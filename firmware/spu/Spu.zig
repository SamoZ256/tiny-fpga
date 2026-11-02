const std = @import("std");
const mmio = @import("../common/mmio.zig");

const Spu = @This();

pub const Engine = @import("Engine.zig");
pub const InstructionEncoder = @import("InstructionEncoder.zig");

pub const ENGINE_COUNT = 3;

engines: [ENGINE_COUNT]Engine,

pub fn init() Spu {
    var self: Spu = undefined;
    for (0..ENGINE_COUNT) |i| {
        self.engines[i] = Engine.init(@intCast(i));
    }

    return self;
}

pub fn waitForVblank() void {
    while (mmio.readVblank()) {}
    while (!mmio.readVblank()) {}
}
