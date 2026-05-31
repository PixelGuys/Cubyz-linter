const std = @import("std");

const main = @import("main");

fn checkType(ctx: main.Context, comptime typ: enum {@"if", @"while", @"for"}, node: std.zig.Ast.Node.Index, thenExpression: std.zig.Ast.Node.Index, elseToken: std.zig.Ast.TokenIndex, elseExpression: ?std.zig.Ast.Node.Index) void {
	const ast = ctx.ast orelse unreachable;

	switch (ast.nodeTag(thenExpression)) {
		.block, .block_semicolon, .block_two, .block_two_semicolon => {},
		else => {
			if (std.mem.findScalar(u8, ast.getNodeSource(node), '\n')) |index| {
				ctx.printError(@tagName(typ) ++ " expression should either be on a single line or use a block", ast.tokenStart(ast.firstToken(node)) + index);
			}
		},
	}
	switch (ast.nodeTag(elseExpression orelse return)) {
		.block, .block_semicolon, .block_two, .block_two_semicolon, .if_simple, .@"if" => {},
		else => {
			const elseStart = ast.tokenStart(elseToken);
			const end = ast.tokenToSpan(ast.lastToken(node)).end;
			if (std.mem.findScalar(u8, ctx.data[elseStart..end], '\n')) |index| {
				ctx.printError("else expression should either be on a single line or use a block", elseStart + index);
			}
		},
	}
}

pub fn check(ctx: main.Context) void {
	const ast = ctx.ast orelse return;

	for (0..ast.nodes.len) |nodeIndex| {
		const node: std.zig.Ast.Node.Index = @enumFromInt(nodeIndex);
		if (ast.fullIf(node)) |ifData| {
			checkType(ctx, .@"if", node, ifData.ast.then_expr, ifData.else_token, ifData.ast.else_expr.unwrap());
		}
		if (ast.fullWhile(node)) |whileData| {
			checkType(ctx, .@"while", node, whileData.ast.then_expr, whileData.else_token, whileData.ast.else_expr.unwrap());
		}
		if (ast.fullFor(node)) |forData| {
			checkType(ctx, .@"for", node, forData.ast.then_expr, forData.else_token orelse undefined, forData.ast.else_expr.unwrap());
		}
	}
}
