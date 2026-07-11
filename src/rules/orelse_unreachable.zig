const std = @import("std");

const main = @import("main");

pub fn check(ctx: main.Context) void {
	const ast = ctx.ast orelse return;

	for (0..ast.nodes.len) |nodeIndex| {
		const node: std.zig.Ast.Node.Index = @enumFromInt(nodeIndex);
		if (ast.nodeTag(node) != .@"orelse") continue;

		const token = ast.nodeMainToken(node);
		const nextToken = ast.tokens.get(token + 1);
		if (nextToken.tag != .keyword_unreachable) continue;

		ctx.printError("please use .? instead of orelse unreachable", ast.tokenStart(token));
	}
}
