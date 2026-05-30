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
		switch (self.ast.nodeTag(node)) {
			.fn_decl => {
				const body = self.ast.nodeData(node).node_and_node[1];
				const item = self.allocator.create(StackItem) catch @panic("OOM");
				item.* = .{
					.nodes = self.ast.extraDataSlice(self.ast.nodeData(body).extra_range, std.zig.Ast.Node.Index),
				};
				self.stack.append(
					self.allocator,
					item,
				) catch @panic("OOM");
			},
			else => {},
		}
	}

	pub fn deinit(self: *SelectiveWalker) void {
		for (self.stack.items) |item| {
			self.allocator.destroy(item);
		}
		self.stack.deinit(self.allocator);
	}

	pub fn leave(self: *SelectiveWalker) void {
		const item = self.stack.pop().?;
		self.allocator.destroy(item);
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
	var stack: std.ArrayList(*SelectiveWalker.StackItem) = .empty;

	const item = allocator.create(SelectiveWalker.StackItem) catch @panic("OOM");
	item.* = .{
		.nodes = ast.extraDataSlice(ast.nodeData(index).extra_range, std.zig.Ast.Node.Index),
	};

	stack.append(allocator, item) catch @panic("OOM");

	return .{
		.ast = ast,
		.stack = stack,
		.allocator = allocator,
	};
}
