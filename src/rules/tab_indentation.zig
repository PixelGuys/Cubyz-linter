const std = @import("std");

const main = @import("main");

pub fn check(ctx: main.Context) void {
	if (std.mem.find(u8, ctx.data, "\n ")) |index| {
		ctx.printError("Incorrect indentation. Please use tabs instead of spaces.", index + 1);
	}
}
