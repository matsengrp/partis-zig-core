const std = @import("std");

/// Path to the ig-sw C sources inside the partis repository.
/// Adjust if partis is checked out elsewhere (or override via workspace.json).
const igsw_src = "/fh/fast/matsen_e/shared/partis-zig/partis/packages/ig-sw/src/ig_align";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── cabi module: shared library exposing C ABI surface ────────────────
    const cabi_mod = b.createModule(.{
        .root_source_file = b.path("src/cabi.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Allow @cImport to find ig_align.h
    cabi_mod.addIncludePath(.{ .cwd_relative = igsw_src });

    const lib = b.addLibrary(.{
        .name = "partis-zig-core",
        .root_module = cabi_mod,
        .linkage = .dynamic,
    });
    // ── ig-sw C sources ───────────────────────────────────────────────────
    lib.addCSourceFile(.{
        .file = .{ .cwd_relative = igsw_src ++ "/ig_align.c" },
        .flags = &.{ "-std=gnu99", "-O2" },
    });
    lib.addCSourceFile(.{
        .file = .{ .cwd_relative = igsw_src ++ "/ksw.c" },
        .flags = &.{ "-std=gnu99", "-O2" },
    });
    lib.addCSourceFile(.{
        .file = .{ .cwd_relative = igsw_src ++ "/kstring.c" },
        .flags = &.{ "-std=gnu99", "-O2" },
    });
    lib.addIncludePath(.{ .cwd_relative = igsw_src });
    lib.linkSystemLibrary("z");
    lib.linkLibC();
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
