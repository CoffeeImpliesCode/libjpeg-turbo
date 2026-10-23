// SPDX-License-Identifier: MIT
// See ../FORK-LICENSE.md for what that identifier covers.
//
//! Build a separate consumer through the package's public dependency module.
//! Forward linkage, runtime-provider, and SIMD options to the dependency.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Declare forwarded options so this consumer checks the dependency's settings instead of ignoring them.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Which delivery of libjpeg to check. Forwarded to the dependency; it " ++
            "decides the artifact, never anything in this package.",
    ) orelse .static;
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Check the dependency's runtime-loading dispatch instead of a linked " ++
            "one. Forwarded to the dependency. A program built this way has to " ++
            "name a provider with an explicit load() before any native call, " ++
            "which is src/main.zig's business and not this file's.",
    ) orelse false;

    // Forward SIMD selection so the dependency rejects unsupported values itself.
    const simd = b.option(
        []const u8,
        "simd",
        "Select the SIMD configuration. `c` is the only accepted value: this " ++
            "package builds the portable C configuration, with WITH_SIMD off and " ++
            "nothing under src/simd/ compiled. See ../build.zig for why, per target " ++
            "and per architecture family.",
    ) orelse "c";

    const dep = b.dependency("libjpeg-turbo", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime_loaded,
        .simd = simd,
    });

    // System integration follows the build runner's `-fsys` flags through the shared Build graph, not `-D`.
    // The dependency resolves the mode, so this consumer needs no local branch.

    // The dependency owns its libc requirement; no local `link_libc` should mask a missing declaration.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("libjpeg_turbo", dep.module("libjpeg_turbo"));

    const exe = b.addExecutable(.{
        .name = "libjpeg-turbo-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.has_side_effects = true;
    // Forward arguments for explicit provider selection; no arguments leave the linked run unchanged.
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
