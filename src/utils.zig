const std = @import("std");
const Allocator = std.mem.Allocator;

// Mostly copied from std.Io.Dir.SelectiveWalker
pub const SelectiveWalker = struct {
	ast: std.zig.Ast,
	stack: std.ArrayList(*StackItem),
	allocator: Allocator,

	const StackItem = struct {
		index: u32 = 0,
		nodes: []const std.zig.Ast.Node.Index,
		nodes_owned: bool,

		fn deinit(self: *StackItem, allocator: Allocator) void {
			if (self.nodes_owned) allocator.free(self.nodes);
			allocator.destroy(self);
		}

		pub fn next(self: *StackItem) ?std.zig.Ast.Node.Index {
			if (self.index >= self.nodes.len) return null;
			defer self.index += 1;
			return self.nodes[self.index];
		}
	};

	pub fn next(self: *SelectiveWalker) ?std.zig.Ast.Node.Index {
		while (self.stack.items.len > 0) {
			const top = self.stack.items[self.stack.items.len - 1];

			if (top.next()) |entry| {
				return entry;
			} else {
				self.leave();
			}
		}
		return null;
	}

	pub fn tryEnter(self: *SelectiveWalker, node: std.zig.Ast.Node.Index) void {
		const body = blk: switch (self.ast.nodeTag(node)) {
			.root => break :blk node,
			.fn_decl => break :blk self.ast.nodeData(node).node_and_node[1],
			else => return,
		};
		const nodes: struct {
			nodes: []const std.zig.Ast.Node.Index,
			owned: bool,
		} = blk: switch (self.ast.nodeTag(body)) {
			.root, .block, .block_semicolon => break :blk .{
				.nodes = self.ast.extraDataSlice(self.ast.nodeData(body).extra_range, std.zig.Ast.Node.Index),
				.owned = false,
			},
			.block_two, .block_two_semicolon => {
				var nodeList: std.ArrayList(std.zig.Ast.Node.Index) = .empty;
				const nodeData = self.ast.nodeData(body).opt_node_and_opt_node;
				if (nodeData[0].unwrap()) |decl| {
					nodeList.append(self.allocator, decl) catch @panic("OOM");
				}
				if (nodeData[1].unwrap()) |decl| {
					nodeList.append(self.allocator, decl) catch @panic("OOM");
				}
				break :blk .{
					.nodes = nodeList.toOwnedSlice(self.allocator) catch @panic("OOM"),
					.owned = true,
				};
			},
			else => return,
		};
		const item = self.allocator.create(StackItem) catch @panic("OOM");
		item.* = .{
			.nodes = nodes.nodes,
			.nodes_owned = nodes.owned,
		};
		self.stack.append(
			self.allocator,
			item,
		) catch @panic("OOM");
	}

	pub fn deinit(self: *SelectiveWalker) void {
		for (self.stack.items) |item| {
			item.deinit(self.allocator);
		}
		self.stack.deinit(self.allocator);
	}

	pub fn leave(self: *SelectiveWalker) void {
		const item = self.stack.pop().?;
		item.deinit(self.allocator);
	}
};

// Mostly copied from std.Io.Dir.Walker
pub const Walker = struct {
	inner: SelectiveWalker,

	pub fn next(self: *Walker) ?std.zig.Ast.Node.Index {
		const entry = self.inner.next();
		if (entry) |node| {
			self.inner.tryEnter(node);
		}
		return entry;
	}

	pub fn deinit(self: *Walker) void {
		self.inner.deinit();
	}

	pub fn leave(self: *Walker) void {
		self.inner.leave();
	}
};

pub fn walk(ast: std.zig.Ast, index: std.zig.Ast.Node.Index, allocator: Allocator) Walker {
	return .{.inner = walkSelectively(ast, index, allocator)};
}

pub fn walkSelectively(ast: std.zig.Ast, index: std.zig.Ast.Node.Index, allocator: Allocator) SelectiveWalker {
	const stack: std.ArrayList(*SelectiveWalker.StackItem) = .empty;

	var selectiveWalker: SelectiveWalker = .{
		.ast = ast,
		.stack = stack,
		.allocator = allocator,
	};
	selectiveWalker.tryEnter(index);
	return selectiveWalker;
}

test "function block_two only one" {
	const data: [:0]const u8 =
		\\fn main() void {
		\\  var x = 1;
		\\}
	;
	var ast: std.zig.Ast = try .parse(std.testing.allocator, data, .zig);
	defer ast.deinit(std.testing.allocator);
	var walker = walk(ast, .root, std.testing.allocator);
	defer walker.deinit();

	try std.testing.expect(walker.next() != null);
	try std.testing.expect(walker.next() != null);
	try std.testing.expect(walker.next() == null);
}

test "function block_two two" {
	const data: [:0]const u8 =
		\\fn main() void {
		\\  var x = 1;
		\\  var y = 1;
		\\}
	;
	var ast: std.zig.Ast = try .parse(std.testing.allocator, data, .zig);
	defer ast.deinit(std.testing.allocator);
	var walker = walk(ast, .root, std.testing.allocator);
	defer walker.deinit();

	try std.testing.expect(walker.next() != null);
	try std.testing.expect(walker.next() != null);
	try std.testing.expect(walker.next() != null);
	try std.testing.expect(walker.next() == null);
}

test "function block" {
	const data: [:0]const u8 =
		\\fn main() void {
		\\  var x = 1;
		\\  var y = 1;
		\\  var z = 1;
		\\}
	;
	var ast: std.zig.Ast = try .parse(std.testing.allocator, data, .zig);
	defer ast.deinit(std.testing.allocator);
	var walker = walk(ast, .root, std.testing.allocator);
	defer walker.deinit();

	try std.testing.expect(walker.next() != null);
	try std.testing.expect(walker.next() != null);
	try std.testing.expect(walker.next() != null);
	try std.testing.expect(walker.next() != null);
	try std.testing.expect(walker.next() == null);
}
