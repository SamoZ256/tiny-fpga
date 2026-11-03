package spu;
    localparam CRAM_ADDR_WIDTH = 8;
    localparam CRAM_DATA_WIDTH = 24;
    localparam CRAM_SIZE = 2 ** CRAM_ADDR_WIDTH;

    localparam VRAM_ADDR_WIDTH = 14;
    localparam VRAM_DATA_WIDTH = 8;
    localparam VRAM_SIZE = 2 ** VRAM_ADDR_WIDTH;

    localparam CMDRAM_ADDR_WIDTH = 8;
    localparam COMMAND_SIZE = 64;
    localparam CMDRAM_SIZE = 2 ** CMDRAM_ADDR_WIDTH;

    localparam LINE_BUFFER_ADDR_WIDTH = 10;
    localparam LINE_BUFFER_DATA_WIDTH = 32;
    localparam LINE_BUFFER_SIZE = vga::H_ACTIVE;

    typedef logic [7:0] Rgb[3];

    typedef struct {
        Rgb rgb;
        logic [7:0] a;
    } Rgba;
endpackage
