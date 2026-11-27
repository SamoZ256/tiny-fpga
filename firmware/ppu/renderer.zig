const std = @import("std");
const common = @import("../common/common.zig");
const mmio = @import("../common/mmio.zig");
const CommandEncoder = @import("command_encoder.zig").CommandEncoder;

pub const Renderer = struct {
    const Command = struct {
        const Kind = enum {
            fill,
            sprite,
            tiles,
        };

        x: u10,
        y: u10,
        height: u10,

        param: union(Kind) {
            fill: struct {
                width: u10,
                color: common.Rgba,
            },
            sprite: struct {
                width: u10,
                vram_addr: mmio.VramAddr,
                vram_bits: u32,
                row_stride: u8,
                cram_addr_offset: mmio.CramAddr,
            },
            tiles: struct {
                tilemap_vram_addr: mmio.VramAddr,
                tile_count: u8,
                tileset_vram_addr: mmio.VramAddr,
                tile_width: u32,
                tile_row_stride: u8,
                tile_stride: u32,
                vram_bits: u32,
                cram_addr_offset: mmio.CramAddr,
            },
        },
    };

    const BUCKET_COUNT = 8;

    allocator: std.mem.Allocator,

    width: u10,
    height: u10,

    commands: std.ArrayList(Command),
    buckets: [BUCKET_COUNT]std.ArrayList(u16),

    pub fn initializePalette() void {
        // TODO: better
        mmio.writeCram(0, common.Rgba.initPremultiplied(0xff, 0x00, 0xff, 0xff).toRawBits());
        mmio.writeCram(1, common.Rgba.initPremultiplied(0x00, 0x00, 0x00, 0x00).toRawBits());
        mmio.writeCram(2, common.Rgba.initPremultiplied(0xff, 0xff, 0xff, 0xff).toRawBits());
        mmio.writeCram(3, common.Rgba.initPremultiplied(0xff, 0x00, 0x00, 0xff).toRawBits());
        mmio.writeCram(4, common.Rgba.initPremultiplied(0x00, 0xff, 0x00, 0xff).toRawBits());
        mmio.writeCram(5, common.Rgba.initPremultiplied(0x00, 0x00, 0xff, 0xff).toRawBits());
    }

    pub fn init(allocator: std.mem.Allocator, width: u10, height: u10) !Renderer {
        var self: Renderer = undefined;
        self.allocator = allocator;
        self.width = width;
        self.height = height;
        self.commands = try std.ArrayList(Command).initCapacity(allocator, 16);
        for (self.buckets[0..]) |*bucket| {
            bucket.* = try std.ArrayList(u16).initCapacity(allocator, 16);
        }

        return self;
    }

    pub fn deinit(self: *Renderer) void {
        self.commands.deinit(self.allocator);
        for (self.buckets[0..]) |*bucket| {
            bucket.deinit(self.allocator);
        }
    }

    pub fn updateSize(self: *Renderer, width: u10, height: u10) void {
        self.width = width;
        self.height = height;
    }

    pub fn clear(self: *Renderer) void {
        self.commands.clearRetainingCapacity();
        for (self.buckets[0..]) |*bucket| {
            bucket.clearRetainingCapacity();
        }
    }

    fn encodeCommand(encoder: *CommandEncoder, line: u10, cmd: *const Command) void {
        if (line < cmd.y or line >= cmd.y + cmd.height) {
            return;
        }
        const rel_y = line - cmd.y;

        switch (cmd.param) {
            .fill => |fill| encoder.cmdFill(cmd.x, cmd.x + fill.width, fill.color.toRawBits()),
            .sprite => |sprite| encoder.cmdSpan(cmd.x, sprite.width, sprite.vram_addr + rel_y * sprite.row_stride, sprite.vram_bits, sprite.cram_addr_offset),
            .tiles => |tiles| encoder.cmdTiles(cmd.x, tiles.tilemap_vram_addr, tiles.tile_count, tiles.tileset_vram_addr + rel_y * tiles.tile_row_stride, tiles.tile_width, tiles.tile_stride, tiles.vram_bits, tiles.cram_addr_offset),
        }
    }

    pub fn renderLine(self: *Renderer, encoder: *CommandEncoder, line: u10) void {
        const bucket = &self.buckets[@as(u16, @intCast(line)) * BUCKET_COUNT / self.height];
        for (bucket.items) |cmd_index| {
            const cmd = &self.commands.items[cmd_index];
            encodeCommand(encoder, line, cmd);
        }
    }

    fn addLastCommandToBuckets(self: *Renderer) !void {
        const index: u16 = @intCast(self.commands.items.len - 1);
        const cmd = self.commands.items[index];
        const begin = @as(u16, @intCast(cmd.y)) * BUCKET_COUNT / self.height;
        const end = ((@as(u16, @intCast(cmd.y)) + cmd.height) * BUCKET_COUNT + self.height - 1) / self.height;
        for (begin..end) |i| {
            try self.buckets[i].append(self.allocator, index);
        }
    }

    pub fn cmdFill(self: *Renderer, x: u10, y: u10, width: u10, height: u10, color: common.Rgba) !void {
        try self.commands.append(self.allocator, .{
            .x = x,
            .y = y,
            .height = height,
            .param = .{ .fill = .{
                .width = width,
                .color = color,
            } },
        });
        try self.addLastCommandToBuckets();
    }

    pub fn cmdSprite(self: *Renderer, x: u10, y: u10, width: u10, height: u10, vram_addr: mmio.VramAddr, vram_bits: u32, row_stride: u8, cram_addr_offset: mmio.CramAddr) !void {
        try self.commands.append(self.allocator, .{
            .x = x,
            .y = y,
            .height = height,
            .param = .{ .sprite = .{
                .width = width,
                .vram_addr = vram_addr,
                .vram_bits = vram_bits,
                .row_stride = row_stride,
                .cram_addr_offset = cram_addr_offset,
            } },
        });
        try self.addLastCommandToBuckets();
    }

    pub fn cmdTiles(self: *Renderer, x: u10, y: u10, height: u10, tilemap_vram_addr: mmio.VramAddr, tile_count: u8, tileset_vram_addr: mmio.VramAddr, tile_width: u32, tile_row_stride: u8, tile_stride: u32, vram_bits: u32, cram_addr_offset: mmio.CramAddr) !void {
        try self.commands.append(self.allocator, .{
            .x = x,
            .y = y,
            .height = height,
            .param = .{ .tiles = .{
                .tilemap_vram_addr = tilemap_vram_addr,
                .tile_count = tile_count,
                .tileset_vram_addr = tileset_vram_addr,
                .tile_width = tile_width,
                .tile_row_stride = tile_row_stride,
                .tile_stride = tile_stride,
                .vram_bits = vram_bits,
                .cram_addr_offset = cram_addr_offset,
            } },
        });
        try self.addLastCommandToBuckets();
    }
};
