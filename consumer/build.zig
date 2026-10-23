// SPDX-License-Identifier: MIT
// See ../FORK-LICENSE.md for what that identifier covers.
//
//! Build a separate consumer through the package's public dependency module.
//! Forward linkage, runtime-provider, and SIMD options to the dependency.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(
        std.lang.LinkMode,
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
    const simd = b.option(
        []const u8,
        "simd",
        "Select the SIMD configuration. `c` is the only accepted value: this " ++
            "package builds the portable C configuration, with WITH_SIMD off and " ++
            "nothing under src/simd/ compiled. See ../build.zig for why, per target " ++
            "and per architecture family.",
    ) orelse "c";

    const allow_darling = b.option(bool, "consumer-darling", "Runner state for the outer consumer step.") orelse false;
    const allow_qemu = b.option(bool, "consumer-qemu", "Runner state for the outer consumer step.") orelse false;
    const allow_wasmtime = b.option(bool, "consumer-wasmtime", "Runner state for the outer consumer step.") orelse false;
    const allow_wine = b.option(bool, "consumer-wine", "Runner state for the outer consumer step.") orelse false;
    const libc_runtimes = b.option([]const u8, "consumer-libc-runtimes", "Runtime files for the outer consumer step.");

    const dep = b.dependency("libjpeg-turbo", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime_loaded,
        .simd = simd,
    });

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
    run_exe.addPassthruArgs();
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);

    const consumer_step = b.step("consumer", "Run the consumer when the target can execute; otherwise install it");
    if (hostCanExecute(
        b,
        target,
        allow_darling,
        allow_qemu,
        allow_wasmtime,
        allow_wine,
        libc_runtimes,
    )) {
        consumer_step.dependOn(&run_exe.step);
    } else {
        consumer_step.dependOn(b.getInstallStep());
    }
}

fn hostCanExecute(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    allow_darling: bool,
    allow_qemu: bool,
    allow_wasmtime: bool,
    allow_wine: bool,
    libc_runtimes: ?[]const u8,
) bool {
    const candidate = &target.result;
    const host = &b.graph.host.result;
    const needs_cross_libc = candidate.os.tag == .linux;
    return switch (std.zig.system.getExternalExecutor(b.graph.io, candidate, .{
        .host_cpu_arch = host.cpu.arch,
        .host_os_tag = host.os.tag,
        .qemu_fixes_dl = needs_cross_libc and libc_runtimes != null,
        .link_mode = .dynamic,
        .link_libc = true,
    })) {
        .native, .rosetta => true,
        .qemu => allow_qemu and (!needs_cross_libc or libc_runtimes != null),
        .darling => allow_darling,
        .wasmtime => allow_wasmtime,
        .wine => allow_wine,
        .bad_dl, .bad_os_or_cpu => false,
    };
}
