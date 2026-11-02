import vga::*;

module Vga(
    input  wire         clk,

    input  wire  [ 7:0] r,
    input  wire  [ 7:0] g,
    input  wire  [ 7:0] b,

    output logic        hsync,
    output logic        vsync,
    output logic        de,
    output logic        vblank,
    output logic [ 7:0] vga_r,
    output logic [ 7:0] vga_g,
    output logic [ 7:0] vga_b
);
    logic [9:0] px;
    logic [9:0] py;
    VgaCounter #(
        .LINE(LINE),
        .SCREEN(SCREEN)
    ) counter (
        .clk(clk),
        .x(px),
        .y(py)
    );

    // Generate hsync and vsync signals
    always_comb begin
        hsync = ~(px >= HS_STA && px < HS_END);
        vsync = ~(py >= VS_STA && py < VS_END);
        de    = (px <= HA_END && py <= VA_END);
        vblank = (py > VA_END);

        // Output color only during active display area
        vga_r = de ? r : 8'b0;
        vga_g = de ? g : 8'b0;
        vga_b = de ? b : 8'b0;
    end
endmodule
