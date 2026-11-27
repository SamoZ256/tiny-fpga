package vga;
    // Default values for 640x480 @ 60Hz
    parameter unsigned H_ACTIVE = 640;
    parameter unsigned H_FRONT  = 16;
    parameter unsigned H_SYNC   = 96;
    parameter unsigned H_BACK   = 48;
    parameter unsigned V_ACTIVE = 480;
    parameter unsigned V_FRONT  = 10;
    parameter unsigned V_SYNC   = 2;
    parameter unsigned V_BACK   = 33;

    // Derived Timing Constants
    localparam unsigned HA_END = H_ACTIVE - 1;
    localparam unsigned HS_STA = HA_END + H_FRONT;
    localparam unsigned HS_END = HS_STA + H_SYNC;
    localparam unsigned LINE = H_ACTIVE + H_FRONT + H_SYNC + H_BACK - 1;

    localparam unsigned VA_END = V_ACTIVE - 1;
    localparam unsigned VS_STA = VA_END + V_FRONT;
    localparam unsigned VS_END = VS_STA + V_SYNC;
    localparam unsigned SCREEN = V_ACTIVE + V_FRONT + V_SYNC + V_BACK - 1;
endpackage
