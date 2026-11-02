import spu::*;

// NOTE: RGB and alpha are in the same cycle on both the inputs and the output, latency is 1 cycle
module SpuColorResolver (
    input logic clk,

    input Rgba src,
    input Rgba dst,

    output Rgba res
);
    // Alpha
    logic [7:0] dst_a_times_one_minus_src_a;
    SpuMultiplierNormalized8 alpha_multiplier(
        .a(dst.a),
        .b('hff - src.a),
        .res(dst_a_times_one_minus_src_a)
    );

    always_ff @(posedge clk) begin
        res.a <= src.a + dst_a_times_one_minus_src_a;
    end

    // Color
    Rgb dst_premultiplied;
    for (genvar i = 0; i < 3; i++) begin : multipliers
        SpuMultiplierNormalized8 multiplier(
            .a(dst.rgb[i]),
            .b(dst_a_times_one_minus_src_a),
            .res(dst_premultiplied[i])
        );
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < 3; i++) begin
            res.rgb[i] <= dst_premultiplied[i] + src.rgb[i];
        end
    end
endmodule
