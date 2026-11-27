const common = @import("../common/common.zig");
const mmio = @import("../common/mmio.zig");

pub const CommandEncoder = struct {
    const Kind = enum(u3) { end_line = 1, fill = 2, span = 3, tiles = 4 };

    const Command = packed struct(u64) {
        kind: Kind,
        payload: packed union(u61) {
            raw: u61,
            fill: packed struct(u61) {
                begin_x: u10,
                end_x: u10,
                color: u32,
                reserved: u9 = 0,
            },
            span: packed struct(u61) {
                begin_x: u10,
                len: u10,
                vram_addr_13_2: u12,
                vram_bits_log2: u2,
                vram_bit_offset: u5,
                cram_addr_offset: u8,
                reserved: u14 = 0,
            },
            tiles: packed struct(u61) {
                begin_x: u10,
                tilemap_vram_addr_13_2: u12,
                tile_count: u8,
                tileset_vram_addr: u14,
                tile_width_log2: u3,
                tile_stride_log2_4_2: u3,
                vram_bits_log2: u2,
                cram_addr_offset: u8,
                reserved: u1 = 0,
            },
        },
    };

    addr: mmio.CmdramAddr,

    pub fn init() CommandEncoder {
        return .{ .addr = 0 };
    }

    fn writeCommand(self: *CommandEncoder, cmd: Command) void {
        mmio.writeCmdram(self.addr, @bitCast(cmd));
        self.addr += 1;
    }

    pub fn cmdEndLine(self: *CommandEncoder) void {
        self.writeCommand(.{ .kind = .end_line, .payload = .{ .raw = 0 } });
    }

    pub fn cmdFill(self: *CommandEncoder, begin_x: u10, end_x: u10, color: u32) void {
        self.writeCommand(.{ .kind = .fill, .payload = .{ .fill = .{
            .begin_x = begin_x,
            .end_x = end_x,
            .color = color,
        } } });
    }

    pub fn cmdSpan(self: *CommandEncoder, begin_x: u10, len: u10, vram_addr: mmio.VramAddr, vram_bits: u32, cram_addr_offset: mmio.CramAddr) void {
        self.writeCommand(.{ .kind = .span, .payload = .{ .span = .{
            .begin_x = begin_x,
            .len = len,
            .vram_addr_13_2 = @intCast(vram_addr >> 2),
            .vram_bits_log2 = @intCast(31 - @clz(vram_bits)),
            .vram_bit_offset = @intCast((vram_addr & 0x3) * 8),
            .cram_addr_offset = cram_addr_offset,
        } } });
    }

    pub fn cmdTiles(self: *CommandEncoder, begin_x: u10, tilemap_vram_addr: mmio.VramAddr, tile_count: u8, tileset_vram_addr: mmio.VramAddr, tile_width: u32, tile_stride: u32, vram_bits: u32, cram_addr_offset: mmio.CramAddr) void {
        // TODO: assert that 2 LSB of tilemap_vram_addr are 0
        self.writeCommand(.{ .kind = .tiles, .payload = .{ .tiles = .{
            .begin_x = begin_x,
            .tilemap_vram_addr_13_2 = @intCast(tilemap_vram_addr >> 2),
            .tile_count = tile_count,
            .tileset_vram_addr = tileset_vram_addr,
            .tile_width_log2 = @intCast(31 - @clz(tile_width)),
            .tile_stride_log2_4_2 = @intCast(31 - @clz(tile_stride) - 2),
            .vram_bits_log2 = @intCast(31 - @clz(vram_bits)),
            .cram_addr_offset = cram_addr_offset,
        } } });
    }
};
