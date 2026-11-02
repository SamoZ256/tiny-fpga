// IcePi Zero board top: PLL + core + HDMI output
module top (
    input logic clk,

    output logic [3:0] gpdi_dp,

    input  logic  [1:0] button,
    output logic [4:0] led
);
    // Clock
    wire clkp, clkt;
    pll_dvi pll_dvi (
        .clk(clk),
        .clkout0(clkt),
        .clkout1(clkp),
        .locked()
    );

    // Core
    wire vsync, hsync, de;
    wire [7:0] vga_r, vga_g, vga_b;
    core core (
        .clk(clk),
        .clk_pixel(clkp),
        .button(button),
        .led(led),
        .video_de(de),
        .video_hsync(hsync),
        .video_vsync(vsync),
        .video_r(vga_r),
        .video_g(vga_g),
        .video_b(vga_b)
    );

    // Convert the signal to DVI and send over HDMI
    vga2tmds tmds_generator (
        .clkp(clkp),
        .clkt(clkt),
        .vsync(vsync),
        .hsync(hsync),
        .de(de),
        .r(vga_r),
        .g(vga_g),
        .b(vga_b),
        .tmds(gpdi_dp)
    );
endmodule
