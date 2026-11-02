module Delayer #(
    parameter type T,
    parameter CYCLE_DELAY = 1
) (
    input logic clk,
    input T in,
    output T out
);
    T buffer[CYCLE_DELAY-1:0];
    assign out = buffer[CYCLE_DELAY-1];

    always_ff @(posedge clk) begin
        buffer[0] <= in;
        for (int i = 1; i < CYCLE_DELAY; i++) begin
            buffer[i] <= buffer[i - 1];
        end
    end
endmodule
