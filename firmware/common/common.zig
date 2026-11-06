pub const WIDTH = 640;
pub const HEIGHT = 480;
pub const LINE = 799;
pub const SCREEN = 524;

pub fn multiplyNormalized8x8(a: u8, b: u8) u8 {
    const product1 = @as(u16, @intCast(a)) * @as(u16, @intCast(b)) + 128;
    const product2 = product1 + (product1 >> 8);
    return product2 >> 8;
}

pub const Rgba = struct {
    raw: [4]u8,

    pub fn init(r_: u8, g_: u8, b_: u8, a_: u8) Rgba {
        return .{.raw = .{r_, g_, b_, a_}};
    }

    pub fn initPremultiplied(r_: u8, g_: u8, b_: u8, a_: u8) Rgba {
        return init(r_, g_, b_, a_).premultiplied();
    }

    pub fn premultiply(self: *Rgba) void {
        for (0..3) |i| {
            self.raw[i] = multiplyNormalized8x8(self.raw[i], self.raw[3]);
        }
    }

    pub fn premultiplied(self: *const Rgba) Rgba {
        var res: Rgba = self.*;
        res.premultiply();
        return res;
    }

    pub fn toRawBits(self: *const Rgba) u32 {
        return (@as(u32, @intCast(self.a())) << 24) | (@as(u32, @intCast(self.b())) << 16) | (@as(u32, @intCast(self.g())) << 8) | (@as(u32, @intCast(self.r())) << 0);
    }

    pub fn r(self: *const Rgba) u8 {
        return self.raw[0];
    }

    pub fn g(self: *const Rgba) u8 {
        return self.raw[1];
    }

    pub fn b(self: *const Rgba) u8 {
        return self.raw[2];
    }

    pub fn a(self: *const Rgba) u8 {
        return self.raw[3];
    }
};
