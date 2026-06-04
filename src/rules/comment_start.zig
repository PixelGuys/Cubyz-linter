const std = @import("std");

const main = @import("main");

pub fn check(ctx: main.Context) void {
	if (ctx.data.len <= 3) return;

	for (0..ctx.data.len - 3) |i| { //extra
		if (ctx.data[i] != '/' or ctx.data[i + 1] != '/') continue;
		const commentStart = if (ctx.data[i + 2] == '/' or ctx.data[i + 2] == '!') i + 3 else i + 2;
		if (ctx.data[commentStart] != ' ' and ctx.data[commentStart] != '\n') {
			if (i != 0 and ctx.data[i - 1] == ':') continue; // https://
			if (i != 0 and ctx.data[i - 1] == '"') continue; // part of a string
			ctx.printError("Comments should include a space before text, ex: // whatever", commentStart);
		}
	}
}
