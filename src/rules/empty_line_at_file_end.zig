const std = @import("std");

const main = @import("main");

pub fn check(ctx: main.Context) void {
	if (ctx.data.len != 0 and ctx.data[ctx.data.len - 1] != '\n' or (ctx.data.len > 2 and ctx.data[ctx.data.len - 2] == '\n')) {
		ctx.printError("File should end with a single empty line", ctx.data.len - 1);
	}
}