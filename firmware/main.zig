const std = @import("std");
const common = @import("common/common.zig");
const mmio = @import("common/mmio.zig");
const Spu = @import("spu/Spu.zig");

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

    const spu = Spu.init();

    // Palette
    mmio.writeCram(0, 0xff00ff);
    mmio.writeCram(1, 0x000000);
    mmio.writeCram(2, 0xffffff);
    mmio.writeCram(3, 0x0000ff);
    mmio.writeCram(4, 0x00ff00);
    mmio.writeCram(5, 0xff0000);

    // Font
    initializeFontVram();

    // Background
    {
        var encoder = Spu.InstructionEncoder.init(0);
        _ = encoder.encodeBlit(Spu.InstructionEncoder.RZ, .{ .cram_addr_offset = 1 });
        _ = encoder.encodeSleep(Spu.InstructionEncoder.RZ, Spu.InstructionEncoder.getCyclesFromCoords(0, 10) - 2);
        _ = encoder.encodeBlit(Spu.InstructionEncoder.RZ, .{ .cram_addr_offset = 2 });
        _ = encoder.encodeSleep(Spu.InstructionEncoder.RZ, Spu.InstructionEncoder.getCyclesFromCoords(0, 1) - 2);
        _ = encoder.encodeBlit(Spu.InstructionEncoder.RZ, .{ .alpha_bits = 1 });
        encoder.endEncoding();
    }

    spu.engines[0].reset(0);

    // Window
    {
        var encoder = Spu.InstructionEncoder.init(500);
        _ = encoder.encodeBlit(Spu.InstructionEncoder.RZ, .{ .alpha_bits = 1 });
        _ = encoder.encodeSleep(Spu.InstructionEncoder.RZ, Spu.InstructionEncoder.getCyclesFromCoords(0, 100) - 1);
        const loop_addr = encoder.encodeSleep(Spu.InstructionEncoder.RZ, 100 - 1);
        _ = encoder.encodeBlit(Spu.InstructionEncoder.RZ, .{ .cram_addr_offset = 2 });
        _ = encoder.encodeBlit(Spu.InstructionEncoder.RZ, .{ .cram_addr_offset = 1 });
        _ = encoder.encodeSleep(Spu.InstructionEncoder.RZ, 200 - 3);
        _ = encoder.encodeBlit(Spu.InstructionEncoder.RZ, .{ .cram_addr_offset = 2 });
        _ = encoder.encodeBlit(Spu.InstructionEncoder.RZ, .{ .alpha_bits = 1 });
        _ = encoder.encodeSleep(Spu.InstructionEncoder.RZ, Spu.InstructionEncoder.getCyclesFromCoords(0, 1) - 100 - 200 - 5);
        _ = encoder.encodeJal(Spu.InstructionEncoder.RZ, loop_addr);
        encoder.endEncoding();
    }

    spu.engines[1].reset(500);

    // Foreground
    const text = "\u{1e} Page Up \u{1f} Page Down";
    const text2 = "Hello, World!";

    {
        var encoder = Spu.InstructionEncoder.init(20);
        _ = encoder.encodeBlit(Spu.InstructionEncoder.RZ, .{ .alpha_bits = 1 });
        _ = encoder.encodeSleep(Spu.InstructionEncoder.RZ, Spu.InstructionEncoder.getCyclesFromCoords(0, 1) - 12);
        _ = encoder.encodeLi(1, 40);
        _ = encoder.encodeLi(2, text.len);
        _ = encoder.encodeCall(Spu.InstructionEncoder.RZ, 400);
        _ = encoder.encodeBlit(Spu.InstructionEncoder.RZ, .{ .alpha_bits = 1 });
        _ = encoder.encodeSleep(Spu.InstructionEncoder.RZ, Spu.InstructionEncoder.getCyclesFromCoords(0, 4) - 12);
        _ = encoder.encodeLi(1, 200);
        _ = encoder.encodeLi(2, text2.len);
        _ = encoder.encodeCall(Spu.InstructionEncoder.RZ, 400);
        encoder.endEncoding();
    }

    {
        var encoder = Spu.InstructionEncoder.init(40);
        for (0..text.len) |i| {
            const c = text[i];
            _ = encoder.encodeSllI(5, 7, 3);
            _ = encoder.encodeAddI(5, 5, getFontVramAddr(c, 0, 0));
            _ = encoder.encodeBlit(5, .{ .vram_value_shift_increment = 8, .cram_addr_bits = 0, .alpha_bits = 8, .cram_addr_offset = 2 });
            _ = encoder.encodeSleep(Spu.InstructionEncoder.RZ, 4);
        }
        _ = encoder.encodeRet();
        encoder.endEncoding();
    }

    {
        var encoder = Spu.InstructionEncoder.init(200);
        for (0..text2.len) |i| {
            const c = text2[i];
            _ = encoder.encodeSllI(5, 7, 3);
            _ = encoder.encodeAddI(5, 5, getFontVramAddr(c, 0, 0));
            _ = encoder.encodeBlit(5, .{ .vram_value_shift_increment = 8, .cram_addr_bits = 0, .alpha_bits = 8, .cram_addr_offset = 3 });
            _ = encoder.encodeSleep(Spu.InstructionEncoder.RZ, 4);
        }
        _ = encoder.encodeRet();
        encoder.endEncoding();
    }

    {
        var encoder = Spu.InstructionEncoder.init(400);
        _ = encoder.encodeLi(7, 0);
        _ = encoder.encodeLi(6, 8);
        const loop_addr = encoder.encodeCall(1, 0);
        _ = encoder.encodeBlit(Spu.InstructionEncoder.RZ, .{ .alpha_bits = 1 });
        _ = encoder.encodeLi(5, (common.LINE + 1) - 1 - 11);
        _ = encoder.encodeSllI(4, 2, 3);
        _ = encoder.encodeSubR(5, 5, 4);
        _ = encoder.encodeSleep(5, 0);
        _ = encoder.encodeInc(7);
        _ = encoder.encodeBne(7, 6, loop_addr);
        _ = encoder.encodeRet();
        encoder.endEncoding();
    }

    spu.engines[2].reset(20);

    // Wait for vblank and start
    Spu.waitForVblank();
    spu.engines[0].start();
    spu.engines[1].start();
    spu.engines[2].start();

    // Main loop
    var buttons_last: u2 = 0;
    while (true) {
        const buttons = mmio.readButtons();
        if (buttons & 1 != 0 and buttons_last & 1 == 0) {
            spu.engines[1].stop();
        }
        if (buttons & 2 != 0 and buttons_last & 2 == 0) {
            spu.engines[1].start();
        }
        buttons_last = buttons;
        mmio.writeLed(buttons);

        // Wait for vblank
        Spu.waitForVblank();
    }
}
