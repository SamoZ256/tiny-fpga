// Scanline processing unit

import spu::*;

package SpuCommandKind;
    typedef enum logic[2:0] {
        begin_line = 3'b000, // TODO: implement
        end_line = 3'b001,
        fill = 3'b010,
        span = 3'b011, // TODO: implement
        tiles = 3'b100 // TODO: implement
    } Type;
endpackage

module Spu (
    input logic clk,
    input logic cpu_clk,

    input logic [CRAM_ADDR_WIDTH-1:0] cram_w_addr,
    input logic [2:0] cram_w_strobe,
    input logic [CRAM_DATA_WIDTH-1:0] cram_din,

    input logic [VRAM_ADDR_WIDTH-1:0] vram_w_addr,
    input logic vram_w_strobe,
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
    wire [CRAM_ADDR_WIDTH-1:0] cram_r_addr;
    wire [CRAM_DATA_WIDTH-1:0] cram_dout;
    SinglePortVram #(
        .ADDR_WIDTH(CRAM_ADDR_WIDTH),
        .DATA_WIDTH(CRAM_DATA_WIDTH),
        .SIZE      (CRAM_SIZE)
    ) cram (
        .r_clk(clk),
        .r_addr(cram_r_addr),
        .dout(cram_dout),

        .w_clk(cpu_clk),
        .w_addr(cram_w_addr),
        .w_strobe(cram_w_strobe),
        .din(cram_din)
    );

    // VRAM
    logic [VRAM_ADDR_WIDTH-1:0] vram_r_addr;
    wire [VRAM_DATA_WIDTH-1:0] vram_dout;
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
    wire [COMMAND_SIZE-1:0] cmdram_douts_raw[2];
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
    Rgba line_din;
    logic [LINE_BUFFER_ADDR_WIDTH-1:0] line_w_addr;
    logic line_w_strobe;
    SpuLineBuffer line_buffer(
        .clk(clk),
        .bank_sel(bank_sel),
        .r_addr(x),
        .dout(color),
        .w_addr(line_w_addr),
        .w_strobe(line_w_strobe),
        .din(line_din)
    );

    // Command
    SpuCommandKind::Type cmd_kind;
    assign cmd_kind = SpuCommandKind::Type'(command[2:0]);
    logic [9:0] cmd_x;
    assign cmd_x = command[12:3];
    logic [9:0] cmd_len_minus_one;
    assign cmd_len_minus_one = command[22:13];
    logic [31:0] cmd_fill_color_raw;
    assign cmd_fill_color_raw = command[54:23];
    Rgba cmd_fill_color;
    assign cmd_fill_color = '{
        rgb: {cmd_fill_color_raw[7:0], cmd_fill_color_raw[15:8], cmd_fill_color_raw[23:16]},
        a: cmd_fill_color_raw[31:24]
    };

    // Command execution
    enum {
        fetch,
        decode,
        execute,
        done
    } state = done;
    logic [9:0] cmd_cycles = 0;
    Rgba fill_color;

    always_comb begin
        // TODO: more complex
        line_din = fill_color;
    end

    always_ff @(posedge clk) begin
        line_w_strobe <= 0;

        if (x == vga::LINE) begin
            // Reset
            cmdram_r_addr <= 0;
            cmd_cycles <= 0;
            state <= fetch;
            bank_sel <= !bank_sel;
        end else case (state)
            // Next command
            fetch: state <= decode; // Wait 1 cycle for the data
            decode: begin
                case (cmd_kind)
                    SpuCommandKind::end_line: begin
                        state <= done;
                    end
                    SpuCommandKind::fill: begin
                        line_w_addr <= cmd_x;
                        line_w_strobe <= 1;
                        cmd_cycles <= cmd_len_minus_one;
                        fill_color <= cmd_fill_color;
                        state <= execute;
                    end
                endcase
                cmdram_r_addr <= cmdram_r_addr + 1;
            end
            execute: begin
                if (cmd_cycles == '0) begin
                    state <= fetch;
                end else begin
                    line_w_addr <= line_w_addr + 1;
                    line_w_strobe <= 1;
                    cmd_cycles <= cmd_cycles - 1;
                end
            end
            done: ;
        endcase
    end
endmodule
