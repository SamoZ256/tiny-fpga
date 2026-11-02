module VgaCounter #(
    parameter LINE,
    parameter SCREEN,
    parameter START_X = 0
) (
    input wire clk,

    output logic [9:0] x = START_X,
    output logic [9:0] y = 0
);
    always_ff @(posedge clk) begin
        if (x == LINE) begin
            x <= 0;
            y <= (y == SCREEN) ? 0 : y + 1;
        end else begin
            x <= x + 1;
        end
    end
endmodule
