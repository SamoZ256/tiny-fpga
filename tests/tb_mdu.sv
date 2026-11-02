module tb;
    logic [31:0] a, b;
    logic [63:0] r_mul, r_mulsu, r_mulu;
    Rv32Mdu m0 (.op(Rv32MduOp::mul),   .a(a), .b(b), .result(r_mul));
    Rv32Mdu m1 (.op(Rv32MduOp::mulsu), .a(a), .b(b), .result(r_mulsu));
    Rv32Mdu m2 (.op(Rv32MduOp::mulu),  .a(a), .b(b), .result(r_mulu));

    int errors = 0;
    logic [31:0] edge_vals[6] = '{0, 1, 32'hffffffff, 32'h80000000, 32'h7fffffff, 32'h12345678};

    task automatic check;
        longint sa, sb;
        logic [63:0] e_mul, e_mulsu, e_mulu;
        #1;
        sa = longint'($signed(a));
        sb = longint'($signed(b));
        e_mul   = sa * sb;
        e_mulsu = sa * longint'({32'b0, b});
        e_mulu  = {32'b0, a} * {32'b0, b};
        if (r_mul !== e_mul || r_mulsu !== e_mulsu || r_mulu !== e_mulu) begin
            errors++;
            $display("MISMATCH a=%h b=%h mul=%h/%h mulsu=%h/%h mulu=%h/%h",
                     a, b, r_mul, e_mul, r_mulsu, e_mulsu, r_mulu, e_mulu);
        end
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
