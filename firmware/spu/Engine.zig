const std = @import("std");
const mmio = @import("../common/mmio.zig");

const Engine = @This();

index: u4,

pub fn init(index: u4) Engine {
    return .{ .index = index };
}

const CtrlCommand = packed struct {
    const Kind = enum(u3) { reset = 1, start = 2, stop = 3 };

    kind: Kind,
    param: u29 = 0,
};

fn ctrl(self: *const Engine, cmd: CtrlCommand) void {
    mmio.spuCtrl(self.index, @bitCast(cmd));
}

pub fn reset(self: *const Engine, addr: mmio.CmdramAddr) void {
    self.ctrl(.{
        .kind = .reset,
        .param = addr,
    });
}

pub fn start(self: *const Engine) void {
    self.ctrl(.{
        .kind = .start,
    });
}

pub fn stop(self: *const Engine) void {
    self.ctrl(.{
        .kind = .stop,
    });
}
