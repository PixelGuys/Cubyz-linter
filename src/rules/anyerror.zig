const std = @import("std");

const main = @import("main");

pub fn check(ctx: main.Context) void {
	if (std.mem.find(u8, ctx.data, "anyerror" ++ "!")) |index| {
		if (!std.mem.eql(u8, ctx.filePath, "network/protocols.zig")) {
			ctx.printError("Found anyerror" ++ "! in file {s}. Please avoid the use of anyerror" ++ "! instead define an error set.", index);
		}
	}
}
