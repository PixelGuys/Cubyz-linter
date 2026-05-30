const std = @import("std");

const main = @import("main");

pub fn check(ctx: main.Context) void {
	var lineStart: bool = true;
	for (ctx.data, 0..) |char, i| {
		if (lineStart and char == '\t') continue;
		if (lineStart and char == ' ') {
			ctx.printError("Incorrect indentation. Please use tabs instead of spaces.", i);
			lineStart = false;
			continue;
		}
		lineStart = char == '\n';
	}
}
