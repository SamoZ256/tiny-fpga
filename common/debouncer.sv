module Debouncer #(
    parameter N = 12
) (
    input logic clk,
    input logic in,
    output logic out
);
    logic [N-1:0] buffer = 0;
    assign out = buffer[N-1];

    always_ff @(posedge clk) begin
        if (!buffer[N-1] && in) buffer <= buffer + 1;
        else if (!in) buffer <= 0;
    end
endmodule
