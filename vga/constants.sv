package vga;
    // Default values for 640x480 @ 60Hz
    parameter H_ACTIVE = 640;
    parameter H_FRONT  = 16;
    parameter H_SYNC   = 96;
    parameter H_BACK   = 48;
    parameter V_ACTIVE = 480;
    parameter V_FRONT  = 10;
    parameter V_SYNC   = 2;
    parameter V_BACK   = 33;

    // Derived Timing Constants
    localparam HA_END = H_ACTIVE - 1;
    localparam HS_STA = HA_END + H_FRONT;
    localparam HS_END = HS_STA + H_SYNC;
    localparam LINE = H_ACTIVE + H_FRONT + H_SYNC + H_BACK - 1;

    localparam VA_END = V_ACTIVE - 1;
    localparam VS_STA = VA_END + V_FRONT;
    localparam VS_END = VS_STA + V_SYNC;
    localparam SCREEN = V_ACTIVE + V_FRONT + V_SYNC + V_BACK - 1;
endpackage
