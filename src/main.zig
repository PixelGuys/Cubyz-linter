const std = @import("std");
const Io = std.Io;

var io: Io = undefined;
var allocator: std.mem.Allocator = undefined;

var failed: bool = false;

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

fn printError(msg: []const u8, filePath: []const u8, data: []const u8, charIndex: usize) void {
	const line = getLineData(data, charIndex);

	var startLineChars: std.ArrayList(u8) = .empty;
	defer startLineChars.deinit(allocator);
	for (data[line.start..charIndex]) |c| {
		if (c == '\t') {
			startLineChars.append(allocator, '\t') catch {};
		} else {
			startLineChars.append(allocator, ' ') catch {};
		}
	}

	failed = true;

	std.log.err("{s}:{}:{}: {s}\n{s}\n{s}^", .{filePath, line.number, charIndex - line.start + 1, msg, data[line.start..line.end], startLineChars.items});
}

fn printInfo(msg: []const u8, filePath: []const u8, data: []const u8, charIndex: usize) void {
	const line = getLineData(data, charIndex);

	var startLineChars: std.ArrayList(u8) = .empty;
	defer startLineChars.deinit(allocator);
	for (data[line.start..charIndex]) |c| {
		if (c == '\t') {
			startLineChars.append(allocator, '\t') catch {};
		} else {
			startLineChars.append(allocator, ' ') catch {};
		}
	}

	failed = true;

	std.log.info("{s}:{}:{}: {s}\n{s}\n{s}^", .{filePath, line.number, charIndex - line.start + 1, msg, data[line.start..line.end], startLineChars.items});
}

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

	return std.mem.eql(u8, importName, aliasName);
}
fn checkImports(ast: *std.zig.Ast, filePath: []const u8) void {
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
					printError("@import should not have a trailing comma.", filePath, ast.source, ast.tokenStart(token));
					break :blk true;
				},
				.builtin_call_two => { // @import("x")
					const importKeyword = ast.tokenSlice(ast.nodeMainToken(rhsNode));
					if (!std.mem.eql(u8, importKeyword, "@import")) break :blk false;

					const token = ast.nodeMainToken(ast.nodeData(rhsNode).opt_node_and_opt_node[0].unwrap().?);
					var importName = ast.tokenSlice(token);
					importName = importName[1 .. importName.len - 1];

					if (!isAliasAllowed(importName, aliasName)) {
						printError("Encountered import with mismatched name", filePath, ast.source, ast.tokenStart(token));
					}
					break :blk true;
				},
				.field_access => { // alias
					const token = ast.nodeData(rhsNode).node_and_token.@"1";
					const importName = ast.tokenSlice(token);

					if (!isAliasAllowed(importName, aliasName)) {
						if (firstNonImportNode != null) break :blk false;
						printError("Encountered alias with mismatched name", filePath, ast.source, ast.tokenStart(token));
					}
					break :blk true;
				},
				else => break :blk false,
			}
		};
		if (isImport) {
			if (firstNonImportNode) |nonImportNode| {
				printError("Encountered import/alias after import section", filePath, ast.source, ast.tokenStart(ast.firstToken(node)));
				printInfo("determined end of import section", filePath, ast.source, ast.tokenStart(ast.firstToken(nonImportNode)));
			}
		} else {
			if (firstNonImportNode == null) {
				firstNonImportNode = node;
			}
		}
	}
}

fn checkFile(dir: std.Io.Dir, filePath: []const u8) !void {
	const data = try dir.readFileAllocOptions(io, filePath, allocator, .unlimited, .@"1", 0);
	defer allocator.free(data);
	var ast = try std.zig.Ast.parse(allocator, data, .zig);
	defer ast.deinit(allocator);

	var lineStart: bool = true;

	for (data, 0..) |c, i| {
		switch (c) {
			'\n' => {
				lineStart = true;
				if (i != 0 and (data[i - 1] == ' ' or data[i - 1] == '\t')) {
					printError("Line contains trailing whitespaces. Please remove them.", filePath, data, i - 1);
				}
			},
			'\r' => {
				printError("Incorrect line ending \\r. Please configure your editor to use LF instead CRLF.", filePath, data, i);
			},
			' ' => {
				if (lineStart) {
					printError("Incorrect indentation. Please use tabs instead of spaces.", filePath, data, i);
				}
			},
			'/' => {
				if (data[i + 1] == '/' and data[i + 2] != '/' and data[i + 2] != '!' and data[i + 2] != ' ' and data[i + 2] != '\n' and (i == 0 or (data[i - 1] != ':' and data[i - 1] != '"'))) {
					printError("Comments should include a space before text, ex: // whatever", filePath, data, i + 2);
				}
				lineStart = false;
			},
			'\t' => {},
			else => {
				lineStart = false;
			},
		}
	}
	if (std.mem.containsAtLeast(u8, data, 1, "anyerror" ++ "!")) {
		if (!std.mem.eql(u8, filePath, "network/protocols.zig")) {
			std.log.err("Found anyerror" ++ "! in file {s}. Please avoid the use of anyerror" ++ "! instead please define an error set.", .{filePath});
		}
	}
	if (data.len != 0 and data[data.len - 1] != '\n' or (data.len > 2 and data[data.len - 2] == '\n')) {
		printError("File should end with a single empty line", filePath, data, data.len - 1);
	}
	if (std.mem.endsWith(u8, filePath, ".zig")) {
		checkImports(&ast, filePath);
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

	for (args[1..]) |arg| {
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
