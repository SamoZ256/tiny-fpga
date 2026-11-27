package spu;
    localparam unsigned LANES = 4;
    localparam unsigned LANES_LOG2 = $clog2(LANES);

    localparam unsigned CRAM_ADDR_WIDTH = 8;
    localparam unsigned CRAM_DATA_WIDTH = 32;
    localparam unsigned CRAM_SIZE = 2 ** CRAM_ADDR_WIDTH;

    localparam unsigned VRAM_LOGICAL_ADDR_WIDTH = 14;
    localparam unsigned VRAM_ADDR_WIDTH = VRAM_LOGICAL_ADDR_WIDTH - LANES_LOG2;
    localparam unsigned VRAM_LOGICAL_DATA_WIDTH = 8;
    localparam unsigned VRAM_DATA_WIDTH = VRAM_LOGICAL_DATA_WIDTH * LANES;
    localparam unsigned VRAM_SIZE = 2 ** VRAM_ADDR_WIDTH;

    localparam unsigned CMDRAM_ADDR_WIDTH = 8;
    localparam unsigned COMMAND_SIZE = 64;
    localparam unsigned CMDRAM_SIZE = 2 ** CMDRAM_ADDR_WIDTH;

    localparam unsigned LINE_BUFFER_LOGICAL_ADDR_WIDTH = 10;
    localparam unsigned LINE_BUFFER_ADDR_WIDTH = LINE_BUFFER_LOGICAL_ADDR_WIDTH - LANES_LOG2;
    localparam unsigned LINE_BUFFER_LOGICAL_DATA_WIDTH = 24;
    localparam unsigned LINE_BUFFER_DATA_WIDTH = LINE_BUFFER_LOGICAL_DATA_WIDTH * LANES;
    localparam unsigned LINE_BUFFER_SIZE = vga::H_ACTIVE / LANES;

    typedef logic [2:0][7:0] Rgb;

    typedef struct packed {
        logic [7:0] a;
        Rgb rgb;
    } Rgba;

    typedef Rgb [LANES-1:0] RgbLanes;
    typedef Rgba [LANES-1:0] RgbaLanes;

    typedef logic [LINE_BUFFER_DATA_WIDTH-1:0] LineBufferLanes;
    typedef logic [LINE_BUFFER_ADDR_WIDTH-1:0] LineBufferLanesAddr;
    typedef logic [LANES-1:0] LineBufferLanesWStrobe;
endpackage
