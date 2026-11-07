module core (
    input logic clk,
    input logic clk_pixel,

    input  logic  [1:0] button,
    output logic [4:0] led,

    output logic       video_de,
    output logic       video_hsync,
    output logic       video_vsync,
    output logic [7:0] video_r,
    output logic [7:0] video_g,
    output logic [7:0] video_b
);
    // IO
    logic [4:0] led_reg;
    logic [1:0] btn;
    Debouncer btn0_debouncer (
        clk,
        !button[0],
        btn[0]
    );
    Debouncer btn1_debouncer (
        clk,
        !button[1],
        btn[1]
    );

    // RAM
    localparam RAM_ADDR_WIDTH = 11;
    localparam RAM_PHYSICAL_ADDR_SPACE_SIZE = 2 ** RAM_ADDR_WIDTH;

    wire [29:0] ram_addr;
    wire [3:0] ram_w_strobe;
    wire [31:0] ram_din;
    wire [31:0] ram_dout;

    wire [ 3:0] ram_w_strobe_physical = ram_addr < RAM_PHYSICAL_ADDR_SPACE_SIZE ? ram_w_strobe : 4'b0;

    ram #(
        .ADDR_WIDTH(RAM_ADDR_WIDTH),
        .FILENAME  ("firmware/firmware.hex")
    ) ram (
        .clk(clk),
        .address(ram_addr[10:0]),
        .w_strobe(ram_w_strobe_physical),
        .din(ram_din),
        .dout(ram_dout)
    );

    logic [31:0] ram_mapped_dout;

    // CPU
    Rv32CpuFault::Type cpu_fault;
    Rv32Cpu cpu (
        .clk(clk),

        .ram_addr(ram_addr),
        .ram_w_strobe(ram_w_strobe),
        .ram_din(ram_din),
        .ram_dout(ram_mapped_dout),

        .fault(cpu_fault)
    );
    assign led = cpu_fault != Rv32CpuFault::none ? cpu_fault : led_reg;

    // Display

    // SPU
    logic [spu::CRAM_ADDR_WIDTH-1:0] cram_w_addr;
    assign cram_w_addr = ram_addr[spu::CRAM_ADDR_WIDTH-1:0];
    logic [3:0] cram_w_strobe;
    logic [spu::CRAM_DATA_WIDTH-1:0] cram_din;

    logic [spu::VRAM_ADDR_WIDTH-1:0] vram_w_addr;
    assign vram_w_addr = ram_addr[spu::VRAM_ADDR_WIDTH-1:0];
    logic [3:0] vram_w_strobe;
    logic [spu::VRAM_DATA_WIDTH-1:0] vram_din;

    logic [spu::CMDRAM_ADDR_WIDTH-1:0] cmdram_w_addr;
    assign cmdram_w_addr = ram_addr[spu::CMDRAM_ADDR_WIDTH:1];
    logic [7:0] cmdram_w_strobe;
    logic [spu::COMMAND_SIZE-1:0] cmdram_din;

    spu::Rgb color;
    logic [9:0] target_line;
    Spu spu (
       	.clk  (clk_pixel),
        .cpu_clk(clk),
        .cram_w_addr(cram_w_addr),
        .cram_w_strobe(cram_w_strobe),
        .cram_din(cram_din),
        .vram_w_addr(vram_w_addr),
        .vram_w_strobe(vram_w_strobe),
        .vram_din(vram_din),
        .cmdram_w_addr(cmdram_w_addr),
        .cmdram_w_strobe(cmdram_w_strobe),
        .cmdram_din(cmdram_din),
       	.color(color),
        .cpu_target_line(target_line)
    );

    // VGA Signal generator
    Vga vga_driver (
        .clk(clk_pixel),
        .r(color[0]),
        .g(color[1]),
        .b(color[2]),
        .hsync(video_hsync),
        .vsync(video_vsync),
        .de(video_de),
        .vblank(),
        .vga_r(video_r),
        .vga_g(video_g),
        .vga_b(video_b)
    );

    // MMIO

    localparam MMIO_LED_ADDR = 32'h04000000;
    localparam MMIO_BTN_ADDR = 32'h04000001;
    localparam MMIO_SCR_WIDTH_ADDR = 32'h04000002;
    localparam MMIO_SCR_HEIGHT_ADDR = 32'h04000003;
    localparam MMIO_TARGET_LINE_ADDR = 32'h04000004;
    localparam MMIO_CRAM_ADDR = 32'h09000000;
    localparam MMIO_VRAM_ADDR = 32'h0a000000;
    localparam MMIO_CMDRAM_ADDR = 32'h0b000000;

    // Read
    always_comb begin
        ram_mapped_dout = ram_addr < RAM_PHYSICAL_ADDR_SPACE_SIZE ? ram_dout : 32'b0;
        case (ram_addr)
            MMIO_BTN_ADDR: ram_mapped_dout = {30'b0, btn};
            MMIO_SCR_WIDTH_ADDR: ram_mapped_dout = 640; // TODO: don't hardcode
            MMIO_SCR_HEIGHT_ADDR: ram_mapped_dout = 480; // TODO: don't hardcode
            MMIO_TARGET_LINE_ADDR: ram_mapped_dout = {22'b0, target_line};
        endcase
    end

    // Write
    always_ff @(posedge clk) begin
        if (ram_addr == MMIO_LED_ADDR) begin
            if (ram_w_strobe[0]) led_reg <= ram_din[4:0];
        end
    end

    always_comb begin
        cram_w_strobe = '0;
        cram_din = '0;

        vram_w_strobe = '0;
        vram_din = '0;

        cmdram_w_strobe = '0;
        cmdram_din = '0;

        if (ram_addr >= MMIO_CRAM_ADDR && ram_addr < MMIO_CRAM_ADDR + spu::CRAM_SIZE) begin
            cram_w_strobe = ram_w_strobe[3:0];
            cram_din = ram_din[spu::CRAM_DATA_WIDTH-1:0];
        end else if (ram_addr >= MMIO_VRAM_ADDR && ram_addr < MMIO_VRAM_ADDR + spu::VRAM_SIZE) begin
            vram_w_strobe = ram_w_strobe;
            vram_din = ram_din[spu::VRAM_DATA_WIDTH-1:0];
        end else if (ram_addr >= MMIO_CMDRAM_ADDR && ram_addr < MMIO_CMDRAM_ADDR + spu::CMDRAM_SIZE * 2) begin
            if (ram_addr[0]) begin
                cmdram_w_strobe = {ram_w_strobe, 4'b0};
                cmdram_din = {ram_din, 32'b0};
            end else begin
                cmdram_w_strobe = {4'b0, ram_w_strobe};
                cmdram_din = {32'b0, ram_din};
            end
        end
    end
endmodule
