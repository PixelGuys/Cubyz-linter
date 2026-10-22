const std = @import("std");
const Io = std.Io;

pub const rules = @import("rules/_list.zig");

var io: Io = undefined;
pub var allocator: std.mem.Allocator = undefined;

var failed: bool = false;

const usage =
	\\Usage:
	\\  Cubyz-linter [OUTPUT] [FILE|DIRECTORY]...        lint the files provided / files in the directories provided.
	\\  Cubyz-linter [OUTPUT] --stdin-filename=FILENAME  lint the content provided via stdin, the filename is needed to know if its a zig / zon file.
	\\  Cubyz-linter -h, --help                          print this help list
	\\OUTPUT:
	\\ Specifies how each error is printed to stdrr.
	\\          when not specified, just uses a human readable format.
	\\  --json  prints at the end of linting every error in json format
	\\  --zon   prints at the end of linting every error in zon format
;

const LineData = struct {
	start: usize,
	end: usize,
	number: usize,
};

pub const ErrorCharIndex = struct {
	start: usize,
	end: usize,

	pub fn fromSpan(span: std.zig.Ast.Span) ErrorCharIndex {
		return .{
			.start = span.start,
			.end = span.end,
		};
	}

	pub fn singleChar(charIndex: usize) ErrorCharIndex {
		return .{
			.start = charIndex,
			.end = charIndex,
		};
	}

	pub fn charWithlength(charIndex: usize, len: usize) ErrorCharIndex {
		return .{
			.start = charIndex,
			.end = charIndex + len,
		};
	}
};

/// Just logs every error / info
const Print = struct {
	counter: usize = 0,

	fn generateMessage(data: [:0]const u8, line: LineData, loc: ErrorCharIndex) []const u8 {
		var startLineChars: std.ArrayList(u8) = .empty;
		defer startLineChars.deinit(allocator);
		for (data[line.start..loc.start]) |c| {
			if (c == '\t') {
				startLineChars.append(allocator, '\t') catch {};
			} else {
				startLineChars.append(allocator, ' ') catch {};
			}
		}
		startLineChars.append(allocator, '^') catch {};
		if (loc.start + 1 < data.len and loc.start < loc.end) {
			for (data[loc.start .. loc.end - 1]) |c| {
				if (c == '\t') { // this is a wierd case...
					startLineChars.append(allocator, '\t') catch {};
				} else {
					startLineChars.append(allocator, '~') catch {};
				}
			}
		}
		return startLineChars.toOwnedSlice(allocator) catch @panic("OOM");
	}

	pub fn addError(_: *Print, ctx: Context, msg: []const u8, line: LineData, loc: ErrorCharIndex) void {
		const output = generateMessage(ctx.data, line, loc);
		defer allocator.free(output);
		failed = true;

		std.log.err("{s}:{}:{}-{}: {s}\n{s}\n{s}", .{ctx.filePath, line.number, loc.start - line.start + 1, loc.end - line.start + 1, msg, ctx.data[line.start..line.end], output});
	}

	pub fn addInfo(_: *Print, ctx: Context, msg: []const u8, line: LineData, loc: ErrorCharIndex) void {
		const output = generateMessage(ctx.data, line, loc);
		defer allocator.free(output);

		std.log.info("{s}:{}:{}-{}: {s}\n{s}\n{s}", .{ctx.filePath, line.number, loc.start - line.start + 1, loc.end - line.start + 1, msg, ctx.data[line.start..line.end], output});
	}

	pub fn format(_: *const Print, _: *std.Io.Writer) std.Io.Writer.Error!void {}
};

const LintInfo = struct {
	startLine: usize,
	endLine: usize,
	columnStart: usize,
	columnEnd: usize,
	filePath: []const u8,
	msg: []const u8,
	severity: enum { err, info },
};

/// saves every error/info into a struct which at then end gets stringified into either zon or json
const Notation = struct {
	lints: std.ArrayList(LintInfo) = .empty,
	typ: enum {
		zon,
		json,
	},

	pub fn deinit(self: *Notation) void {
		self.lints.deinit(allocator);
	}

	pub fn add(self: *Notation, info: LintInfo) void {
		self.lints.append(allocator, info) catch @panic("OOM");
	}

	pub fn format(self: *const Notation, writer: *std.Io.Writer) std.Io.Writer.Error!void {
		try switch (self.typ) {
			.zon => std.zon.stringify.serialize(self.lints.items, .{}, writer),
			.json => std.json.Stringify.value(self.lints.items, .{}, writer),
		};
	}
};

const Output = union(enum) {
	print: Print,
	notation: Notation,

	pub fn deinit(self: *Output) void {
		switch (self.*) {
			.print => {},
			.notation => self.notation.deinit(),
		}
	}

	pub fn format(self: *const Output) void {
		switch (self.*) {
			.print => {},
			.notation => |notation| {
				std.log.err("{f}", .{notation});
			},
		}
	}

	pub fn parseOutoutOrNull(arg: []const u8) ?Output {
		if (std.mem.eql(u8, arg, "--json")) {
			return .{.notation = .{.typ = .json}};
		}
		if (std.mem.eql(u8, arg, "--zon")) {
			return .{.notation = .{.typ = .zon}};
		}
		return null;
	}

	pub fn parseOutout(arg: []const u8) Output {
		if (parseOutoutOrNull(arg)) |output| return output;
		return .{.print = .{}};
	}
};

pub const Context = struct { // MARK: Context
	data: [:0]const u8,
	ast: ?std.zig.Ast,
	filePath: []const u8,
	output: *Output,

	fn init(data: [:0]const u8, filePath: []const u8, output: *Output) !Context {
		var ast: ?std.zig.Ast = null;
		errdefer if (ast) |*a| a.deinit(allocator);
		if (std.mem.endsWith(u8, filePath, ".zig")) {
			ast = try std.zig.Ast.parse(allocator, data, .{.mode = .zig});
		} else if (std.mem.endsWith(u8, filePath, ".zon")) {
			ast = try std.zig.Ast.parse(allocator, data, .{.mode = .zon});
		}
		return .{
			.data = data,
			.ast = ast,
			.filePath = filePath,
			.output = output,
		};
	}

	fn initFromFile(dir: std.Io.Dir, filePath: []const u8, output: *Output) !Context {
		const data = try dir.readFileAllocOptions(io, filePath, allocator, .unlimited, .@"1", 0);
		errdefer allocator.free(data);
		return try .init(data, filePath, output);
	}

	fn initFromStdin(fileName: []const u8, output: *Output) !Context {
		const stdin: std.Io.File = .stdin();
		var reader = stdin.reader(io, &.{});

		const data = try reader.interface.allocRemainingAlignedSentinel(allocator, .unlimited, .@"1", 0);
		errdefer allocator.free(data);
		return try .init(data, fileName, output);
	}

	fn deinit(self: *Context) void {
		allocator.free(self.data);
		if (self.ast) |*ast| ast.deinit(allocator);
	}

	fn getLineData(data: []const u8, charIndex: usize) LineData {
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

	pub fn printError(self: Context, msg: []const u8, loc: ErrorCharIndex) void {
		const line = getLineData(self.data, loc.start);
		const endLine = getLineData(self.data, loc.end);

		switch (self.output.*) {
			.print => {
				self.output.print.addError(self, msg, line, .{
					.start = loc.start,
					.end = if (line.number != endLine.number) line.end else loc.end, // print currently doens't support multiline messages
				});
			},
			.notation => {
				self.output.notation.add(.{
					.filePath = self.filePath,
					.startLine = line.number,
					.endLine = endLine.number,
					.columnStart = loc.start - line.start + 1,
					.columnEnd = loc.end - endLine.start + 1,
					.msg = msg,
					.severity = .err,
				});
			},
		}
	}

	pub fn printInfo(self: Context, msg: []const u8, loc: ErrorCharIndex) void {
		const line = getLineData(self.data, loc.start);
		const endLine = getLineData(self.data, loc.end);

		switch (self.output.*) {
			.print => {
				self.output.print.addInfo(self, msg, line, .{
					.start = loc.start,
					.end = if (line.number != endLine.number) line.end else loc.end, // print currently doens't support multiline messages
				});
			},
			.notation => {
				self.output.notation.add(.{
					.filePath = self.filePath,
					.startLine = line.number,
					.endLine = endLine.number,
					.columnStart = loc.start - line.start + 1,
					.columnEnd = loc.end - endLine.start + 1,
					.msg = msg,
					.severity = .info,
				});
			},
		}
	}
};

fn check(ctx: Context) void {
	inline for (comptime std.meta.declarations(rules)) |rule| {
		@field(rules, rule).check(ctx);
	}
}

fn checkStdin(fileName: []const u8, output: *Output) !void {
	var ctx: Context = try .initFromStdin(fileName, output);
	defer ctx.deinit();
	check(ctx);
}

fn checkFile(dir: std.Io.Dir, filePath: []const u8, output: *Output) !void {
	var ctx: Context = try .initFromFile(dir, filePath, output);
	defer ctx.deinit();
	check(ctx);
}

fn checkDirectory(dir: std.Io.Dir, output: *Output) !void {
	var walker = try dir.walk(allocator);
	defer walker.deinit();
	while (try walker.next(io)) |child| {
		if (std.mem.endsWith(u8, child.basename, ".zon") and !std.mem.endsWith(u8, child.basename, ".zig.zon")) {
			std.log.err("File name should end with .zig.zon so it gets syntax highlighting on github.", .{});
			failed = true;
		}
		if (child.kind == .file and (std.mem.endsWith(u8, child.basename, ".vert") or std.mem.endsWith(u8, child.basename, ".frag") or std.mem.endsWith(u8, child.basename, ".comp") or (std.mem.endsWith(u8, child.basename, ".zig") and !std.mem.eql(u8, child.basename, "fmt.zig")))) {
			try checkFile(dir, child.path, output);
		}
	}
}

pub fn main(init: std.process.Init) !void {
	allocator = init.gpa;
	io = init.io;

	const arena: std.mem.Allocator = init.arena.allocator();
	const args = try init.minimal.args.toSlice(arena);

	defer {
		if (failed) std.process.exit(1);
	}

	if (args.len <= 1) {
		std.log.err("Missing arguments.\n" ++ usage, .{});
		std.process.exit(1);
	}

	if (std.mem.eql(u8, args[1], "-h") or std.mem.eql(u8, args[1], "--help")) {
		var stdout = std.Io.File.stdout().writer(init.io, &.{});
		try stdout.interface.print(usage, .{});
		return;
	}

	var output: Output = .parseOutout(args[1]);
	defer {
		output.format();
		output.deinit();
	}
	const argIndex: usize = if (output == .print) 1 else 2;

	const fileNameOption = "--stdin-filename=";
	if (argIndex < args.len and std.mem.startsWith(u8, args[argIndex], fileNameOption)) {
		if (args[1].len == fileNameOption.len) {
			std.log.err("No filename given to --stdin-filename", .{});
			std.process.exit(1);
		}

		checkStdin(args[1][fileNameOption.len..], &output) catch |err| {
			std.log.err("Unable to read from stdin: {t}", .{err});
			std.process.exit(1);
		};
		return;
	}

	for (args[argIndex..]) |arg| {
		const stat = std.Io.Dir.cwd().statFile(io, arg, .{.follow_symlinks = true}) catch |err| {
			std.log.err("Error while trying to read metadata of file '{s}'. 'Error: {t}", .{arg, err});
			return err;
		};
		if (stat.kind == .directory) {
			var dir = try std.Io.Dir.cwd().openDir(io, arg, .{.iterate = true});
			defer dir.close(io);
			try checkDirectory(dir, &output);
		} else {
			try checkFile(std.Io.Dir.cwd(), arg, &output);
		}
	}
}
