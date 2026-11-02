module tb;
    logic clk = 0;
    always #10 clk = ~clk;

    logic start = 0;
    logic is_signed;
    logic [31:0] a, b;
    wire busy;
    wire [31:0] quotient, remainder;
    Rv32Div div (
        .clk(clk),
        .start(start),
        .is_signed(is_signed),
        .a(a),
        .b(b),
        .busy(busy),
        .quotient(quotient),
        .remainder(remainder)
    );

    int errors = 0;
    logic [31:0] edge_vals[6] = '{0, 1, 32'hffffffff, 32'h80000000, 32'h7fffffff, 32'h12345678};

    task automatic check(input bit sgn);
        logic [31:0] e_q, e_r;
        if (b == 0) begin
            e_q = 32'hffffffff;
            e_r = a;
        end else if (sgn && a == 32'h80000000 && b == 32'hffffffff) begin
            e_q = a;
            e_r = 0;
        end else if (sgn) begin
            e_q = $signed(a) / $signed(b);
            e_r = $signed(a) % $signed(b);
        end else begin
            e_q = a / b;
            e_r = a % b;
        end

        is_signed = sgn;
        start = 1;
        @(posedge clk);
        #1 start = 0;
        while (busy) @(posedge clk);
        #1;
        if (quotient !== e_q || remainder !== e_r) begin
            errors++;
            $display("MISMATCH signed=%0d a=%h b=%h q=%h/%h r=%h/%h", sgn, a, b, quotient, e_q, remainder, e_r);
        end
    endtask

    initial begin
        foreach (edge_vals[i]) foreach (edge_vals[j]) begin
            a = edge_vals[i];
            b = edge_vals[j];
            check(0);
            check(1);
        end
        repeat (20000) begin
            a = $urandom;
            b = $urandom;
            check(0);
            check(1);
        end
        $display("errors=%0d", errors);
        $finish;
    end
endmodule
