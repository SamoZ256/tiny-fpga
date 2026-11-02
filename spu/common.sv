package spu;
    localparam ENGINE_COUNT = 3;

    localparam CRAM_ADDR_WIDTH = 8;
    localparam CRAM_DATA_WIDTH = 24;
    localparam CRAM_SIZE = 2 ** CRAM_ADDR_WIDTH;

    localparam VRAM_ADDR_WIDTH = 14;
    localparam VRAM_DATA_WIDTH = 8;
    localparam VRAM_SIZE = 2 ** VRAM_ADDR_WIDTH;

    localparam CMDRAM_ADDR_WIDTH = 12;
    localparam COMMAND_SIZE = 32;
    localparam CMDRAM_SIZE = 2 ** CMDRAM_ADDR_WIDTH;

    typedef logic [7:0] Rgb[3];

    typedef struct {
        Rgb rgb;
        logic [7:0] a;
    } Rgba;

    // xxx (3) | xxxxxxxxxxxxxxxxxxxxxxxxxxxxx (29)
    // kind    | param
    typedef struct packed {
        logic [28:0] param;
        SpuCtrlCommandKind::Type kind;
    } CtrlCommand;
endpackage

package SpuCtrlCommandKind;
    typedef enum logic [2:0] {
        reset = 1,
        start = 2,
        stop = 3
    } Type;
endpackage
