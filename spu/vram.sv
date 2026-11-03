module Vram #(
    parameter ADDR_WIDTH,
    parameter DATA_WIDTH,
    parameter W_STROBE_WIDTH = (DATA_WIDTH + 7) / 8,
    parameter DATA_ELEMENT_WIDTH = DATA_WIDTH / W_STROBE_WIDTH,
    parameter SIZE,
    parameter NUM_R_PORTS = 1
) (
    input logic                                   r_clks[NUM_R_PORTS],
    input logic      [            ADDR_WIDTH-1:0] r_addrs[NUM_R_PORTS],
    output logic [            DATA_WIDTH-1:0] douts[NUM_R_PORTS],

    input logic                                   w_clk,
    input logic      [            ADDR_WIDTH-1:0] w_addr,
    input logic      [W_STROBE_WIDTH-1:0] w_strobe,
    input logic      [            DATA_WIDTH-1:0] din
);
    logic [DATA_WIDTH-1:0] data[SIZE];

    // Read
    for (genvar p = 0; p < NUM_R_PORTS; p++) begin : gen_read
        always_ff @(posedge r_clks[p]) begin
            douts[p] <= data[r_addrs[p]];
        end
    end

    // Write
    always_ff @(posedge w_clk) begin
        for (int i = 0; i < W_STROBE_WIDTH; i++) begin
            if (w_strobe[i]) begin
                data[w_addr][(i*DATA_ELEMENT_WIDTH)+:DATA_ELEMENT_WIDTH] <= din[(i*DATA_ELEMENT_WIDTH)+:DATA_ELEMENT_WIDTH];
            end
        end
    end
endmodule

module SinglePortVram #(
    parameter ADDR_WIDTH,
    parameter DATA_WIDTH,
    parameter W_STROBE_WIDTH = (DATA_WIDTH + 7) / 8,
    parameter DATA_ELEMENT_WIDTH = DATA_WIDTH / W_STROBE_WIDTH,
    parameter SIZE
) (
    input logic                                   r_clk,
    input logic      [            ADDR_WIDTH-1:0] r_addr,
    output logic [            DATA_WIDTH-1:0] dout,

    input logic                                   w_clk,
    input logic      [            ADDR_WIDTH-1:0] w_addr,
    input logic      [W_STROBE_WIDTH-1:0] w_strobe,
    input logic      [            DATA_WIDTH-1:0] din
);
    wire r_clks[1] = {r_clk};
    wire [ADDR_WIDTH-1:0] r_addrs[1] = {r_addr};
    logic [DATA_WIDTH-1:0] douts[1];
    assign dout = douts[0];

    Vram #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .W_STROBE_WIDTH(W_STROBE_WIDTH),
        .DATA_ELEMENT_WIDTH(DATA_ELEMENT_WIDTH),
        .SIZE(SIZE)
    ) vram (
        .r_clks(r_clks),
        .r_addrs(r_addrs),
        .douts(douts),
        .w_clk(w_clk),
        .w_addr(w_addr),
        .w_strobe(w_strobe),
        .din(din)
    );
endmodule
