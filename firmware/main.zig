const std = @import("std");
const common = @import("common/common.zig");
const mmio = @import("common/mmio.zig");
const CommandEncoder = @import("ppu/command_encoder.zig").CommandEncoder;
const Renderer = @import("ppu/renderer.zig").Renderer;

export fn _start() linksection(".text.start") callconv(.naked) noreturn {
    asm volatile (
        \\ # Set the stack pointer
        \\ la sp, __stack_top
        \\
        \\ # Set the global pointer
        \\ .option push
        \\ .option norelax
        \\ la gp, __global_pointer$
        \\ .option pop
        \\
        \\ # Zero .bss
        \\ la t0, __bss_start
        \\ la t1, __bss_end
        \\ 1:
        \\ bgeu t0, t1, 2f
        \\ sw zero, 0(t0)
        \\ addi t0, t0, 4
        \\ j 1b
        \\
        \\ # Jump to _init
        \\ 2:
        \\ j _init
    );
}

export fn _init() noreturn {
    @setRuntimeSafety(false);

    // Main
    main() catch {};

    // Loop forever
    while (true) {}
}

const font_data = @embedFile("font.bin");

const char_width = 8;
const char_height = 8;
const bytes_per_char = char_height;
const char_count = 256;

fn getPixelRow(char: u8, y: usize) u8 {
    const char_offset: usize = @as(usize, char) * bytes_per_char;
    return @bitReverse(font_data[char_offset + y]);
}

const FONT_VRAM_ADDR_OFFSET = 0x200;

fn getFontVramAddr(char: u8, y: u3) mmio.VramAddr {
    return FONT_VRAM_ADDR_OFFSET + (@as(mmio.VramAddr, char) * char_height + @as(mmio.VramAddr, y));
}

fn initializeFontVram() void {
    for (0..char_count) |char| {
        for (0..char_height) |y| {
            mmio.writeVram(getFontVramAddr(@intCast(char), @intCast(y)), getPixelRow(@intCast(char), @intCast(y)));
        }
    }
}

var buffer: [4096]u8 = undefined;

fn main() !void {
    // Get screen params
    //const screen_width = readScreenWidth();
    //const screen_height = readScreenHeight();

    // PPU

    // Palette
    mmio.writeCram(0, common.Rgba.initPremultiplied(0xff, 0x00, 0xff, 0xff).toRawBits());
    mmio.writeCram(1, common.Rgba.initPremultiplied(0x00, 0x00, 0x00, 0x00).toRawBits());
    mmio.writeCram(2, common.Rgba.initPremultiplied(0xff, 0xff, 0xff, 0xff).toRawBits());
    mmio.writeCram(3, common.Rgba.initPremultiplied(0xff, 0x00, 0x00, 0xff).toRawBits());
    mmio.writeCram(4, common.Rgba.initPremultiplied(0x00, 0xff, 0x00, 0xff).toRawBits());
    mmio.writeCram(5, common.Rgba.initPremultiplied(0x00, 0x00, 0xff, 0xff).toRawBits());

    // Font
    initializeFontVram();

    // Tilemap
    const text = "Hello, World! This is a very looong text";
    for (0..text.len) |i| {
        const c = text[i];
        mmio.writeVram(@intCast(i), c);
    }

    var allocator = std.heap.FixedBufferAllocator.init(&buffer);

    var renderer = try Renderer.init(allocator.allocator(), common.WIDTH, common.HEIGHT);
    defer renderer.deinit();

    const ground_y = 440;
    const ground_color = common.Rgba.init(0x20, 0x80, 0x20, 0xff);
    //     const ball_color = common.Rgba.initPremultiplied(0xff, 0x80, 0x00, 0x7f);
    //     const radius = 100;
    //     const min_x = radius;
    //     const max_x = common.WIDTH - 1 - radius;
    //     const min_y = radius;
    //     const max_y = ground_y - 1 - radius;
    //
    //     const half_widths = blk: {
    //         var widths: [2 * radius + 1]u8 = undefined;
    //         for (&widths, 0..) |*width, i| {
    //             const dy: f64 = @as(f64, @floatFromInt(i)) - radius;
    //             width.* = @intFromFloat(@round(@sqrt(radius * radius - dy * dy)));
    //         }
    //         break :blk widths;
    //     };

    // var ball_x: i32 = 200;
    // var ball_y: i32 = 150;
    // var vel_x: i32 = 3;
    // var vel_y: i32 = 2;

    // Main loop
    //var buttons_last: u2 = 0;
    while (true) {
        const buttons = mmio.readButtons();
        //buttons_last = buttons;
        mmio.writeLed(buttons);

        // Game logic
        // ball_x = std.math.clamp(ball_x + vel_x, min_x, max_x);
        // if (ball_x == min_x or ball_x == max_x) vel_x = -vel_x;
        // ball_y = std.math.clamp(ball_y + vel_y, min_y, max_y);
        // if (ball_y == min_y or ball_y == max_y) vel_y = -vel_y;

        // Draw

        renderer.clear();

        // Sky and sun
        //         for (0..ground_y) |y| {
        //             // Sky
        //             const sky = common.Rgba.init(0x10, @intCast(0x20 + y / 4), @intCast(0x60 + y / 4), 0xff);
        //             try renderer.cmdFill(0, @intCast(y), common.WIDTH, 1, sky);
        //
        //             // Sun
        //             const row = @as(i32, @intCast(y)) - ball_y + radius;
        //             if (row >= 0 and row <= 2 * radius) {
        //                 const half_width: i32 = half_widths[@intCast(row)];
        //                 const x0: u32 = @intCast(ball_x - half_width);
        //                 const x1: u32 = @intCast(ball_x + half_width + 1);
        //                 try renderer.cmdFill(@intCast(x0), @intCast(y), @intCast(x1 - x0), 1, ball_color);
        //             }
        //         }
        try renderer.cmdFill(0, 0, common.WIDTH, ground_y, common.Rgba.init(0x10, 0x20, 0x60, 0xff));

        // Ground
        try renderer.cmdFill(0, ground_y, common.WIDTH, common.HEIGHT - ground_y, ground_color);

        // Text
        const text2 = "S";
        for (0..text2.len) |i| {
            const c = text2[i];
            try renderer.cmdSprite(@intCast(i * char_width), 0, char_width, char_height, getFontVramAddr(c, 0), 1, 1, 1);
        }

        try renderer.cmdTiles(0, 8, char_height, 0, @intCast(text.len), @intCast(FONT_VRAM_ADDR_OFFSET), char_width, 1, char_height, 1, 1);

        var line = mmio.waitForNextLine();
        while (line != 0) {
            line = mmio.waitForNextLine();
        }

        while (line < common.HEIGHT) {
            var command_encoder = CommandEncoder.init();
            renderer.renderLine(&command_encoder, line);
            command_encoder.cmdEndLine();

            line = mmio.waitForNextLine();
        }
    }
}
