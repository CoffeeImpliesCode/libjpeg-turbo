// SPDX-License-Identifier: MIT
// See ../FORK-LICENSE.md for what that identifier covers.
//
//! Build wiring for the separate `consumer/` package.
//!
//! This package exists to prove one thing: that a dependent needs only
//! `b.dependency("libjpeg-turbo", ...)` and `dep.module("libjpeg_turbo")` and
//! gets a working, correctly linked library. If the facade module stopped
//! carrying its C artifact, or the translated headers stopped matching the C
//! source, or the `libjpeg_turbo` module stopped resolving by name, this would
//! stop building or stop producing the answers its program checks - and nothing
//! inside the library would notice.
//!
//! `src/main.zig` is the API role's file. This file is only the graph that
//! builds it, and it deliberately repeats almost nothing: the library decides
//! which artifact is delivered, which three headers were generated for this
//! target, which SIMD configuration was compiled and which `libjpeg` ABI the
//! headers describe, and this package learns all of that through the dependency
//! rather than by restating it.
//!
//! `zig build run` runs it. The parent package's `zig build consumer` runs or
//! installs this package as a nested build for the selected target, linkage and
//! dispatch mode -- it installs when this host cannot execute that target -- so
//! `zig build run -Dlinkage=dynamic` really does check `libjpeg.so.62.4.0` and
//! not the default archive.
//!
//! The program needs no fixture files of its own and no working directory: the
//! four JPEG fixtures are byte literals inside `src/main.zig`, checked there
//! against the digests this repository records. A gate that had to find a file
//! first is a gate that can pass for the wrong reason.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The delivery and dispatch options are declared here rather than ignored,
    // so `zig build run -Dlinkage=dynamic` checks the shared object instead of
    // silently checking the default archive, and so the parent package's
    // `zig build consumer` can pass a configuration through to the dependency
    // instead of dropping it on the floor.
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

    // The SIMD configuration, forwarded and accepted on exactly one value.
    //
    // The dependency refuses anything but `c` with a printed reason and a
    // non-zero exit, and this package must reach the same answer rather than
    // inventing its own default that a caller cannot see. Declaring the option
    // here means `zig build run -Dsimd=nasm` in *this* directory is refused by
    // the dependency's own check rather than silently ignored, which is the same
    // boundary a dependent gets.
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

    // The system mode is deliberately *not* a `-D` option here, and that is not
    // an omission. The dependency resolves it through
    // `b.systemIntegrationOption`, which is fed by the build runner's
    // `-fsys=`/`-fno-sys=` flags and is never an entry in the `-D` map, so a
    // `b.option` declared here would have to be threaded down as a dependency
    // option to reach the same answer. It does not need to be: a dependency
    // shares its parent's `Graph` (`lib/std/Build.zig:352`) and
    // `system_library_options` is a field of it (`:116`, read at `:2731`), so
    // the flag the runner was given reaches the dependency's own
    // `systemIntegrationOption` call unchanged.
    //
    // That is what the parent package's `zig build consumer` forwards, as the
    // mode it resolved, and it is also why `zig build run -fsys=jpeg` in this
    // directory is the same check stated directly. Both spellings reach the one
    // switch; neither is a second code path. This package has no system branch
    // of its own either, so there is nothing here for the flag to select.

    // No `link_libc` here on purpose. The C requirement belongs to the library
    // module, which carries it; a dependent states its own, and this program
    // needs nothing beyond what the library already brings. Adding it here would
    // hide a library that forgot to declare it.
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
    // Forwarded so `zig build run -Druntime=true -- --provider <path>` reaches
    // `src/main.zig`, which reads exactly that and otherwise falls through to
    // `LIBJPEG_TURBO_TEST_PROVIDER`. With no arguments this is inert, so a
    // linked run is unchanged.
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}