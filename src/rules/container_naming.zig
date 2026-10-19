const std = @import("std");

const main = @import("main");

fn checkPascalCase(ctx: main.Context, name: []const u8, tokenLocation: usize) void {
	std.debug.assert(name.len > 0);

	if (std.ascii.isLower(name[0])) {
		ctx.printError("Container names should be in PascalCase", tokenLocation);
		return;
	}

	for (name, 0..) |c, i| {
		if (!std.ascii.isAlphanumeric(c)) {
			ctx.printError("Container names should be in PascalCase", tokenLocation + i);
			return;
		}
	}
}

fn checkSnakeCase(ctx: main.Context, name: []const u8, tokenLocation: usize) void {
	for (name, 0..) |c, i| {
		if (std.ascii.isUpper(c) or (!std.ascii.isAlphanumeric(c) and c != '_' and c != ':')) {
			ctx.printError("Structs without fields are namespaces and their name should be in snake_case", tokenLocation + i);
			return;
		}
	}
}

pub fn check(ctx: main.Context) void {
	const ast = ctx.ast orelse return;

	var buffer: [2]std.zig.Ast.Node.Index = undefined;
	for (0..ast.nodes.len) |nodeIndex| {
		const node: std.zig.Ast.Node.Index = @fromBackingInt(@intCast(nodeIndex));
		if (ast.nodeTag(node) != .simple_var_decl) continue;
		const varDec = ast.simpleVarDecl(node);
		if (varDec.ast.type_node.unwrap() != null) continue;
		var name = ast.tokenSlice(varDec.ast.mut_token + 1);
		var nameStart = ast.tokenStart(varDec.ast.mut_token + 1);
		if (name.len != 0 and name[0] == '@') {
			name = name[2 .. name.len - 1];
			nameStart += 2;
		}

		const rhsNode = varDec.ast.init_node.unwrap() orelse continue;
		const container = ast.fullContainerDecl(&buffer, rhsNode) orelse continue;
		if (container.ast.members.len == 0) continue;

		const containerType = ast.tokenSlice(container.ast.main_token);

		var foundMember: bool = false;
		for (container.ast.members) |index| {
			const tag = ast.nodeTag(index);
			if (tag == .container_field_init) {
				foundMember = true;
				break;
			}

			// we also need to check for functions where the first parameter is the container.
			var fnBuffer: [1]std.zig.Ast.Node.Index = undefined;
			const fnProto = ast.fullFnProto(&fnBuffer, index) orelse continue;
			if (fnProto.ast.params.len < 1) continue;
			const param = fnProto.ast.params[0];
			if (std.mem.eql(u8, ast.getNodeSource(param), ast.tokenSlice(varDec.ast.mut_token + 1))) {
				foundMember = true;
				break;
			}
		}
		if (foundMember) {
			checkPascalCase(ctx, name, nameStart);
		} else {
			if (!std.mem.eql(u8, containerType, "struct")) continue; // else enums get seen as possible rule breakers
			checkSnakeCase(ctx, name, nameStart);
		}
	}
}
