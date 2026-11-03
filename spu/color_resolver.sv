import spu::*;

// NOTE: latency is 1 cycle
module SpuColorResolver (
    input logic clk,

    input Rgba src, // Straight alpha
    input Rgba dst, // Premultiplied

    output Rgba res // Premultiplied
);
    logic [7:0] one_minus_src_a;
    assign one_minus_src_a = 8'hff - src.a;

    // Alpha
    logic [7:0] dst_a_scaled;
    SpuMultiplierNormalized8 alpha_multiplier(
        .a(dst.a),
        .b(one_minus_src_a),
        .res(dst_a_scaled)
    );

    always_ff @(posedge clk) begin
        res.a <= src.a + dst_a_scaled;
    end

    // Color
    Rgb src_premultiplied;
    Rgb dst_scaled;
    for (genvar i = 0; i < 3; i++) begin : multipliers
        SpuMultiplierNormalized8 src_multiplier(
            .a(src.rgb[i]),
            .b(src.a),
            .res(src_premultiplied[i])
        );
        SpuMultiplierNormalized8 dst_multiplier(
            .a(dst.rgb[i]),
            .b(one_minus_src_a),
            .res(dst_scaled[i])
        );
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < 3; i++) begin
            res.rgb[i] <= src_premultiplied[i] + dst_scaled[i];
        end
    end
endmodule
