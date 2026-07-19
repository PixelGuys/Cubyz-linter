const std = @import("std");

const main = @import("main");

pub fn check(ctx: main.Context) void {
	const ast = ctx.ast orelse return;

	var identifiers: std.StringHashMapUnmanaged(void) = .empty;
	defer identifiers.deinit(main.allocator);

	for (0..ast.nodes.len) |nodeIndex| {
		const node: std.zig.Ast.Node.Index = @enumFromInt(nodeIndex);
		switch (ast.nodeTag(node)) {
			.identifier => {
				_ = identifiers.getOrPut(main.allocator, ast.getNodeSource(node)) catch @panic("OOM");
			},
			.field_access => {
				const token = ast.nodeData(node).node_and_token[1];
				const name = ast.tokenSlice(token);
				_ = identifiers.getOrPut(main.allocator, name) catch @panic("OOM");
			},
			.enum_literal => {
				const name = ast.tokenSlice(ast.nodeMainToken(node));
				_ = identifiers.getOrPut(main.allocator, name) catch @panic("OOM");
			},
			else => continue,
		}
	}

	for (0..ast.nodes.len) |nodeIndex| {
		const node: std.zig.Ast.Node.Index = @enumFromInt(nodeIndex);
		switch (ast.nodeTag(node)) {
			.simple_var_decl => {
				if (main.rules.imports.isImport(ctx, ast, node, .ignoreAliasNameMismatch)) continue;
				const varDec = ast.simpleVarDecl(node);
				if (varDec.visib_token != null) continue;
				const name = ast.tokenSlice(varDec.ast.mut_token + 1);
				if (!identifiers.contains(name)) {
					ctx.printError("Unused declaration", ast.tokenStart(varDec.firstToken()));
				}
			},
			.fn_proto, .fn_proto_simple, .fn_proto_one, .fn_proto_multi => |tag| {
				var buffer: [1]std.zig.Ast.Node.Index = undefined;
				const functionProto = switch (tag) {
					.fn_proto => ast.fnProto(node),
					.fn_proto_simple => ast.fnProtoSimple(&buffer, node),
					.fn_proto_one => ast.fnProtoOne(&buffer, node),
					.fn_proto_multi => ast.fnProtoMulti(node),
					else => unreachable,
				};
				if (functionProto.visib_token != null) continue;
				const name = ast.tokenSlice(functionProto.name_token orelse continue);
				if (!identifiers.contains(name)) {
					ctx.printError("Unused declaration", ast.tokenStart(functionProto.firstToken()));
				}
			},
			else => continue,
		}
	}
}
