const std = @import("std");

const main = @import("main");

pub fn check(ctx: main.Context) void {
	if (ctx.data.len < 1) return;

	for (0..ctx.data.len - 1) |i| {
		if ((ctx.data[i] == ' ' or ctx.data[i] == '\t') and ctx.data[i + 1] == '\n') {
			ctx.printError("Line contains trailing whitespaces. Please remove them.", i);
		}
	}
}
