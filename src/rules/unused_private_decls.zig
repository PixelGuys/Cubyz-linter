const std = @import("std");

const main = @import("main");

pub fn check(ctx: main.Context) void {
	const ast = ctx.ast orelse return;
	const root = ast.rootDecls();

	var identifiers: std.StringHashMapUnmanaged(void) = .empty;
	defer identifiers.deinit(main.allocator);

	identifiers.put(main.allocator, "std", {}) catch @panic("OOM");
	identifiers.put(main.allocator, "main", {}) catch @panic("OOM");

	for (0..ast.nodes.len) |nodeIndex| {
		const node: std.zig.Ast.Node.Index = @enumFromInt(nodeIndex);
		if (ast.nodeTag(node) == .identifier) {
			_ = identifiers.getOrPut(main.allocator, ast.getNodeSource(node)) catch @panic("OOM");
		}
	}

	for (root) |node| {
		if (ast.nodeTag(node) != .simple_var_decl) continue;
		const varDec = ast.simpleVarDecl(node);
		if (varDec.visib_token != null) continue;
		const name = ast.tokenSlice(varDec.ast.mut_token + 1);
		if (!identifiers.contains(name)) {
			ctx.printError("Unused declaration", ast.tokenStart(varDec.firstToken()));
		}
	}
}
