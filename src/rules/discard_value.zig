const std = @import("std");

const main = @import("main");

pub fn check(ctx: main.Context) void {
	const ast = ctx.ast orelse return;

	for (0..ast.nodes.len) |nodeIndex| {
		const node: std.zig.Ast.Node.Index = @enumFromInt(nodeIndex);
		if (ast.nodeTag(node) != .assign) continue;

		const data = ast.nodeData(node).node_and_node;

		const name = data.@"0".toOptional().unwrap() orelse continue;
		var expression = data.@"1".toOptional().unwrap() orelse continue;

		while (ast.nodeTag(expression) == .address_of) {
			expression = ast.nodeData(expression).node;
		}

		if (ast.nodeTag(name) != .identifier) continue;
		if (ast.nodeTag(expression) != .identifier) continue;
		if (!std.mem.eql(u8, ast.getNodeSource(name), "_")) continue;

		ctx.printError("Do not discard variables, for parameters discard the parameter directly", ast.tokenStart(ast.nodeMainToken(node)));
	}
}
