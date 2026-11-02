pub fn writeLed(value: u5) void {
    const ptr = @as(*volatile u32, @ptrFromInt(0x10000000));
    ptr.* = value;
}

pub fn readButtons() u2 {
    const ptr = @as(*volatile u32, @ptrFromInt(0x10000004));
    return @intCast(ptr.*);
}

pub fn readScreenWidth() u32 {
    const ptr = @as(*volatile u32, @ptrFromInt(0x10000008));
    return ptr.*;
}

pub fn readScreenHeight() u32 {
    const ptr = @as(*volatile u32, @ptrFromInt(0x1000000c));
    return ptr.*;
}

pub fn readVblank() bool {
    const ptr = @as(*volatile u32, @ptrFromInt(0x10000010));
    // TODO: emit plain bit cast
    return ptr.* != 0;
}

pub fn waitForVblank() void {
    while (readVblank()) {}
    while (!readVblank()) {}
}

pub const EngineIndex = u4;

pub fn spuCtrl(engine: EngineIndex, cmd: u32) void {
    const ptr = @as(*volatile u32, @ptrFromInt(0x20000000 + @as(u32, @intCast(engine)) * @sizeOf(u32)));
    ptr.* = cmd;
}

pub const CramAddr = u8;

pub fn writeCram(index: CramAddr, color: u24) void {
    const ptr = @as(*volatile u32, @ptrFromInt(0x24000000 + @as(u32, @intCast(index)) * 4));
    ptr.* = color;
}

pub const VramAddr = u14;

pub fn writeVram(index: VramAddr, value: u8) void {
    const ptr = @as(*volatile u32, @ptrFromInt(0x28000000 + @as(u32, @intCast(index)) * 4));
    ptr.* = value;
}

pub const CmdramAddr = u12;

pub fn writeCmdram(addr: CmdramAddr, cmd: u32) void {
    const ptr = @as(*volatile u32, @ptrFromInt(0x2c000000 + @as(u32, @intCast(addr)) * @sizeOf(u32)));
    ptr.* = cmd;
}
