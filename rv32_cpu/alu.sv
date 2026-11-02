package Rv32AluOp;
    typedef enum {
        add,
        sub,
        and_,
        or_,
        xor_,
        sll,
        srl,
        sra
    } Type;
endpackage

module Rv32Alu #(
    parameter XLEN = 32
) (
    input Rv32AluOp::Type op,
    input logic [XLEN-1:0] a,
    input logic [XLEN-1:0] b,
    output logic [XLEN-1:0] result,
    output logic carry
);
    localparam SHIFT_BITS = $clog2(XLEN);

    logic [XLEN:0] full_res;

    always_comb begin
        result   = 0;
        carry    = 0;
        full_res = 0;
        unique case (op)
            Rv32AluOp::add: begin
                full_res = a + b;
                result = full_res[XLEN-1:0];
                carry = full_res[XLEN];
            end
            Rv32AluOp::sub: begin
                full_res = a - b;
                result = full_res[XLEN-1:0];
                carry = full_res[XLEN];
            end
            Rv32AluOp::and_: result = a & b;
            Rv32AluOp::or_:  result = a | b;
            Rv32AluOp::xor_: result = a ^ b;
            Rv32AluOp::sll:  result = a << b[SHIFT_BITS-1:0];
            Rv32AluOp::srl:  result = a >> b[SHIFT_BITS-1:0];
            Rv32AluOp::sra:  result = $signed(a) >>> b[SHIFT_BITS-1:0];
        endcase
    end

endmodule
