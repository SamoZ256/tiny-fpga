package Rv32MduOp;
    typedef enum {
        mul,
        mulsu,
        mulu
    } Type;
endpackage

module Rv32Mdu #(
    parameter XLEN = 32
) (
    input Rv32MduOp::Type op,
    input logic [XLEN-1:0] a,
    input logic [XLEN-1:0] b,
    output logic [XLEN*2-1:0] result
);
    logic a_sign;
    logic b_sign;
    logic [XLEN*2+1:0] full_res;
    always_comb begin
        a_sign = 1'b0;
        b_sign = 1'b0;
        unique case (op)
            Rv32MduOp::mul: begin
                a_sign = a[XLEN-1];
                b_sign = b[XLEN-1];
            end
            Rv32MduOp::mulsu: a_sign = a[XLEN-1];
            Rv32MduOp::mulu: ;
        endcase

        full_res = $signed({a_sign, a}) * $signed({b_sign, b});
        result = full_res[XLEN*2-1:0];
    end

endmodule
