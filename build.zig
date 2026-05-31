const std = @import("std");

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	const exe = b.addExecutable(.{
		.name = "Cubyz-linter",
		.root_module = b.createModule(.{
			.root_source_file = b.path("src/main.zig"),
			.target = target,
			.optimize = optimize,
			.imports = &.{},
		}),
	});

	exe.root_module.addImport("main", exe.root_module);

	exe.root_module.addImport("zls", b.dependency("zls", .{
		.target = target,
		.optimize = optimize,
	}).module("zls"));

	b.installArtifact(exe);

	const run_step = b.step("run", "Run the app");

	const run_cmd = b.addRunArtifact(exe);
	run_step.dependOn(&run_cmd.step);

	run_cmd.step.dependOn(b.getInstallStep());

	if (b.args) |args| {
		run_cmd.addArgs(args);
	}

	const exe_tests = b.addTest(.{
		.root_module = exe.root_module,
	});

	const run_exe_tests = b.addRunArtifact(exe_tests);

	const test_step = b.step("test", "Run tests");
	test_step.dependOn(&run_exe_tests.step);
}
