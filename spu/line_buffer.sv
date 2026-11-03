import spu::*;

module SpuLineBuffer (
    input logic clk,

    input logic bank_sel,

    input logic [LINE_BUFFER_ADDR_WIDTH-1:0] r_addr,
    output Rgb dout,

    input logic [LINE_BUFFER_ADDR_WIDTH-1:0] w_addr,
    input logic w_strobe,
    input Rgba din
);
    logic [LINE_BUFFER_ADDR_WIDTH-1:0] w_addr_delayed2;
    Delayer #(
        .T(logic [LINE_BUFFER_ADDR_WIDTH-1:0]),
        .CYCLE_DELAY(2)
    ) w_addr_delayer2(
        .clk(clk),
        .in(w_addr),
        .out(w_addr_delayed2)
    );

    logic w_strobe_delayed2;
    Delayer #(
        .T(logic),
        .CYCLE_DELAY(2)
    ) w_strobe_delayer2(
        .clk(clk),
        .in(w_strobe),
        .out(w_strobe_delayed2)
    );

    Rgba din_delayed1;
    Delayer #(
        .T(Rgba),
        .CYCLE_DELAY(1)
    ) din_delayer1(
        .clk(clk),
        .in(din),
        .out(din_delayed1)
    );

    logic bank_sel_delayed1;
    Delayer #(
        .T(logic),
        .CYCLE_DELAY(1)
    ) bank_sel_delayer1(
        .clk(clk),
        .in(bank_sel),
        .out(bank_sel_delayed1)
    );

    logic bank_sel_delayed2;
    Delayer #(
        .T(logic),
        .CYCLE_DELAY(1)
    ) bank_sel_delayer2(
        .clk(clk),
        .in(bank_sel_delayed1),
        .out(bank_sel_delayed2)
    );

    // Buffers
    Rgba din_resolved;
    logic [LINE_BUFFER_DATA_WIDTH-1:0] douts_raw[2];
    for (genvar i = 0; i < 2; i++) begin : line_buffers
        SinglePortVram #(
            .ADDR_WIDTH(LINE_BUFFER_ADDR_WIDTH),
            .DATA_WIDTH(LINE_BUFFER_DATA_WIDTH),
            .W_STROBE_WIDTH(1),
            .SIZE      (LINE_BUFFER_SIZE)
        ) line_buffer (
            .r_clk(clk),
            .r_addr(i == bank_sel ? r_addr : w_addr),
            .dout(douts_raw[i]),

            .w_clk(clk),
            .w_addr(w_addr_delayed2),
            .w_strobe(i == bank_sel_delayed2 ? '0 : w_strobe_delayed2),
            .din({din_resolved.a, din_resolved.rgb[2], din_resolved.rgb[1], din_resolved.rgb[0]})
        );
    end

    // Color resolve
    logic [LINE_BUFFER_DATA_WIDTH-1:0] blend_dout_raw;
    assign blend_dout_raw = douts_raw[!bank_sel_delayed1];
    SpuColorResolver color_resolver(
        .clk(clk),
        .src(din_delayed1),
       	.dst('{
                rgb: {blend_dout_raw[7:0], blend_dout_raw[15:8], blend_dout_raw[23:16]},
                a: blend_dout_raw[31:24]
            }),
       	.res(din_resolved)
    );

    // Output
    logic [LINE_BUFFER_DATA_WIDTH-1:0] dout_raw;
    assign dout_raw = douts_raw[bank_sel];
    assign dout = {dout_raw[7:0], dout_raw[15:8], dout_raw[23:16]};
endmodule
