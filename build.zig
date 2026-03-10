const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── cabi module: shared library exposing C ABI surface ────────────────
    const cabi_mod = b.createModule(.{
        .root_source_file = b.path("src/cabi.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "partis-zig-core",
        .root_module = cabi_mod,
        .linkage = .dynamic,
    });
    b.installArtifact(lib);

    // ── partis-zig-core executable: bcrham-compatible CLI ────────────────
    // Accepts the same arguments as bcrham so the equivalence harness can
    // drive both side-by-side and compare checkpoint streams.
    const exe = b.addExecutable(.{
        .name = "partis-zig-core",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    // ── compare: equivalence harness binary ──────────────────────────────
    const compare = b.addExecutable(.{
        .name = "compare",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/equivalence/compare.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(compare);

    // ── test: unit test runner ────────────────────────────────────────────
    const unit_tests = b.addTest(.{
        .root_module = cabi_mod,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
