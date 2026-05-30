const std = @import("std");

const main = @import("main");

pub fn check(ctx: main.Context) void {
	if (std.mem.findScalar(u8, ctx.data, '\r')) |index| {
		ctx.printError("Incorrect line ending \\r. Please configure your editor to use LF instead CRLF.", index);
	}
}
