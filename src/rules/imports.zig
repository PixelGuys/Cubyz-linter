const std = @import("std");

const main = @import("main");

fn isAliasAllowed(_importName: []const u8, _aliasName: []const u8) bool {
	var importName = _importName;
	var aliasName = _aliasName;

	if (importName.len != 0 and importName[0] == '"') importName = std.mem.trim(u8, importName, "\"");

	if (std.mem.endsWith(u8, importName, "_list.zig")) return true;
	if (std.mem.eql(u8, aliasName, "Atomic") and std.mem.eql(u8, importName, "Value")) return true;

	if (std.mem.endsWith(u8, importName, ".zon")) importName.len -= 4;
	if (std.mem.endsWith(u8, importName, ".zig")) importName.len -= 4;

	if (importName.len != 0 and importName[0] == '@') importName = importName[2 .. importName.len - 1];
	if (aliasName.len != 0 and aliasName[0] == '@') aliasName = aliasName[2 .. aliasName.len - 1];

	if (std.mem.eql(u8, importName, aliasName)) return true;

	if (std.mem.findLast(u8, importName, "/")) |i| importName = importName[i + 1 ..];

	if (std.mem.findLast(u8, importName, ":")) |i| importName = importName[i + 1 ..];
	if (std.mem.findLast(u8, aliasName, ":")) |i| aliasName = aliasName[i + 1 ..];

	if (std.mem.eql(u8, importName, "world") and std.mem.eql(u8, aliasName, "world_zig")) return true; // TODO: Remove after https://github.com/PixelGuys/Cubyz/issues/3069

	return std.mem.eql(u8, importName, aliasName);
}

pub fn check(ctx: main.Context) void {
	const ast = ctx.ast;
	const root = ast.rootDecls();
	var firstNonImportNode: ?std.zig.Ast.Node.Index = null;

	for (root) |node| {
		const isImport: bool = blk: {
			if (ast.nodeTag(node) != .simple_var_decl) break :blk false;
			const varDec = ast.simpleVarDecl(node);
			const aliasName = ast.tokenSlice(varDec.ast.mut_token + 1);
			const rhsNode = varDec.ast.init_node.unwrap().?;

			switch (ast.nodeTag(rhsNode)) {
				.builtin_call_two_comma => { // @import("x",)
					const token = ast.nodeMainToken(rhsNode);
					const importKeyword = ast.tokenSlice(token);
					if (!std.mem.eql(u8, importKeyword, "@import")) break :blk false;
					ctx.printError("@import should not have a trailing comma.", ast.tokenStart(token));
					break :blk true;
				},
				.builtin_call_two => { // @import("x")
					const importKeyword = ast.tokenSlice(ast.nodeMainToken(rhsNode));
					if (!std.mem.eql(u8, importKeyword, "@import")) break :blk false;

					const token = ast.nodeMainToken(ast.nodeData(rhsNode).opt_node_and_opt_node[0].unwrap().?);
					var importName = ast.tokenSlice(token);
					importName = importName[1 .. importName.len - 1];

					if (!isAliasAllowed(importName, aliasName)) {
						ctx.printError("Encountered import with mismatched name", ast.tokenStart(token));
					}
					break :blk true;
				},
				.field_access => { // alias
					const token = ast.nodeData(rhsNode).node_and_token[1];
					const importName = ast.tokenSlice(token);

					if (!isAliasAllowed(importName, aliasName)) {
						if (firstNonImportNode != null) break :blk false;
						ctx.printError("Encountered alias with mismatched name", ast.tokenStart(token));
					}
					break :blk true;
				},
				else => break :blk false,
			}
		};
		if (isImport) {
			if (firstNonImportNode) |nonImportNode| {
				ctx.printError("Encountered import/alias after import section", ast.tokenStart(ast.firstToken(node)));
				ctx.printInfo("determined end of import section", ast.tokenStart(ast.firstToken(nonImportNode)));
			}
		} else {
			if (firstNonImportNode == null) {
				firstNonImportNode = node;
			}
		}
	}
}
