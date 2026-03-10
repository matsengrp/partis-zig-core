const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── lib: shared library (.so) exposing C ABI surface ──────────────────
    const lib = b.addSharedLibrary(.{
        .name = "partis-zig-core",
        .root_source_file = b.path("src/cabi.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // ── exe: standalone test binary ───────────────────────────────────────
    const exe = b.addExecutable(.{
        .name = "partis-zig-core",
        .root_source_file = b.path("src/cabi.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // ── compare: equivalence harness binary ──────────────────────────────
    const compare = b.addExecutable(.{
        .name = "compare",
        .root_source_file = b.path("src/equivalence/compare.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(compare);

    // ── test: unit test runner ────────────────────────────────────────────
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/cabi.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
