const std = @import("std");

const main = @import("main");

pub fn check(ctx: main.Context) void {
	const ast = ctx.ast orelse return;

	for (0..ast.nodes.len) |nodeIndex| {
		const node: std.zig.Ast.Node.Index = @enumFromInt(nodeIndex);
		if (ast.fullIf(node)) |ifData| {
			const thenExpression = ifData.ast.then_expr;
			switch (ast.nodeTag(thenExpression)) {
				.block, .block_semicolon, .block_two, .block_two_semicolon => {},
				else => {
					if (std.mem.findScalar(u8, ast.getNodeSource(node), '\n')) |index| {
						ctx.printError("if expression should either be on a single line or use a block", ast.tokenStart(ast.nodeMainToken(node)) + index);
					}
				},
			}
			const elseExpression = ifData.ast.else_expr.unwrap() orelse continue;
			switch (ast.nodeTag(elseExpression)) {
				.block, .block_semicolon, .block_two, .block_two_semicolon, .if_simple, .@"if" => {},
				else => {
					const elseStart = ast.tokenStart(ifData.else_token);
					const end = ast.tokenToSpan(ast.lastToken(node)).end;
					if (std.mem.findScalar(u8, ctx.data[elseStart..end], '\n')) |index| {
						ctx.printError("else expression should either be on a single line or use a block", elseStart + index);
					}
				},
			}
		}
	}
}
