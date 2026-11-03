pub fn writeLed(value: u5) void {
    const ptr = @as(*volatile u32, @ptrFromInt(0x10000000));
    ptr.* = value;
}

pub fn readButtons() u2 {
    const ptr = @as(*volatile u32, @ptrFromInt(0x10000004));
    return @intCast(ptr.*);
}

pub fn readTargetLine() u10 {
    const ptr = @as(*volatile u32, @ptrFromInt(0x10000010));
    return @intCast(ptr.*);
}

pub fn waitForNextLine() u10 {
    const prev = readTargetLine();
    var line = prev;
    while (line == prev) line = readTargetLine();
    return line;
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

pub const CmdramAddr = u8;

pub fn writeCmdram(addr: CmdramAddr, cmd: u64) void {
    const ptr = @as(*volatile u64, @ptrFromInt(0x2c000000 + @as(u32, @intCast(addr)) * @sizeOf(u64)));
    ptr.* = cmd;
}
