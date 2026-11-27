module ram #(
    parameter XLEN = 32,
    parameter ADDR_WIDTH,
    parameter FILENAME,
    localparam W_STROBE_WIDTH = (XLEN + 7) / 8
) (
    input logic                             clk,
    input logic        [    ADDR_WIDTH-1:0] address,
    input logic        [W_STROBE_WIDTH-1:0] w_strobe,
    input logic        [          XLEN-1:0] din,
    output logic [          XLEN-1:0] dout
);
    logic [XLEN-1:0] data[0:2**ADDR_WIDTH-1];

    initial $readmemh(FILENAME, data);

    // Plain always: always_ff may not share `data` with the $readmemh initial block
    always @(posedge clk) begin
        dout <= data[address];
        for (int i = 0; i < W_STROBE_WIDTH; i = i + 1) begin
            if (w_strobe[i]) begin
                data[address][(i*8)+:8] <= din[(i*8)+:8];
            end
        end
    end

endmodule
