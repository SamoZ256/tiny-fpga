module PpuMultiplierNormalized8 (
    input logic [7:0] a,
    input logic [7:0] b,

    output logic [7:0] res
);
    logic [15:0] product1;
    assign product1 = {8'b0, a} * {8'b0, b} + 128;

    logic [15:0] product2;
    assign product2 = (product1 + {8'b0, product1[15:8]});

    assign res = product2[15:8];
endmodule
