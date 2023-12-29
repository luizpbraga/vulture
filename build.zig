const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // THIS MODULE
    const vulture_mod = b.addModule("Vulture", .{
        .source_file = .{ .path = "src/Vulture.zig" },
    });

    // EXECUTABLE
    const exe = b.addExecutable(.{
        .name = "vulture_exe",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("Vulture", vulture_mod);
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // TESTS
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    tests.addModule("Vulture", vulture_mod);
    const run_lib_unit_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
