import spu::*;

// NOTE: latency is 1 cycle
module SpuColorResolver (
    input logic clk,

    input Rgba src, // Premultiplied
    input Rgb dst, // Premultiplied

    output Rgb res // Premultiplied
);
    logic [7:0] one_minus_src_a;
    assign one_minus_src_a = 8'hff - src.a;

    // Color
    Rgb dst_scaled;
    for (genvar i = 0; i < 3; i++) begin : multipliers
        SpuMultiplierNormalized8 dst_multiplier(
            .a(dst[i]),
            .b(one_minus_src_a),
            .res(dst_scaled[i])
        );
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < 3; i++) begin
            res[i] <= src.rgb[i] + dst_scaled[i];
        end
    end
endmodule
