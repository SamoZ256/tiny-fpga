// Scanline processing unit

import spu::*;

package SpuCommandKind;
    typedef enum logic[2:0] {
        begin_line = 3'b000, // TODO: implement
        end_line = 3'b001,
        fill = 3'b010,
        span = 3'b011,
        tiles = 3'b100 // TODO: implement
    } Type;
endpackage

module Spu (
    input logic clk,
    input logic cpu_clk,

    input logic [CRAM_ADDR_WIDTH-1:0] cram_w_addr,
    input logic [3:0] cram_w_strobe,
    input logic [CRAM_DATA_WIDTH-1:0] cram_din,

    input logic [VRAM_ADDR_WIDTH-1:0] vram_w_addr,
    input logic [3:0] vram_w_strobe,
    input logic [VRAM_DATA_WIDTH-1:0] vram_din,

    input logic [CMDRAM_ADDR_WIDTH-1:0] cmdram_w_addr,
    input logic [7:0] cmdram_w_strobe,
    input logic [COMMAND_SIZE-1:0] cmdram_din,

    output Rgb color,
    output logic [9:0] cpu_target_line
);
    logic [9:0] x;
    logic [9:0] y;
    VgaCounter #(
        .LINE(vga::LINE),
        .SCREEN(vga::SCREEN),
        .START_X(1), // TODO: will need more once VRAM and CRAM reading is implemented
        .START_Y(1)
    ) counter(
        .clk(clk),
        .x(x),
        .y(y)
    );

    logic [9:0] target_line;
    assign target_line = y == vga::SCREEN ? 0 : y + 1;

    // Bank selector
    logic bank_sel = 0;
    logic [2:0] bank_sync = '0; // [0],[1] = synchronizer, [2] = previous value for edge detect
    //logic cpu_bank_sel = 0;

    always_ff @(posedge cpu_clk) begin
        bank_sync <= {bank_sync[1:0], bank_sel};
        if (bank_sync[2] != bank_sync[1]) begin
            //cpu_bank_sel        <= bank_sync[1];
            cpu_target_line <= target_line;
        end
    end

    // CRAM
    logic [CRAM_ADDR_WIDTH-1:0] cram_r_addrs[LANES];
    logic [CRAM_DATA_WIDTH-1:0] cram_douts[LANES];
    Vram #(
        .ADDR_WIDTH(CRAM_ADDR_WIDTH),
        .DATA_WIDTH(CRAM_DATA_WIDTH),
        .SIZE      (CRAM_SIZE),
        .NUM_R_PORTS(LANES)
    ) cram (
        .r_clks('{default: clk}),
        .r_addrs(cram_r_addrs),
        .douts(cram_douts),

        .w_clk(cpu_clk),
        .w_addr(cram_w_addr),
        .w_strobe(cram_w_strobe),
        .din(cram_din)
    );

    // VRAM
    logic [VRAM_ADDR_WIDTH-1:0] vram_r_addr;
    logic [VRAM_DATA_WIDTH-1:0] vram_douts_raw[2];
    Vram #(
        .ADDR_WIDTH(VRAM_ADDR_WIDTH),
        .DATA_WIDTH(VRAM_DATA_WIDTH),
        .SIZE      (VRAM_SIZE),
        .NUM_R_PORTS(2)
    ) vram (
        .r_clks({clk, clk}),
        .r_addrs({vram_r_addr, vram_r_addr + 1}),
        .douts(vram_douts_raw),

        .w_clk(cpu_clk),
        .w_addr(vram_w_addr),
        .w_strobe(vram_w_strobe),
        .din(vram_din)
    );

    logic [LANES * 2 - 1:0][VRAM_LOGICAL_DATA_WIDTH-1:0] vram_douts;
    always_comb begin
        for (int i = 0; i < 2; i++) begin
            for (int j = 0; j < LANES; j++) begin
                vram_douts[i * LANES + j] = vram_douts_raw[i][VRAM_LOGICAL_DATA_WIDTH * j +:VRAM_LOGICAL_DATA_WIDTH];
            end
        end
    end

    // Command RAM
    logic [CMDRAM_ADDR_WIDTH-1:0] cmdram_r_addr;
    logic [COMMAND_SIZE-1:0] cmdram_douts_raw[2];
    for (genvar i = 0; i < 2; i++) begin : cmdram
        SinglePortVram #(
            .ADDR_WIDTH(CMDRAM_ADDR_WIDTH),
            .DATA_WIDTH(COMMAND_SIZE),
            .SIZE      (CMDRAM_SIZE)
        ) cmdram (
            .r_clk(clk),
            .r_addr(cmdram_r_addr),
            .dout(cmdram_douts_raw[i]),

            .w_clk(cpu_clk),
            .w_addr(cmdram_w_addr),
            .w_strobe(i == !bank_sel ? cmdram_w_strobe : '0), // TODO: use cpu_bank_sel?
            .din(cmdram_din)
        );
    end

    logic [COMMAND_SIZE-1:0] command;
    assign command = cmdram_douts_raw[bank_sel];

    // Line buffer
    RgbaLanes lines_din;
    LineBufferLanesAddr line_w_addr;
    LineBufferLanesWStrobe line_w_strobe;
    SpuLineBuffer line_buffer(
        .clk(clk),
        .bank_sel(bank_sel),
        .r_addr(x),
        .dout(color),
        .w_addr(line_w_addr),
        .w_strobe(line_w_strobe),
        .din(lines_din)
    );

    // Command
    SpuCommandKind::Type cmd_kind;
    assign cmd_kind = SpuCommandKind::Type'(command[2:0]);

    typedef struct packed {
        logic [8:0] reserved;
        Rgba color;
        logic [9:0] end_x;
        logic [9:0] begin_x;
    } FillParam;
    FillParam fill_param;
    assign fill_param = FillParam'(command[63:3]);

    typedef struct packed {
        logic [27:0] reserved;
        logic [11:0] vram_addr;
        logic [9:0] end_x;
        logic [9:0] begin_x;
    } SpanParam;
    SpanParam span_param;
    assign span_param = SpanParam'(command[63:3]);

    typedef struct packed {
        logic [8:0] reserved;
        logic [2:0] tile_stride_log2;
        logic [2:0] tile_width_log2;
        logic [13:0] tileset_vram_addr;
        logic [7:0] tile_count;
        logic [13:0] tilemap_vram_addr;
        logic [9:0] begin_x;
    } TilesParam;
    TilesParam tiles_param;
    assign tiles_param = TilesParam'(command[63:3]);

    // Command execution
    enum {
        fetch,
        decode,
        mem,
        execute,
        done
    } state = done;
    logic [1:0] mem_counter = 0;

    logic [9:0] crnt_x = 0;
    logic [9:0] crnt_end_x = 0;

    logic [LANES_LOG2-1:0] crnt_draw_begin;
    assign crnt_draw_begin = crnt_x[LANES_LOG2-1:0];
    logic [LANES_LOG2:0] crnt_draw_end;

    logic [9:0] next_x;
    assign next_x = crnt_x + {{(10 - (LANES_LOG2 + 1)){1'b0}}, crnt_draw_end} - {{(10 - LANES_LOG2){1'b0}}, crnt_draw_begin};

    enum {
        fill,
        span,
        tiles
    } draw_mode = fill;
    Rgba fill_color;
    logic [LANES_LOG2-1:0] vram_dout_offset_neg;

    always_comb begin
        // CRAM read
        for (int i = 0; i < LANES; i++) begin
            cram_r_addrs[i] = vram_douts[i + LANES - vram_dout_offset_neg];
        end

        crnt_draw_end = '0;
        line_w_addr = '0;
        line_w_strobe = '0;
        lines_din = '{default: '0};

        if (state == execute) begin
            // Line write
            if (crnt_x == crnt_end_x) begin
                crnt_draw_end = '0;
            end else if (crnt_end_x[LANES_LOG2-1:0] == '0 || crnt_x[9:LANES_LOG2] != crnt_end_x[9:LANES_LOG2]) begin
                crnt_draw_end = {1'b1, {LANES_LOG2{1'b0}}};
            end else begin
                crnt_draw_end = {1'b0, crnt_end_x[LANES_LOG2-1:0]};
            end
            line_w_addr = crnt_x[LINE_BUFFER_LOGICAL_ADDR_WIDTH-1:LANES_LOG2];
            line_w_strobe = ((1 << crnt_draw_end) - 1) & ~((1 << crnt_draw_begin) - 1);

            // Line input
            case (draw_mode)
                fill: begin
                    for (int i = 0; i < LANES; i++) begin
                        lines_din[i] = fill_color;
                    end
                end
                span: begin
                    for (int i = 0; i < LANES; i++) begin
                        lines_din[i] = Rgba'(cram_douts[i]);
                    end
                end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        // VRAM advance
        case (draw_mode)
            span: begin
                vram_r_addr <= vram_r_addr + 1;
            end
        endcase

        if (x == vga::LINE) begin
            // Reset
            cmdram_r_addr <= 0;
            mem_counter <= 0;
            crnt_x <= 0;
            crnt_end_x <= 0;
            state <= fetch;
            bank_sel <= !bank_sel;
        end else case (state)
            fetch: state <= decode; // Wait 1 cycle for the data
            decode: begin
                case (cmd_kind)
                    SpuCommandKind::end_line: begin
                        state <= done;
                    end
                    SpuCommandKind::fill: begin
                        crnt_x <= fill_param.begin_x;
                        crnt_end_x <= fill_param.end_x;
                        draw_mode <= fill;
                        fill_color <= fill_param.color;
                        state <= execute;
                    end
                    SpuCommandKind::span: begin
                        crnt_x <= span_param.begin_x;
                        crnt_end_x <= span_param.end_x;
                        draw_mode <= span;
                        vram_r_addr <= span_param.vram_addr - 1;
                        vram_dout_offset_neg <= span_param.begin_x[LANES_LOG2-1:0];
                        mem_counter <= 1; // Wait for the memory to get fetched
                        state <= mem;
                    end
                endcase

                // Increment
                cmdram_r_addr <= cmdram_r_addr + 1;
            end
            mem: begin
                if (mem_counter == '0) begin
                    state <= execute;
                end else begin
                    mem_counter <= mem_counter - 1;
                end
            end
            execute: begin
                if (next_x == crnt_end_x) begin
                    state <= decode; // We can skip directly to decode
                end else begin
                    crnt_x <= next_x;
                end
            end
            done: ;
        endcase
    end
endmodule
