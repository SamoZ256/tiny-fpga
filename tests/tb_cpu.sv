module tb;
    logic clk = 0;
    always #10 clk = ~clk;

    logic vblank = 0;
    always #20000 vblank = ~vblank;

    wire [29:0] ram_addr;
    wire [ 3:0] ram_w_strobe;
    wire [31:0] ram_din;
    wire [31:0] ram_dout;
    logic [31:0] ram_mapped_dout;
    wire fault;

    ram #(
        .ADDR_WIDTH(11),
        .FILENAME  ("/dev/null")
    ) ram (
        .clk(clk),
        .address(ram_addr[10:0]),
        .w_strobe(ram_addr < 2048 ? ram_w_strobe : 4'b0),
        .din(ram_din),
        .dout(ram_dout)
    );

    Rv32Cpu dut (
        .clk(clk),
        .ram_addr(ram_addr),
        .ram_w_strobe(ram_w_strobe),
        .ram_din(ram_din),
        .ram_dout(ram_mapped_dout),
        .fault(fault)
    );

    // Same read map as main.sv
    always_comb begin
        ram_mapped_dout = ram_addr < 2048 ? ram_dout : 32'b0;
        case (ram_addr)
            30'h4000001: ram_mapped_dout = 0;
            30'h4000002: ram_mapped_dout = 640;
            30'h4000003: ram_mapped_dout = 480;
            30'h4000004: ram_mapped_dout = {31'b0, vblank};
        endcase
    end

    int led_writes = 0;
    always @(posedge clk) begin
        if (ram_w_strobe != 0 && ram_addr == 30'h4000000) led_writes++;
        if (ram_w_strobe != 0 && ram_addr == 30'h4000040) begin
            if (ram_din == 1) $display("PASS");
            else $display("FAIL %0d", ram_din >> 1);
            $finish;
        end
        if (fault) begin
            $display("FAULT pc=%h", dut.pc);
            $finish;
        end
    end

    string hex;
    int cycles;
    initial begin
        if (!$value$plusargs("hex=%s", hex)) $fatal(1, "missing +hex=<file>");
        if (!$value$plusargs("cycles=%d", cycles)) cycles = 200000;
        $readmemh(hex, ram.data);
        repeat (cycles) @(posedge clk);
        if ($test$plusargs("smoke") && !fault && led_writes > 0) $display("PASS");
        else $display("TIMEOUT");
        $finish;
    end
endmodule
