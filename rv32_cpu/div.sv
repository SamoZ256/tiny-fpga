module Rv32Div #(
    parameter XLEN = 32
) (
    input logic clk,

    input logic start,
    input logic is_signed,
    input logic [XLEN-1:0] a,
    input logic [XLEN-1:0] b,

    output logic busy = 1'b0,
    output logic [XLEN-1:0] quotient,
    output logic [XLEN-1:0] remainder
);
    logic [XLEN-1:0] dividend;
    logic [XLEN-1:0] divisor;
    logic [XLEN-1:0] q;
    logic [XLEN-1:0] r;
    logic neg_q;
    logic neg_r;
    logic [$clog2(XLEN)-1:0] count;

    wire [XLEN:0] r_next = {r, dividend[XLEN-1]};
    wire r_ge = r_next >= {1'b0, divisor};

    always_ff @(posedge clk) begin
        if (start) begin
            dividend <= is_signed && a[XLEN-1] ? -a : a;
            divisor  <= is_signed && b[XLEN-1] ? -b : b;
            neg_q    <= is_signed && (a[XLEN-1] ^ b[XLEN-1]) && b != 0;
            neg_r    <= is_signed && a[XLEN-1];
            q        <= 0;
            r        <= 0;
            count    <= 0;
            busy     <= 1'b1;
        end else if (busy) begin
            r        <= r_ge ? r_next[XLEN-1:0] - divisor : r_next[XLEN-1:0];
            q        <= {q[XLEN-2:0], r_ge};
            dividend <= dividend << 1;
            count    <= count + 1;
            if (count == XLEN - 1) busy <= 1'b0;
        end
    end

    assign quotient  = neg_q ? -q : q;
    assign remainder = neg_r ? -r : r;
endmodule
