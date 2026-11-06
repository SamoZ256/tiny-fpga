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

    localparam LINE_BUFFER_DATA_LANES = 4;
    localparam LINE_BUFFER_DATA_LANES_LOG2 = $clog2(LINE_BUFFER_DATA_LANES);
    localparam LINE_BUFFER_LOGICAL_ADDR_WIDTH = 10;
    localparam LINE_BUFFER_ADDR_WIDTH = LINE_BUFFER_LOGICAL_ADDR_WIDTH - LINE_BUFFER_DATA_LANES_LOG2;
    localparam LINE_BUFFER_LOGICAL_DATA_WIDTH = 24;
    localparam LINE_BUFFER_DATA_WIDTH = LINE_BUFFER_LOGICAL_DATA_WIDTH * LINE_BUFFER_DATA_LANES;
    localparam LINE_BUFFER_SIZE = vga::H_ACTIVE / LINE_BUFFER_DATA_LANES;

    typedef logic [2:0][7:0] Rgb;

    typedef struct packed {
        Rgb rgb;
        logic [7:0] a;
    } Rgba;

    typedef logic [LINE_BUFFER_ADDR_WIDTH-1:0] LanesAddr;
    typedef logic [LINE_BUFFER_DATA_LANES-1:0] LanesWStrobe;
    typedef logic [LINE_BUFFER_DATA_WIDTH-1:0] Lanes;
    typedef Rgb [LINE_BUFFER_DATA_LANES-1:0] RgbLanes;
    typedef Rgba [LINE_BUFFER_DATA_LANES-1:0] RgbaLanes;
endpackage
