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
    logic [CRAM_ADDR_WIDTH-1:0] cram_r_addrs[SPU_LANES];
    logic [CRAM_DATA_WIDTH-1:0] cram_douts[SPU_LANES];
    Vram #(
        .ADDR_WIDTH(CRAM_ADDR_WIDTH),
        .DATA_WIDTH(CRAM_DATA_WIDTH),
        .SIZE      (CRAM_SIZE),
        .NUM_R_PORTS(SPU_LANES)
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
    logic [VRAM_DATA_WIDTH-1:0] vram_dout;
    SinglePortVram #(
        .ADDR_WIDTH(VRAM_ADDR_WIDTH),
        .DATA_WIDTH(VRAM_DATA_WIDTH),
        .SIZE      (VRAM_SIZE)
    ) vram (
        .r_clk(clk),
        .r_addr(vram_r_addr),
        .dout(vram_dout),

        .w_clk(cpu_clk),
        .w_addr(vram_w_addr),
        .w_strobe(vram_w_strobe),
        .din(vram_din)
    );

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
    logic [9:0] cmd_begin_x;
    assign cmd_begin_x = command[12:3];
    logic [9:0] cmd_end_x;
    assign cmd_end_x = command[22:13];

    logic [31:0] cmd_fill_color_raw;
    assign cmd_fill_color_raw = command[54:23];
    Rgba cmd_fill_color;
    assign cmd_fill_color = '{
        rgb: {cmd_fill_color_raw[23:16], cmd_fill_color_raw[15:8], cmd_fill_color_raw[7:0]},
        a: cmd_fill_color_raw[31:24]
    };

    logic [VRAM_ADDR_WIDTH-1:0] cmd_vram_addr;
    assign cmd_vram_addr = command[34:23];

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

    logic [SPU_LANES_LOG2-1:0] crnt_draw_begin;
    assign crnt_draw_begin = crnt_x[SPU_LANES_LOG2-1:0];
    logic [SPU_LANES_LOG2:0] crnt_draw_end;

    logic [9:0] next_x;
    assign next_x = crnt_x + {{(10 - (SPU_LANES_LOG2 + 1)){1'b0}}, crnt_draw_end} - {{(10 - SPU_LANES_LOG2){1'b0}}, crnt_draw_begin};

    enum {
        fill,
        span,
        tiles
    } draw_mode = fill;
    Rgba fill_color;

    always_comb begin
        // CRAM read
        for (int i = 0; i < SPU_LANES; i++) begin
            cram_r_addrs[i] = vram_dout[VRAM_LOGICAL_DATA_WIDTH * i +:VRAM_LOGICAL_DATA_WIDTH];
        end

        crnt_draw_end = '0;
        line_w_addr = '0;
        line_w_strobe = '0;
        lines_din = '{default: '0};

        if (state == execute) begin
            // Line write
            if (crnt_x == crnt_end_x) begin
                crnt_draw_end = '0;
            end else if (crnt_end_x[SPU_LANES_LOG2-1:0] == '0 || crnt_x[9:SPU_LANES_LOG2] != crnt_end_x[9:SPU_LANES_LOG2]) begin
                crnt_draw_end = {1'b1, {SPU_LANES_LOG2{1'b0}}};
            end else begin
                crnt_draw_end = {1'b0, crnt_end_x[SPU_LANES_LOG2-1:0]};
            end
            line_w_addr = crnt_x[LINE_BUFFER_LOGICAL_ADDR_WIDTH-1:SPU_LANES_LOG2];
            line_w_strobe = ((1 << crnt_draw_end) - 1) & ~((1 << crnt_draw_begin) - 1);

            // Line input
            case (draw_mode)
                fill: begin
                    for (int i = 0; i < SPU_LANES; i++) begin
                        lines_din[i] = fill_color;
                    end
                end
                span: begin
                    for (int i = 0; i < SPU_LANES; i++) begin
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
                        crnt_x <= cmd_begin_x;
                        crnt_end_x <= cmd_end_x;
                        draw_mode <= fill;
                        fill_color <= cmd_fill_color;
                        state <= execute;
                        cmdram_r_addr <= cmdram_r_addr + 1;
                    end
                    SpuCommandKind::span: begin
                        crnt_x <= cmd_begin_x;
                        crnt_end_x <= cmd_end_x;
                        draw_mode <= span;
                        vram_r_addr <= cmd_vram_addr; // TODO: support misaligned VRAM reads
                        mem_counter <= 1; // Wait for the memory to get fetched
                        state <= mem;
                    end
                endcase
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
