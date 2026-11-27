// Picture processing unit

import ppu::*;

package PpuCommandKind;
    typedef enum logic [2:0] {
        begin_line = 3'b000,  // TODO: implement
        end_line = 3'b001,
        fill = 3'b010,
        span = 3'b011,
        tiles = 3'b100  // TODO: implement
    } Type;
endpackage

module Ppu (
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
        .START_X(1),  // TODO: will need more once VRAM and CRAM reading is implemented
        .START_Y(1)
    ) counter (
        .clk(clk),
        .x  (x),
        .y  (y)
    );

    logic [9:0] target_line;
    assign target_line = y == vga::SCREEN ? 0 : y + 1;

    // Bank selector
    logic bank_sel = 0;
    logic [2:0] bank_sync = '0;  // [0],[1] = synchronizer, [2] = previous value for edge detect
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
    logic [CRAM_DATA_WIDTH-1:0] cram_douts  [LANES];
    Vram #(
        .ADDR_WIDTH (CRAM_ADDR_WIDTH),
        .DATA_WIDTH (CRAM_DATA_WIDTH),
        .SIZE       (CRAM_SIZE),
        .NUM_R_PORTS(LANES)
    ) cram (
        .r_clks ('{default: clk}),
        .r_addrs(cram_r_addrs),
        .douts  (cram_douts),

        .w_clk(cpu_clk),
        .w_addr(cram_w_addr),
        .w_strobe(cram_w_strobe),
        .din(cram_din)
    );

    // VRAM
    logic [VRAM_ADDR_WIDTH-1:0] vram_r_addr;
    logic [VRAM_DATA_WIDTH-1:0] vram_douts_raw[2];
    Vram #(
        .ADDR_WIDTH (VRAM_ADDR_WIDTH),
        .DATA_WIDTH (VRAM_DATA_WIDTH),
        .SIZE       (VRAM_SIZE),
        .NUM_R_PORTS(2)
    ) vram (
        .r_clks ({clk, clk}),
        .r_addrs({vram_r_addr, vram_r_addr + 1}),
        .douts  (vram_douts_raw),

        .w_clk(cpu_clk),
        .w_addr(vram_w_addr),
        .w_strobe(vram_w_strobe),
        .din(vram_din)
    );

    logic [VRAM_DATA_WIDTH * 2 - 1:0] vram_douts;
    assign vram_douts = {vram_douts_raw[1], vram_douts_raw[0]};

    // Command RAM
    logic [CMDRAM_ADDR_WIDTH-1:0] cmdram_r_addr;
    logic [COMMAND_SIZE-1:0] cmdram_douts_raw[2];
    for (genvar i = 0; i < 2; i++) begin : cmdram
        SinglePortVram #(
            .ADDR_WIDTH(CMDRAM_ADDR_WIDTH),
            .DATA_WIDTH(COMMAND_SIZE),
            .SIZE      (CMDRAM_SIZE)
        ) cmdram (
            .r_clk (clk),
            .r_addr(cmdram_r_addr),
            .dout  (cmdram_douts_raw[i]),

            .w_clk(cpu_clk),
            .w_addr(cmdram_w_addr),
            .w_strobe(i == !bank_sel ? cmdram_w_strobe : '0),  // TODO: use cpu_bank_sel?
            .din(cmdram_din)
        );
    end

    logic [COMMAND_SIZE-1:0] command;
    assign command = cmdram_douts_raw[bank_sel];

    // Line buffer
    RgbaLanes lines_din;
    LineBufferLanesAddr line_w_addr;
    LineBufferLanesWStrobe line_w_strobe;
    PpuLineBuffer line_buffer (
        .clk(clk),
        .bank_sel(bank_sel),
        .r_addr(x),
        .dout(color),
        .w_addr(line_w_addr),
        .w_strobe(line_w_strobe),
        .din(lines_din)
    );

    // Command
    PpuCommandKind::Type cmd_kind;
    assign cmd_kind = PpuCommandKind::Type'(command[2:0]);

    typedef struct packed {
        logic [8:0] reserved;
        Rgba color;
        logic [9:0] end_x;
        logic [9:0] begin_x;
    } FillParam;
    FillParam fill_param;
    assign fill_param = FillParam'(command[63:3]);

    typedef struct packed {
        logic [7:0]  cram_addr_offset;
        logic [4:0]  vram_bit_offset;
        logic [1:0]  vram_bits_log2;
        logic [11:0] vram_addr;
        logic [9:0] len;
        logic [9:0]  begin_x;
    } Span;

    typedef struct packed {
        logic [13:0] reserved;
        Span span;
    } SpanParam;
    SpanParam span_param;
    assign span_param = SpanParam'(command[63:3]);

    typedef struct packed {
        logic reserved;
        logic [7:0] cram_addr_offset;
        logic [1:0] vram_bits_log2;
        logic [2:0] tile_stride_log2;
        logic [2:0] tile_width_log2;
        logic [13:0] tileset_vram_logical_addr;
        logic [7:0] tile_count;
        logic [11:0] tilemap_vram_addr;
        logic [9:0] begin_x;
    } TilesParam;
    TilesParam tiles_param;

    // Command execution
    typedef enum {
        State_decode,
        State_wait,
        State_span_prepare,
        State_span_fetch,
        State_tiles_prepare,
        State_tiles_fetch
    } State;
    State state = State_wait;
    State draw_end_return_state;
    logic [1:0] mem_counter = 0;

    logic [9:0] crnt_x = 0;
    logic [9:0] crnt_end_x = 0;

    logic [LANES_LOG2-1:0] crnt_draw_begin;
    assign crnt_draw_begin = crnt_x[LANES_LOG2-1:0];
    logic [LANES_LOG2:0] crnt_draw_end;

    logic [9:0] next_x;
    assign next_x = crnt_x + {{(10 - (LANES_LOG2 + 1)) {1'b0}}, crnt_draw_end} - {{(10 - LANES_LOG2) {1'b0}}, crnt_draw_begin};

    enum {
        DrawSource_constant,
        DrawSource_mem
    } draw_source = DrawSource_constant;
    Rgba fill_color;

    Span span;
    logic [$clog2(VRAM_DATA_WIDTH):0] span_vram_dout_bit_offset;
    assign span_vram_dout_bit_offset = 6'(LANES * VRAM_LOGICAL_DATA_WIDTH) - (6'(span.begin_x[LANES_LOG2-1:0]) << span.vram_bits_log2) + 6'(span.vram_bit_offset);

    logic [7:0] tile;

    logic [$clog2(VRAM_DATA_WIDTH):0] vram_dout_bit_offset;
    logic [$clog2(VRAM_DATA_WIDTH)+1:0] next_vram_dout_bit_offset;
    assign next_vram_dout_bit_offset = vram_dout_bit_offset + (LANES << span.vram_bits_log2);

    logic [$clog2(VRAM_DATA_WIDTH):0] vram_dout_bit_offset_delayed1;
    Delayer #(
        .T(logic [$clog2(VRAM_DATA_WIDTH):0])
    ) delayer (
        .clk(clk),
        .in (vram_dout_bit_offset),
        .out(vram_dout_bit_offset_delayed1)
    );

    logic draw_enable = 0;

    always_comb begin
        // CRAM read
        for (int unsigned i = 0; i < LANES; i++) begin
            cram_r_addrs[i] = span.cram_addr_offset + (8'(vram_douts >> ((6'(i) << span.vram_bits_log2) + vram_dout_bit_offset_delayed1)) & ((1 << (1 << span.vram_bits_log2)) - 1));
        end

        crnt_draw_end = '0;
        line_w_addr = '0;
        line_w_strobe = '0;
        lines_din = '{default: '0};

        if (draw_enable) begin
            // Line write
            if (crnt_x == crnt_end_x) begin
                crnt_draw_end = '0;
            end else if (crnt_end_x[LANES_LOG2-1:0] == '0 || crnt_x[9:LANES_LOG2] != crnt_end_x[9:LANES_LOG2]) begin
                crnt_draw_end = {1'b1, {LANES_LOG2{1'b0}}};
            end else begin
                crnt_draw_end = {1'b0, crnt_end_x[LANES_LOG2-1:0]};
            end
            line_w_addr   = crnt_x[LINE_BUFFER_LOGICAL_ADDR_WIDTH-1:LANES_LOG2];
            line_w_strobe = ((1 << crnt_draw_end) - 1) & ~((1 << crnt_draw_begin) - 1);

            // Line input
            case (draw_source)
                DrawSource_constant: begin
                    for (int unsigned i = 0; i < LANES; i++) begin
                        lines_din[i] = fill_color;
                    end
                end
                DrawSource_mem: begin
                    for (int unsigned i = 0; i < LANES; i++) begin
                        lines_din[i] = Rgba'(cram_douts[i]);
                    end
                end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (x == vga::LINE - 1) begin
            // Fetch next command
            cmdram_r_addr <= 0;
        end else if (x == vga::LINE) begin
            // Reset
            mem_counter <= 0;
            crnt_x <= 0;
            crnt_end_x <= 0;
            draw_enable <= 0;
            state <= State_decode;
            bank_sel <= !bank_sel;
        end else begin
            case (state)
                State_decode: begin
                    case (cmd_kind)
                        PpuCommandKind::end_line: begin
                            state <= State_wait;
                        end
                        PpuCommandKind::fill: begin
                            crnt_x <= fill_param.begin_x;
                            crnt_end_x <= fill_param.end_x;
                            draw_source <= DrawSource_constant;
                            fill_color <= fill_param.color;
                            draw_enable <= 1;
                            state <= State_wait;
                            draw_end_return_state <= State_decode;
                        end
                        PpuCommandKind::span: begin
                            span <= span_param.span;
                            draw_source <= DrawSource_mem;
                            state <= State_span_prepare;
                            draw_end_return_state <= State_decode;
                        end
                        PpuCommandKind::tiles: begin
                            draw_source <= DrawSource_mem;
                            tiles_param <= TilesParam'(command[63:3]);
                            tile <= 0;
                            state <= State_tiles_prepare;
                            draw_end_return_state <= State_tiles_prepare;
                        end
                    endcase

                    cmdram_r_addr <= cmdram_r_addr + 1;
                end
                State_span_prepare: begin
                    crnt_x <= span.begin_x;
                    crnt_end_x <= span.begin_x + span.len;
                    vram_r_addr <= span.vram_addr - 1 + 12'(span_vram_dout_bit_offset[$clog2(VRAM_DATA_WIDTH)]);
                    vram_dout_bit_offset <= {1'b0, span_vram_dout_bit_offset[$clog2(VRAM_DATA_WIDTH)-1:0]};
                    mem_counter <= 1;  // Wait for the memory to get fetched
                    state <= State_span_fetch;
                end
                State_span_fetch: begin
                    if (mem_counter == 0) begin
                        draw_enable <= 1;
                    end else begin
                        mem_counter <= mem_counter - 1;
                    end

                    if (next_vram_dout_bit_offset[$clog2(VRAM_DATA_WIDTH)]) begin
                        vram_r_addr <= vram_r_addr + 1;
                    end
                    vram_dout_bit_offset <= {1'b0, next_vram_dout_bit_offset[$clog2(VRAM_DATA_WIDTH)-1:0]};
                end
                State_tiles_prepare: begin
                    if (tile < tiles_param.tile_count) begin
                        vram_r_addr <= tiles_param.tilemap_vram_addr + 12'(tile[7:LANES_LOG2]);
                        mem_counter <= 1;  // Wait for the memory to get fetched
                        state <= State_tiles_fetch;
                    end else begin
                        state <= State_decode;
                    end
                end
                State_tiles_fetch: begin
                    if (mem_counter == 0) begin
                        span <= '{
                            begin_x: tiles_param.begin_x + (10'(tile) << tiles_param.tile_width_log2),
                            len: 1 << tiles_param.tile_width_log2,
                            vram_addr: tiles_param.tileset_vram_logical_addr[VRAM_LOGICAL_ADDR_WIDTH-1:2] + ({4'b0, vram_douts[32'(tile[LANES_LOG2-1:0]) * VRAM_LOGICAL_DATA_WIDTH +: VRAM_LOGICAL_DATA_WIDTH]} << tiles_param.tile_stride_log2),
                            vram_bits_log2: tiles_param.vram_bits_log2,
                            vram_bit_offset: {3'b0, tiles_param.tileset_vram_logical_addr[1:0]} * VRAM_LOGICAL_DATA_WIDTH,
                            cram_addr_offset: tiles_param.cram_addr_offset
                        };
                        tile <= tile + 1;
                        state <= State_span_prepare;
                    end else begin
                        mem_counter <= mem_counter - 1;
                    end
                end
                State_wait:  ;
            endcase

            if (draw_enable) begin
                if (next_x == crnt_end_x) begin
                    crnt_x <= 0;
                    crnt_end_x <= 0;
                    draw_enable <= 0;
                    state <= draw_end_return_state;
                end else begin
                    crnt_x <= next_x;
                end
            end
        end
    end
endmodule
