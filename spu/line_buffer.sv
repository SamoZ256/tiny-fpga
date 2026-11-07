import spu::*;

module SpuLineBuffer (
    input logic clk,

    input logic bank_sel,

    input logic [LINE_BUFFER_LOGICAL_ADDR_WIDTH-1:0] r_addr,
    output Rgb dout,

    input LineBufferLanesAddr w_addr,
    input LineBufferLanesWStrobe w_strobe,
    input RgbaLanes din
);
    logic [LINE_BUFFER_LOGICAL_ADDR_WIDTH-1:0] r_addr_delayed1;
    Delayer #(
        .T(logic [LINE_BUFFER_LOGICAL_ADDR_WIDTH-1:0]),
        .CYCLE_DELAY(1)
    ) r_addr_delayer2(
        .clk(clk),
        .in(r_addr),
        .out(r_addr_delayed1)
    );

    LineBufferLanesAddr w_addr_delayed2;
    Delayer #(
        .T(LineBufferLanesAddr),
        .CYCLE_DELAY(2)
    ) w_addr_delayer2(
        .clk(clk),
        .in(w_addr),
        .out(w_addr_delayed2)
    );

    LineBufferLanesWStrobe w_strobe_delayed2;
    Delayer #(
        .T(LineBufferLanesWStrobe),
        .CYCLE_DELAY(2)
    ) w_strobe_delayer2(
        .clk(clk),
        .in(w_strobe),
        .out(w_strobe_delayed2)
    );

    RgbaLanes din_delayed1;
    Delayer #(
        .T(RgbaLanes),
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
    RgbLanes din_resolved;
    LineBufferLanes douts_raw[2];
    for (genvar i = 0; i < 2; i++) begin : line_buffers
        SinglePortVram #(
            .ADDR_WIDTH(LINE_BUFFER_ADDR_WIDTH),
            .DATA_WIDTH(LINE_BUFFER_DATA_WIDTH),
            .W_STROBE_WIDTH(LANES),
            .SIZE      (LINE_BUFFER_SIZE)
        ) line_buffer (
            .r_clk(clk),
            .r_addr(i == bank_sel ? r_addr[LINE_BUFFER_LOGICAL_ADDR_WIDTH-1:LANES_LOG2] : w_addr),
            .dout(douts_raw[i]),

            .w_clk(clk),
            .w_addr(w_addr_delayed2),
            .w_strobe(i == bank_sel_delayed2 ? '0 : w_strobe_delayed2),
            .din(LineBufferLanes'(din_resolved))
        );
    end

    // Color resolve
    RgbLanes blend_dout;
    assign blend_dout = RgbLanes'(douts_raw[!bank_sel_delayed1]);
    for (genvar i = 0; i < LANES; i++) begin : color_resolvers
        Rgb crnt_blend_dout;
        assign crnt_blend_dout = blend_dout[i];
        SpuColorResolver color_resolver(
            .clk(clk),
            .src(din_delayed1[i]),
           	.dst(crnt_blend_dout),
           	.res(din_resolved[i])
        );
    end

    // Output
    RgbLanes dout_raw;
    assign dout_raw = RgbLanes'(douts_raw[bank_sel]);
    assign dout = dout_raw[r_addr_delayed1[LANES_LOG2-1:0]];
endmodule
