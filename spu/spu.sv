// Scanline processing unit

import spu::*;

module Spu (
    input logic clk,
    input logic cpu_clk,

    input logic ctrl[ENGINE_COUNT],
    input CtrlCommand ctrl_cmd[ENGINE_COUNT],

    input logic [CRAM_ADDR_WIDTH-1:0] cram_w_addr,
    input logic [2:0] cram_w_strobe,
    input logic [CRAM_DATA_WIDTH-1:0] cram_din,

    input logic [VRAM_ADDR_WIDTH-1:0] vram_w_addr,
    input logic vram_w_strobe,
    input logic [VRAM_DATA_WIDTH-1:0] vram_din,

    input logic [CMDRAM_ADDR_WIDTH-1:0] cmdram_w_addr,
    input logic [3:0] cmdram_w_strobe,
    input logic [COMMAND_SIZE-1:0] cmdram_din,

    output Rgb color
);
    // CRAM
    wire [CRAM_ADDR_WIDTH-1:0] cram_r_addr[ENGINE_COUNT];
    wire [CRAM_DATA_WIDTH-1:0] cram_dout[ENGINE_COUNT];
    Vram #(
        .ADDR_WIDTH(CRAM_ADDR_WIDTH),
        .DATA_WIDTH(CRAM_DATA_WIDTH),
        .SIZE      (CRAM_SIZE),
        .NUM_R_PORTS(ENGINE_COUNT)
    ) cram (
        .r_clks('{default: clk}),
        .r_addrs(cram_r_addr),
        .douts(cram_dout),

        .w_clk(cpu_clk),
        .w_addr(cram_w_addr),
        .w_strobe(cram_w_strobe),
        .din(cram_din)
    );

    // VRAM
    logic [VRAM_ADDR_WIDTH-1:0] vram_r_addr[ENGINE_COUNT];
    wire [VRAM_DATA_WIDTH-1:0] vram_dout[ENGINE_COUNT];
    Vram #(
        .ADDR_WIDTH(VRAM_ADDR_WIDTH),
        .DATA_WIDTH(VRAM_DATA_WIDTH),
        .SIZE      (VRAM_SIZE),
        .NUM_R_PORTS(ENGINE_COUNT)
    ) vram (
        .r_clks('{default: clk}),
        .r_addrs(vram_r_addr),
        .douts(vram_dout),

        .w_clk(cpu_clk),
        .w_addr(vram_w_addr),
        .w_strobe(vram_w_strobe),
        .din(vram_din)
    );

    // Command RAM
    logic [CMDRAM_ADDR_WIDTH-1:0] cmdram_r_addr[ENGINE_COUNT];
    wire [COMMAND_SIZE-1:0] cmdram_douts[ENGINE_COUNT * 2];

    logic [CMDRAM_ADDR_WIDTH-1:0] cmdram_r_addr_resolved[ENGINE_COUNT * 2];
    always_comb begin
        for (int i = 0; i < ENGINE_COUNT; i++) begin
            cmdram_r_addr_resolved[i * 2 + 0] = cmdram_r_addr[i];
            cmdram_r_addr_resolved[i * 2 + 1] = cmdram_r_addr[i] + 1;
        end
    end

    Vram #(
        .ADDR_WIDTH(CMDRAM_ADDR_WIDTH),
        .DATA_WIDTH(COMMAND_SIZE),
        .SIZE      (CMDRAM_SIZE),
        .NUM_R_PORTS(ENGINE_COUNT * 2)
    ) cmdram (
        .r_clks('{default: clk}),
        .r_addrs(cmdram_r_addr_resolved),
        .douts(cmdram_douts),

        .w_clk(cpu_clk),
        .w_addr(cmdram_w_addr),
        .w_strobe(cmdram_w_strobe),
        .din(cmdram_din)
    );

    // Engines
    Rgba colors[ENGINE_COUNT];
    for (genvar i = 0; i < ENGINE_COUNT; i++) begin : engines
        // Control commands come from the CPU clock domain. Latch the command and pass a toggle through a
        // synchronizer, so that a single CPU cycle pulse isn't missed by the slower pixel clock
        // NOTE: commands to the same engine must be at least 6 CPU cycles apart
        CtrlCommand cmd;
        logic cmd_toggle = 0;
        always_ff @(posedge cpu_clk) begin
            if (ctrl[i]) begin
                cmd <= ctrl_cmd[i];
                cmd_toggle <= !cmd_toggle;
            end
        end

        logic [2:0] cmd_toggle_sync = 0;
        always_ff @(posedge clk) begin
            cmd_toggle_sync <= {cmd_toggle_sync[1:0], cmd_toggle};
        end
        wire cmd_valid = cmd_toggle_sync[2] ^ cmd_toggle_sync[1];

        logic [9:0] x;
        logic [9:0] y;
        VgaCounter #(
            .LINE(vga::LINE),
            .SCREEN(vga::SCREEN),
            // Run ahead of the VGA counter by the latency to the output: 3 engine stages + (i + 2) color resolvers
            .START_X(3 + (i + 2))
        ) counter(
            .clk(clk),
            .x(x),
            .y(y)
        );

        SpuEngine engine(
            clk,
            cmd_valid,
            cmd,
            x,
            y,
            cram_r_addr[i],
            cram_dout[i],
            vram_r_addr[i],
            vram_dout[i],
            cmdram_r_addr[i],
            {cmdram_douts[i * 2 + 0], cmdram_douts[i * 2 + 1]},
            colors[i]
        );
    end

    // Color resolve
    localparam COLOR_RESOLVE_CHANNELS = ENGINE_COUNT + 1;
    Rgba colors_resolved[COLOR_RESOLVE_CHANNELS];
    for (genvar i = 0; i < COLOR_RESOLVE_CHANNELS; i++) begin : color_resolvers
        SpuColorResolver color_resolver(
            .clk(clk),
            .src(i != COLOR_RESOLVE_CHANNELS - 1 ? colors_resolved[i + 1] : '{
                rgb: '{default: '0},
                a: '0
            }),
        	.dst(i != 0 ? colors[i - 1] : '{
                 rgb: {'hff, 'hff, 'h00}, // TODO: make this configurable
                 a: 'hff
             }),
        	.res(colors_resolved[i])
        );
    end

    // Output
    assign color = colors_resolved[0].rgb;
endmodule
