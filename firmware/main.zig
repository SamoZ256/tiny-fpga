const std = @import("std");
const common = @import("common/common.zig");
const mmio = @import("common/mmio.zig");

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
    main();

    // Loop forever
    while (true) {}
}

const font_data = @embedFile("font.bin");

const char_width = 8;
const char_height = 8;
const bytes_per_char = char_height;
const char_count = 256;

fn getPixel(char: u8, x: usize, y: usize) bool {
    const char_offset: usize = @as(usize, char) * bytes_per_char;
    const row_byte = font_data[char_offset + y];
    const bit_shift: u33 = @intCast(7 - x);
    return ((row_byte >> @intCast(bit_shift)) & 1) == 1;
}

fn getFontVramAddr(char: u8, x: u3, y: u3) mmio.VramAddr {
    return ((@as(mmio.VramAddr, char) * char_height + @as(mmio.VramAddr, y)) * char_width) + @as(mmio.VramAddr, x);
}

fn initializeFontVram() void {
    for (0..char_count) |char| {
        for (0..char_height) |y| {
            for (0..char_width) |x| {
                mmio.writeVram(getFontVramAddr(@intCast(char), @intCast(x), @intCast(y)), if (getPixel(@intCast(char), @intCast(x), @intCast(y))) 0xbf else 0);
            }
        }
    }
}

fn main() void {
    // Get screen params
    //const screen_width = readScreenWidth();
    //const screen_height = readScreenHeight();

    // SPU

    // Palette
    mmio.writeCram(0, 0xff00ff);
    mmio.writeCram(1, 0x000000);
    mmio.writeCram(2, 0xffffff);
    mmio.writeCram(3, 0x0000ff);
    mmio.writeCram(4, 0x00ff00);
    mmio.writeCram(5, 0xff0000);

    // Font
    initializeFontVram();

    // Main loop
    //var buttons_last: u2 = 0;
    while (true) {
        const buttons = mmio.readButtons();
        //buttons_last = buttons;
        mmio.writeLed(buttons);

        // Draw
        const Draw = struct {
            // Must match SpuCommandKind in spu/spu.sv (begin_line, span and tiles aren't implemented yet)
            const Kind = enum(u3) { end_line = 1, fill = 2 };

            // Must match the command layout in spu/spu.sv
            const Command = packed struct(u64) {
                kind: Kind,
                x: u10 = 0,
                len_minus_one: u10 = 0,
                color: u32 = 0, // 0xAABBGGRR
                reserved: u9 = 0,
            };

            const ground_y = 440;
            const ground_color = 0xff208020;
            const ball_color = 0x7f0080ff;
            const radius = 100;
            const min_x = radius;
            const max_x = common.WIDTH - 1 - radius;
            const min_y = radius;
            const max_y = ground_y - 1 - radius;

            // Half-width of each row of the ball, computed at compile time
            const half_widths = blk: {
                var widths: [2 * radius + 1]u8 = undefined;
                for (&widths, 0..) |*width, i| {
                    const dy: f64 = @as(f64, @floatFromInt(i)) - radius;
                    width.* = @intFromFloat(@round(@sqrt(radius * radius - dy * dy)));
                }
                break :blk widths;
            };

            var ball_x: i32 = 200;
            var ball_y: i32 = 150;
            var vel_x: i32 = 3;
            var vel_y: i32 = 2;

            fn moveBall() void {
                ball_x = std.math.clamp(ball_x + vel_x, min_x, max_x);
                if (ball_x == min_x or ball_x == max_x) vel_x = -vel_x;
                ball_y = std.math.clamp(ball_y + vel_y, min_y, max_y);
                if (ball_y == min_y or ball_y == max_y) vel_y = -vel_y;
            }

            inline fn fill(index: *mmio.CmdramAddr, x: u32, len: u32, color: u32) void {
                mmio.writeCmdram(index.*, @bitCast(Command{ .kind = .fill, .x = @intCast(x), .len_minus_one = @intCast(len - 1), .color = color }));
                index.* += 1;
            }

            // The line buffer isn't cleared, so every line must cover all WIDTH pixels. The blitter draws one
            // pixel per pixel clock, so the background is drawn around the ball instead of underneath it
            fn drawLine(line: u32) void {
                var index: mmio.CmdramAddr = 0;
                if (line >= ground_y) {
                    fill(&index, 0, common.WIDTH, ground_color);
                } else {
                    // Sky, getting lighter towards the ground
                    const sky = 0xff000000 | ((0x60 + line / 4) << 16) | ((0x20 + line / 4) << 8) | 0x10;
                    const row = @as(i32, @intCast(line)) - ball_y + radius;
                    fill(&index, 0, common.WIDTH, sky);
                    if (row >= 0 and row <= 2 * radius) {
                        const half_width: i32 = half_widths[@intCast(row)];
                        const x0: u32 = @intCast(ball_x - half_width);
                        const x1: u32 = @intCast(ball_x + half_width + 1);
                        fill(&index, x0, x1 - x0, ball_color);
                    }
                }
                mmio.writeCmdram(index, @bitCast(Command{ .kind = .end_line }));
            }
        };

        const line = mmio.waitForNextLine();
        if (line < common.HEIGHT) {
            Draw.drawLine(line);
        } else if (line == common.HEIGHT) {
            // The last visible line has been submitted, move the ball for the next frame
            Draw.moveBall();
        }
    }
}
