package spu;
    localparam SPU_LANES = 4;
    localparam SPU_LANES_LOG2 = $clog2(SPU_LANES);

    localparam CRAM_ADDR_WIDTH = 8;
    localparam CRAM_DATA_WIDTH = 32;
    localparam CRAM_SIZE = 2 ** CRAM_ADDR_WIDTH;

    localparam VRAM_LOGICAL_ADDR_WIDTH = 14;
    localparam VRAM_ADDR_WIDTH = VRAM_LOGICAL_ADDR_WIDTH - SPU_LANES_LOG2;
    localparam VRAM_LOGICAL_DATA_WIDTH = 8;
    localparam VRAM_DATA_WIDTH = VRAM_LOGICAL_DATA_WIDTH * SPU_LANES;
    localparam VRAM_SIZE = 2 ** VRAM_ADDR_WIDTH;

    localparam CMDRAM_ADDR_WIDTH = 8;
    localparam COMMAND_SIZE = 64;
    localparam CMDRAM_SIZE = 2 ** CMDRAM_ADDR_WIDTH;

    localparam LINE_BUFFER_LOGICAL_ADDR_WIDTH = 10;
    localparam LINE_BUFFER_ADDR_WIDTH = LINE_BUFFER_LOGICAL_ADDR_WIDTH - SPU_LANES_LOG2;
    localparam LINE_BUFFER_LOGICAL_DATA_WIDTH = 24;
    localparam LINE_BUFFER_DATA_WIDTH = LINE_BUFFER_LOGICAL_DATA_WIDTH * SPU_LANES;
    localparam LINE_BUFFER_SIZE = vga::H_ACTIVE / SPU_LANES;

    typedef logic [2:0][7:0] Rgb;

    typedef struct packed {
        logic [7:0] a;
        Rgb rgb;
    } Rgba;

    typedef Rgb [SPU_LANES-1:0] RgbLanes;
    typedef Rgba [SPU_LANES-1:0] RgbaLanes;

    typedef logic [LINE_BUFFER_DATA_WIDTH-1:0] LineBufferLanes;
    typedef logic [LINE_BUFFER_ADDR_WIDTH-1:0] LineBufferLanesAddr;
    typedef logic [SPU_LANES-1:0] LineBufferLanesWStrobe;
endpackage
