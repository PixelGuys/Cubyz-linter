const std = @import("std");

const main = @import("main");

const maxLineNumber = 100;

pub fn check(ctx: main.Context) void {
	const ast = ctx.ast orelse return;

	var buffer: [2]std.zig.Ast.Node.Index = undefined;
	for (0..ast.nodes.len) |nodeIndex| {
		const node: std.zig.Ast.Node.Index = @enumFromInt(nodeIndex);
		if (ast.nodeTag(node) != .simple_var_decl) continue;
		const varDec = ast.simpleVarDecl(node);
		if (varDec.ast.type_node.unwrap() != null) continue;
		var name = ast.tokenSlice(varDec.ast.mut_token + 1);
		if (name.len != 0 and name[0] == '@') name = name[2 .. name.len - 1];

		const rhsNode = varDec.ast.init_node.unwrap() orelse continue;
		_ = ast.fullContainerDecl(&buffer, rhsNode) orelse continue;

		const firstToken = ast.firstToken(rhsNode);
		const lastToken = ast.lastToken(rhsNode);

		const firstTokenlocation = ast.tokenLocation(firstToken, firstToken);
		const lastTokenlocation = ast.tokenLocation(firstToken, lastToken);

		if (lastTokenlocation.line - firstTokenlocation.line < maxLineNumber) continue;

		const lineText = ctx.data[firstTokenlocation.line_start..firstTokenlocation.line_end];
		const markComment = std.fmt.allocPrint(main.allocator, "// MARK: {s}", .{name}) catch @panic("OOM");
		defer main.allocator.free(markComment);
		if (std.mem.endsWith(u8, lineText, markComment)) continue;

		const msg = std.fmt.allocPrint(main.allocator, "Container over the size of {d} should have a MARK comment like this: \"// MARK: {s}\"", .{maxLineNumber, name}) catch @panic("OOM");
		defer main.allocator.free(msg);
		ctx.printError(msg, firstTokenlocation.line_end);
	}
}
