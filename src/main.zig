const std = @import("std");
const Io = std.Io;

const rules = @import("rules/_list.zig");

var io: Io = undefined;
var allocator: std.mem.Allocator = undefined;

var failed: bool = false;

pub const Context = struct {
	data: [:0]const u8,
	ast: ?std.zig.Ast,
	filePath: []const u8,

	fn init(data: [:0]const u8, filePath: []const u8) !Context {
		var ast: ?std.zig.Ast = null;
		errdefer if (ast) |*a| a.deinit(allocator);
		if (std.mem.endsWith(u8, filePath, ".zig")) {
			ast = try std.zig.Ast.parse(allocator, data, .zig);
		} else if (std.mem.endsWith(u8, filePath, ".zon")) {
			ast = try std.zig.Ast.parse(allocator, data, .zon);
		}
		return .{
			.data = data,
			.ast = ast,
			.filePath = filePath,
		};
	}

	fn initFromFile(dir: std.Io.Dir, filePath: []const u8) !Context {
		const data = try dir.readFileAllocOptions(io, filePath, allocator, .unlimited, .@"1", 0);
		errdefer allocator.free(data);
		return .init(data, filePath);
	}

	fn initFromStdin(filePath: []const u8) !Context {
		const stdin = std.Io.File.stdin();
		var reader = stdin.reader(io, &.{});

		const data = try reader.interface.allocRemainingAlignedSentinel(allocator, .unlimited, .@"1", 0);
		errdefer allocator.free(data);
		return .init(data, filePath);
	}

	fn deinit(self: *Context) void {
		allocator.free(self.data);
		if (self.ast) |*ast| ast.deinit(allocator);
	}

	fn getLineData(data: []const u8, charIndex: usize) struct { start: usize, end: usize, number: usize } {
		var lineStart: usize = 0;
		var lineNumber: usize = 1;
		var lineEnd: usize = data.len;
		for (data[0..charIndex], 0..) |c, i| {
			if (c == '\n') {
				lineStart = i + 1;
				lineNumber += 1;
			}
		}
		for (data[charIndex..], charIndex..) |c, i| {
			if (c == '\n') {
				lineEnd = i;
				break;
			}
		}
		return .{.start = lineStart, .end = lineEnd, .number = lineNumber};
	}

	pub fn printError(self: Context, msg: []const u8, charIndex: usize) void {
		const line = getLineData(self.data, charIndex);

		var startLineChars: std.ArrayList(u8) = .empty;
		defer startLineChars.deinit(allocator);
		for (self.data[line.start..charIndex]) |c| {
			if (c == '\t') {
				startLineChars.append(allocator, '\t') catch {};
			} else {
				startLineChars.append(allocator, ' ') catch {};
			}
		}

		failed = true;

		std.log.err("{s}:{}:{}: {s}\n{s}\n{s}^", .{self.filePath, line.number, charIndex - line.start + 1, msg, self.data[line.start..line.end], startLineChars.items});
	}

	pub fn printInfo(self: Context, msg: []const u8, charIndex: usize) void {
		const line = getLineData(self.data, charIndex);

		var startLineChars: std.ArrayList(u8) = .empty;
		defer startLineChars.deinit(allocator);
		for (self.data[line.start..charIndex]) |c| {
			if (c == '\t') {
				startLineChars.append(allocator, '\t') catch {};
			} else {
				startLineChars.append(allocator, ' ') catch {};
			}
		}

		std.log.info("{s}:{}:{}: {s}\n{s}\n{s}^", .{self.filePath, line.number, charIndex - line.start + 1, msg, self.data[line.start..line.end], startLineChars.items});
	}
};

fn checkStdin(filePath: []const u8) !void {
	var ctx: Context = try .initFromStdin(filePath);
	defer ctx.deinit();

	inline for (comptime std.meta.declarations(rules)) |rule| {
		@field(rules, rule.name).check(ctx);
	}
}

fn checkFile(dir: std.Io.Dir, filePath: []const u8) !void {
	var ctx: Context = try .initFromFile(dir, filePath);
	defer ctx.deinit();

	inline for (comptime std.meta.declarations(rules)) |rule| {
		@field(rules, rule.name).check(ctx);
	}
}

fn checkDirectory(dir: std.Io.Dir) !void {
	var walker = try dir.walk(allocator);
	defer walker.deinit();
	while (try walker.next(io)) |child| {
		if (std.mem.endsWith(u8, child.basename, ".zon") and !std.mem.endsWith(u8, child.basename, ".zig.zon")) {
			std.log.err("File name should end with .zig.zon so it gets syntax highlighting on github.", .{});
			failed = true;
		}
		if (child.kind == .file and (std.mem.endsWith(u8, child.basename, ".vert") or std.mem.endsWith(u8, child.basename, ".frag") or std.mem.endsWith(u8, child.basename, ".comp") or (std.mem.endsWith(u8, child.basename, ".zig") and !std.mem.eql(u8, child.basename, "fmt.zig")))) {
			try checkFile(dir, child.path);
		}
	}
}

pub fn main(init: std.process.Init) !void {
	allocator = init.gpa;
	io = init.io;

	const arena: std.mem.Allocator = init.arena.allocator();
	const args = try init.minimal.args.toSlice(arena);

	if (args.len <= 1) {
		std.log.err("Missing arguments, expected list of directories, found nothing.", .{});
		std.process.exit(1);
	}

	var stdin = false;

	for (args[1..]) |arg| {
		if (std.mem.eql(u8, arg, "--stdin")) {
			stdin = true;
			continue;
		}
		if (stdin) {
			try checkStdin(arg);
			return;
		}
		const stat = try std.Io.Dir.cwd().statFile(io, arg, .{.follow_symlinks = true});
		if (stat.kind == .directory) {
			var dir = try std.Io.Dir.cwd().openDir(io, arg, .{.iterate = true});
			defer dir.close(io);
			try checkDirectory(dir);
		} else {
			try checkFile(std.Io.Dir.cwd(), arg);
		}
	}

	if (failed) std.process.exit(1);
}
