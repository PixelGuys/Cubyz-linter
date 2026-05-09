const std = @import("std");
const Io = std.Io;

var io: Io = undefined;
var allocator: std.mem.Allocator = undefined;

var failed: bool = false;

fn printError(msg: []const u8, filePath: []const u8, data: []const u8, charIndex: usize) void {
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

	var startLineChars: std.ArrayList(u8) = .empty;
	defer startLineChars.deinit(allocator);
	for (data[lineStart..charIndex]) |c| {
		if (c == '\t') {
			startLineChars.append(allocator, '\t') catch {};
		} else {
			startLineChars.append(allocator, ' ') catch {};
		}
	}

	failed = true;

	std.log.err("Found formatting error in line {} of file {s}: {s}\n{s}\n{s}^", .{lineNumber, filePath, msg, data[lineStart..lineEnd], startLineChars.items});
}
fn checkImports(data: []const u8, filePath: []const u8) void {
	var split = std.mem.splitScalar(u8, data, '\n');
	var finishedImports: bool = false;

	var buf: [65536]u8 = undefined;
	while (split.next()) |line| {
		const lineZ = std.fmt.bufPrintZ(&buf, "{s}", .{line}) catch {
			printError("Line too long, seriously what are you doing?", filePath, data, line.ptr - data.ptr);
			continue;
		};
		var tokenizer = std.zig.Tokenizer.init(lineZ);
		var token = tokenizer.next();
		if (token.tag == .eof) continue;
		if (token.tag == .doc_comment) continue;
		if (token.tag == .container_doc_comment) continue;
		const isImport: bool = blk: {
			if (line[0] == '\t') break :blk false;

			if (token.tag == .keyword_pub) token = tokenizer.next();
			if (token.tag != .keyword_const) break :blk false;
			token = tokenizer.next();
			if (token.tag != .identifier) break :blk false;
			var aliasName = tokenizer.buffer[token.loc.start..token.loc.end];
			token = tokenizer.next();
			if (token.tag != .equal) break :blk false;

			token = tokenizer.next();
			switch (token.tag) {
				.builtin => { // @import
					const importKeyword = tokenizer.buffer[token.loc.start..token.loc.end];
					if (!std.mem.eql(u8, importKeyword, "@import")) break :blk false;
					token = tokenizer.next();
					if (token.tag != .l_paren) break :blk false;
					token = tokenizer.next();
					if (token.tag != .string_literal) break :blk false;
					const importNameToken = token;
					token = tokenizer.next();
					if (token.tag != .r_paren) break :blk false;
					token = tokenizer.next();
					if (token.tag != .semicolon) break :blk false;

					var importName = tokenizer.buffer[importNameToken.loc.start..importNameToken.loc.end];
					importName = std.mem.trim(u8, importName, "\"");
					if (std.mem.endsWith(u8, importName, ".zon")) importName.len -= 4;
					if (std.mem.endsWith(u8, importName, ".zig")) importName.len -= 4;
					if (std.mem.findLast(u8, importName, "/")) |i| importName = importName[i + 1 ..];
					if (aliasName[0] == '@') aliasName = aliasName[2 .. aliasName.len - 1];
					if (std.mem.findLast(u8, aliasName, "/")) |i| aliasName = aliasName[i + 1 ..];
					if (!std.mem.eql(u8, aliasName, importName)) {
						std.log.err("{s} {s}", .{aliasName, importName});
						printError("Encountered import with mismatched name", filePath, data, line.ptr - data.ptr + importNameToken.loc.start);
					}
					break :blk true;
				},
				.identifier => { // alias
					var importNameToken = token;
					while (true) {
						token = tokenizer.next();
						if (token.tag == .semicolon) break;
						if (token.tag != .period) break :blk false;
						token = tokenizer.next();
						if (token.tag != .identifier) break :blk false;
						importNameToken = token;
					}
					if (!std.mem.eql(u8, aliasName, tokenizer.buffer[importNameToken.loc.start..importNameToken.loc.end])) {
						if (finishedImports) break :blk false;
						printError("Encountered alias with mismatched name", filePath, data, line.ptr - data.ptr + importNameToken.loc.start);
					}
					break :blk true;
				},
				else => break :blk false,
			}
		};
		if (isImport) {
			if (finishedImports) {
				printError("Encountered import/alias after import section", filePath, data, line.ptr - data.ptr);
			}
		} else {
			finishedImports = true;
		}
	}
}

fn checkFile(dir: std.Io.Dir, filePath: []const u8) !void {
	const data = try dir.readFileAlloc(io, filePath, allocator, .unlimited);
	defer allocator.free(data);

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
		checkImports(data, filePath);
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
