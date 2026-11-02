const std = @import("std");
const common = @import("../common/common.zig");
const mmio = @import("../common/mmio.zig");

const InstructionEncoder = @This();

const Value = u20;
const RSel = u3;

pub const RZ: RSel = 0;

addr: mmio.CmdramAddr,

const Opcode = enum(u3) {
    arithmetic = 0b000,
    logical = 0b001,
    jump = 0b010,
    branch = 0b011,
    call = 0b100,
    ret = 0b101,
    blit = 0b110,
    sleep = 0b111,
};

const VariantR = packed struct {
    opcode: Opcode,
    rd: RSel,
    funct3: u3,
    ra: RSel,
    rb: RSel,
    reserved: u17 = 0,
};

const VariantI = packed struct {
    opcode: Opcode,
    rd: RSel,
    funct3: u3,
    ra: RSel,
    imm: Value,
};

const VariantS = packed struct {
    opcode: Opcode,
    imm6: u6,
    ra: RSel,
    imm9: u9,
    reserved: u11 = 0,
};

const VariantB = packed struct {
    opcode: Opcode,
    reserved_3: u3 = 0,
    funct3: u3,
    ra: RSel,
    rb: RSel,
    addr: mmio.CmdramAddr,
    reserved_27: u5 = 0,
};

const VariantU = packed struct {
    opcode: Opcode,
    rd: RSel,
    funct3: u3,
    reserved_9: u3 = 0,
    imm: Value,
};

const VariantJ = packed struct {
    opcode: Opcode,
    reserved_3: u3 = 0,
    funct3: u3,
    ra: RSel,
    reserved_12: u3 = 0,
    imm: mmio.CmdramAddr,
    reserved_27: u5 = 0,
};

pub fn init(addr: mmio.CmdramAddr) InstructionEncoder {
    return .{ .addr = addr };
}

pub fn getCyclesFromCoords(x: u10, y: u10) u20 {
    // A line is LINE + 1 cycles, since LINE is the last x
    return @as(u20, y) * (common.LINE + 1) + x;
}

fn write(self: *InstructionEncoder, inst: anytype) mmio.CmdramAddr {
    const addr = self.addr;
    mmio.writeCmdram(addr, @bitCast(inst));
    self.addr += 1;

    return addr;
}

//pub fn encodeLui(self: *InstructionEncoder, rd: RSel, imm: Value) mmio.CmdramAddr {
//    return self.write(VariantU{
//        .opcode = .lui,
//        .funct3 = 0,
//        .rd = rd,
//        .imm = imm,
//    });
//}

pub fn encodeAddR(self: *InstructionEncoder, rd: RSel, ra: RSel, rb: RSel) mmio.CmdramAddr {
    return self.write(VariantR{
        .opcode = .arithmetic,
        .rd = rd,
        .funct3 = 0b000,
        .ra = ra,
        .rb = rb,
    });
}

pub fn encodeAddI(self: *InstructionEncoder, rd: RSel, ra: RSel, imm: Value) mmio.CmdramAddr {
    return self.write(VariantI{
        .opcode = .arithmetic,
        .rd = rd,
        .funct3 = 0b100,
        .ra = ra,
        .imm = imm,
    });
}

pub fn encodeSubR(self: *InstructionEncoder, rd: RSel, ra: RSel, rb: RSel) mmio.CmdramAddr {
    return self.write(VariantR{
        .opcode = .arithmetic,
        .rd = rd,
        .funct3 = 0b001,
        .ra = ra,
        .rb = rb,
    });
}

pub fn encodeSubI(self: *InstructionEncoder, rd: RSel, ra: RSel, imm: Value) mmio.CmdramAddr {
    return self.write(VariantI{
        .opcode = .arithmetic,
        .rd = rd,
        .funct3 = 0b101,
        .ra = ra,
        .imm = imm,
    });
}

pub fn encodeSllR(self: *InstructionEncoder, rd: RSel, ra: RSel, rb: RSel) mmio.CmdramAddr {
    return self.write(VariantR{
        .opcode = .logical,
        .rd = rd,
        .funct3 = 0b000,
        .ra = ra,
        .rb = rb,
    });
}

pub fn encodeSllI(self: *InstructionEncoder, rd: RSel, ra: RSel, imm: u5) mmio.CmdramAddr {
    return self.write(VariantI{
        .opcode = .logical,
        .rd = rd,
        .funct3 = 0b100,
        .ra = ra,
        .imm = imm,
    });
}

pub fn encodeSrlR(self: *InstructionEncoder, rd: RSel, ra: RSel, rb: RSel) mmio.CmdramAddr {
    return self.write(VariantR{
        .opcode = .logical,
        .rd = rd,
        .funct3 = 0b001,
        .ra = ra,
        .rb = rb,
    });
}

pub fn encodeSrlI(self: *InstructionEncoder, rd: RSel, ra: RSel, imm: u5) mmio.CmdramAddr {
    return self.write(VariantI{
        .opcode = .logical,
        .rd = rd,
        .funct3 = 0b101,
        .ra = ra,
        .imm = imm,
    });
}

pub fn encodeJal(self: *InstructionEncoder, ra: RSel, imm: mmio.CmdramAddr) mmio.CmdramAddr {
    const inst_addr = self.write(VariantJ{
        .opcode = .jump,
        .funct3 = 0,
        .ra = ra,
        .imm = imm,
    });

    return inst_addr;
}

pub fn encodeBne(self: *InstructionEncoder, ra: RSel, rb: RSel, addr: mmio.CmdramAddr) mmio.CmdramAddr {
    return self.write(VariantB{
        .opcode = .branch,
        .funct3 = 0b000,
        .ra = ra,
        .rb = rb,
        .addr = addr,
    });
}

pub fn encodeCall(self: *InstructionEncoder, ra: RSel, imm: mmio.CmdramAddr) mmio.CmdramAddr {
    const inst_addr = self.write(VariantJ{
        .opcode = .call,
        .funct3 = 0,
        .ra = ra,
        .imm = imm,
    });

    return inst_addr;
}

pub fn encodeRet(self: *InstructionEncoder) mmio.CmdramAddr {
    const inst_addr = self.write(VariantS{
        .opcode = .ret,
        .imm6 = 0,
        .ra = RZ,
        .imm9 = 0,
    });

    return inst_addr;
}

pub const BlitParam = packed struct {
    vram_value_shift_increment: u4 = 0,
    cram_addr_bits: u4 = 8,
    alpha_bits: u4 = 0,
    cram_addr_offset: u3 = 0,
};

pub fn encodeBlit(self: *InstructionEncoder, ra: RSel, param: BlitParam) mmio.CmdramAddr {
    const param_raw: u15 = @bitCast(param);
    return self.write(VariantS{
        .opcode = .blit,
        .imm6 = @intCast(param_raw & 0x3f),
        .ra = ra,
        .imm9 = @intCast((param_raw >> 6) & 0x1ff),
    });
}

// The next instruction executes cycles + 1 cycles after the sleep
pub fn encodeSleep(self: *InstructionEncoder, ra: RSel, imm: Value) mmio.CmdramAddr {
    const addr = self.write(VariantI{
        .opcode = .sleep,
        .rd = RZ,
        .funct3 = 0,
        .ra = ra,
        .imm = imm,
    });

    return addr;
}

// Pseudo instructions
pub fn encodeMv(self: *InstructionEncoder, rd: RSel, ra: RSel) mmio.CmdramAddr {
    return self.encodeAddI(rd, ra, 0);
}

pub fn encodeLi(self: *InstructionEncoder, rd: RSel, imm: Value) mmio.CmdramAddr {
    return self.encodeAddI(rd, RZ, imm);
}

pub fn encodeInc(self: *InstructionEncoder, rd: RSel) mmio.CmdramAddr {
    return self.encodeAddI(rd, rd, 1);
}

pub fn encodeDec(self: *InstructionEncoder, rd: RSel) mmio.CmdramAddr {
    return self.encodeSubI(rd, rd, 1);
}

pub fn encodeBnz(self: *InstructionEncoder, ra: RSel, addr: mmio.CmdramAddr) mmio.CmdramAddr {
    return self.encodeBne(ra, RZ, addr);
}

// Helpers
pub fn endEncoding(self: *InstructionEncoder) void {
    // Jump to the same instruction
    _ = self.encodeJal(RZ, self.addr);
}
