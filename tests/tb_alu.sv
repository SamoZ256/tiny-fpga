module tb;
    import Rv32AluOp::*;

    Type op;
    logic [31:0] a, b;
    logic [31:0] result;
    logic carry;
    Rv32Alu alu (.op(op), .a(a), .b(b), .result(result), .carry(carry));

    int errors = 0;
    logic [31:0] edge_vals[6] = '{0, 1, 32'hffffffff, 32'h80000000, 32'h7fffffff, 32'h12345678};

    task automatic check_op(input Type o, input logic [32:0] exp, input bit check_carry);
        op = o;
        #1;
        if (result !== exp[31:0] || (check_carry && carry !== exp[32])) begin
            errors++;
            $display("MISMATCH op=%0d a=%h b=%h got=%b/%h exp=%b/%h", o, a, b, carry, result, exp[32], exp[31:0]);
        end
    endtask

    task automatic check;
        check_op(add,  {1'b0, a} + {1'b0, b}, 1);
        check_op(sub,  {1'b0, a} - {1'b0, b}, 1);
        check_op(and_, a & b, 0);
        check_op(or_,  a | b, 0);
        check_op(xor_, a ^ b, 0);
        check_op(sll,  a << b[4:0], 0);
        check_op(srl,  a >> b[4:0], 0);
        check_op(sra,  $signed(a) >>> b[4:0], 0);
    endtask

    initial begin
        foreach (edge_vals[i]) foreach (edge_vals[j]) begin
            a = edge_vals[i];
            b = edge_vals[j];
            check();
        end
        repeat (100000) begin
            a = $urandom;
            b = $urandom;
            check();
        end
        $display("errors=%0d", errors);
        $finish;
    end
endmodule
