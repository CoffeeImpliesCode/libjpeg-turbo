// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers, and NOTICE.md for the
// per-file inventory of the upstream material this package ships.

//! Builds the 98 upstream C units as a libjpeg-turbo library.
//! SIMD is disabled: x86 requires NASM; other targets require CMake-generated probes.
//! Generated configuration headers use the target's size, not the host generator's.

const std = @import("std");

const manifest = @import("build.zig.zon");

/// Reject invalid manifest versions at configure time.
const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon: .version is not a semantic version");

/// Use one loader-core module so `LoadSource` and `LoadError` retain identical types.
const graph = @import("runtime/graph.zig");

const package_name = "libjpeg-turbo";

const lib_name = "libjpeg_turbo";

const artifact_name = "jpeg";

/// Upstream source version; checked against the manifest.
const upstream_version: std.SemanticVersion = .{ .major = 3, .minor = 2, .patch = 0 };

/// libjpeg v6 API level; JPEG 7/8 extensions are disabled.
const jpeg_lib_version = 62;

/// CMake's release-number formula (`src/CMakeLists.txt:34-39`).
const libjpeg_turbo_version_number = 3002000;

/// Copyright-year input to `jversion.h` (`src/CMakeLists.txt:18`).
const copyright_year = "1991-2026";

/// CMake project name (`src/CMakeLists.txt:16`).
const cmake_project_name = "libjpeg-turbo";

/// Fixed instead of CMake's non-reproducible timestamp (`src/CMakeLists.txt:91`).
const build_stamp = "zig-3.2.0";

/// Upstream ABI version: file 62.4.0, SONAME 62 (`src/CMakeLists.txt:373-397`).
const abi_version: std.SemanticVersion = .{ .major = 62, .minor = 4, .patch = 0 };

const source_dir = "src/src";

const facade_source = "zig/root.zig";

/// Translation wrapper for public headers and required system headers.
const translate_header = "zig/translate.h";

const generator_source = "tools/jconfig.zig";

const test_source = "tests.zig";

const example_source = "smoke.zig";

/// The 98 upstream `JPEG_SOURCES` units (`src/CMakeLists.txt:653-690`).
/// Keep the full base list; the optional source appends are disabled.
const core_sources = [_][]const u8{
    "src/src/jcapimin.c",
    "src/src/wrapper/jcapistd-8.c",    "src/src/wrapper/jcapistd-12.c",  "src/src/wrapper/jcapistd-16.c",
    "src/src/wrapper/jccoefct-8.c",    "src/src/wrapper/jccoefct-12.c",
    "src/src/wrapper/jccolor-8.c",     "src/src/wrapper/jccolor-12.c",   "src/src/wrapper/jccolor-16.c",
    "src/src/wrapper/jcdctmgr-8.c",    "src/src/wrapper/jcdctmgr-12.c",
    "src/src/wrapper/jcdiffct-8.c",    "src/src/wrapper/jcdiffct-12.c",  "src/src/wrapper/jcdiffct-16.c",
    "src/src/jchuff.c",                "src/src/jcicc.c",                "src/src/jcinit.c",
    "src/src/jclhuff.c",
    "src/src/wrapper/jclossls-8.c",    "src/src/wrapper/jclossls-12.c",  "src/src/wrapper/jclossls-16.c",
    "src/src/wrapper/jcmainct-8.c",    "src/src/wrapper/jcmainct-12.c",  "src/src/wrapper/jcmainct-16.c",
    "src/src/jcmarker.c",              "src/src/jcmaster.c",             "src/src/jcomapi.c",
    "src/src/jcparam.c",               "src/src/jcphuff.c",
    "src/src/wrapper/jcprepct-8.c",    "src/src/wrapper/jcprepct-12.c",  "src/src/wrapper/jcprepct-16.c",
    "src/src/wrapper/jcsample-8.c",    "src/src/wrapper/jcsample-12.c",  "src/src/wrapper/jcsample-16.c",
    "src/src/jctrans.c",               "src/src/jdapimin.c",
    "src/src/wrapper/jdapistd-8.c",    "src/src/wrapper/jdapistd-12.c",  "src/src/wrapper/jdapistd-16.c",
    "src/src/jdatadst.c",              "src/src/jdatasrc.c",
    "src/src/wrapper/jdcoefct-8.c",    "src/src/wrapper/jdcoefct-12.c",
    "src/src/wrapper/jdcolor-8.c",     "src/src/wrapper/jdcolor-12.c",   "src/src/wrapper/jdcolor-16.c",
    "src/src/wrapper/jddctmgr-8.c",    "src/src/wrapper/jddctmgr-12.c",
    "src/src/wrapper/jddiffct-8.c",    "src/src/wrapper/jddiffct-12.c",  "src/src/wrapper/jddiffct-16.c",
    "src/src/jdhuff.c",                "src/src/jdicc.c",                "src/src/jdinput.c",
    "src/src/jdlhuff.c",
    "src/src/wrapper/jdlossls-8.c",    "src/src/wrapper/jdlossls-12.c",  "src/src/wrapper/jdlossls-16.c",
    "src/src/wrapper/jdmainct-8.c",    "src/src/wrapper/jdmainct-12.c",  "src/src/wrapper/jdmainct-16.c",
    "src/src/jdmarker.c",              "src/src/jdmaster.c",
    "src/src/wrapper/jdmerge-8.c",     "src/src/wrapper/jdmerge-12.c",
    "src/src/jdphuff.c",
    "src/src/wrapper/jdpostct-8.c",    "src/src/wrapper/jdpostct-12.c",  "src/src/wrapper/jdpostct-16.c",
    "src/src/wrapper/jdsample-8.c",    "src/src/wrapper/jdsample-12.c",  "src/src/wrapper/jdsample-16.c",
    "src/src/jdtrans.c",               "src/src/jerror.c",               "src/src/jfdctflt.c",
    "src/src/wrapper/jfdctfst-8.c",    "src/src/wrapper/jfdctfst-12.c",
    "src/src/wrapper/jfdctint-8.c",    "src/src/wrapper/jfdctint-12.c",
    "src/src/wrapper/jidctflt-8.c",    "src/src/wrapper/jidctflt-12.c",
    "src/src/wrapper/jidctfst-8.c",    "src/src/wrapper/jidctfst-12.c",
    "src/src/wrapper/jidctint-8.c",    "src/src/wrapper/jidctint-12.c",
    "src/src/wrapper/jidctred-8.c",    "src/src/wrapper/jidctred-12.c",
    "src/src/jmemmgr.c",               "src/src/jmemnobs.c",             "src/src/jpeg_nbits.c",
    "src/src/wrapper/jquant1-8.c",     "src/src/wrapper/jquant1-12.c",
    "src/src/wrapper/jquant2-8.c",     "src/src/wrapper/jquant2-12.c",
    "src/src/wrapper/jutils-8.c",      "src/src/wrapper/jutils-12.c",    "src/src/wrapper/jutils-16.c",
};

/// Install order matters: generated `jconfig.h` precedes `jpeglib.h`.
const public_headers = [_]struct { source: []const u8, generated: bool }{
    // Install the generated header from the build cache.
    .{ .source = "jconfig.h", .generated = true },
    .{ .source = "jerror.h", .generated = false },
    .{ .source = "jmorecfg.h", .generated = false },
    .{ .source = "jpeglib.h", .generated = false },
};

/// Install upstream licence texts under their original names.
const licence_records = [_]struct { source: []const u8, basename: []const u8 }{
    .{ .source = "src/README.ijg", .basename = "README.ijg" },
    .{ .source = "src/LICENSE.md", .basename = "LICENSE.md" },
};

/// Targets included in the cross-compilation check.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

const refused_check_targets = [_]std.Target.Query{};

const Template = enum {
    jconfig,
    jconfigint,
    jversion,

    fn source(self: Template) []const u8 {
        return switch (self) {
            .jconfig => source_dir ++ "/jconfig.h.in",
            .jconfigint => source_dir ++ "/jconfigint.h.in",
            .jversion => source_dir ++ "/jversion.h.in",
        };
    }

    fn inFlag(self: Template) []const u8 {
        return switch (self) {
            .jconfig => "--jconfig-in",
            .jconfigint => "--jconfigint-in",
            .jversion => "--jversion-in",
        };
    }

    fn outFlag(self: Template) []const u8 {
        return switch (self) {
            .jconfig => "--jconfig-out",
            .jconfigint => "--jconfigint-out",
            .jversion => "--jversion-out",
        };
    }

    fn outputName(self: Template) []const u8 {
        return switch (self) {
            .jconfig => "jconfig.h",
            .jconfigint => "jconfigint.h",
            .jversion => "jversion.h",
        };
    }
};

/// The generator requires all three templates in this order.
const templates = [_]Template{ .jconfig, .jversion, .jconfigint };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Reject system integration; this graph bundles libjpeg-turbo.
    const system_default = b.option(
        bool,
        "system",
        "Refused in this package: no system mode is implemented, and the module " ++
            "comment says why (src/jpeglib.h:41-42 includes the *generated* jconfig.h " ++
            "by bare name, so a system mode must translate the installed jconfig.h " ++
            "alongside the installed jpeglib.h from the same prefix, and bundling " ++
            "this tree's headers against an older installed libjpeg is the " ++
            "silent-ABI failure AGENTS.md rule 4 forbids). This option supplies the " ++
            "default of systemIntegrationOption(\"jpeg\"); a build runner that " ++
            "decides the mode itself (-fsys=jpeg) overrides it. Either spelling " ++
            "that selects the system stops the build before a compiler is invoked.",
    ) orelse false;

    // The system-integration flag uses the C artifact name.
    if (b.systemIntegrationOption(artifact_name, .{ .default = system_default })) {
        std.log.err(
            \\libjpeg-turbo: -fsys=jpeg selects a system mode this package does not
            \\implement, and the rule is recorded as vacuous rather than satisfied.
            \\
            \\src/jpeglib.h:41-42 includes the *generated* jconfig.h by bare name, so a
            \\system mode must translate the installed jconfig.h alongside the
            \\installed jpeglib.h and jmorecfg.h from the same prefix. Bundling this
            \\tree's headers against an older installed libjpeg is the silent ABI
            \\mismatch AGENTS.md rule 4 forbids, and no b.dependency performs the
            \\check that would catch it.
            \\
            \\Build the bundled graph instead: drop -Dsystem and do not pass -fsys=jpeg.
            \\
        , .{});
        @panic("libjpeg-turbo: refusing a system mode this package does not implement");
    }

    // Only portable C is supported; reject other SIMD values.
    const simd = b.option(
        []const u8,
        "simd",
        "Select the SIMD configuration. `c` is the only accepted value: this " ++
            "package builds the portable C configuration, with WITH_SIMD off, " ++
            "SIMD_ARCHITECTURE NONE and nothing under src/simd/ compiled. There is " ++
            "no second configuration to select. See the module comment under \"THE " ++
            "SIMD BOUNDARY\" for why, per target and per architecture family.",
    ) orelse "c";
    if (!std.mem.eql(u8, simd, "c")) {
        std.log.err(
            \\libjpeg-turbo: -Dsimd={s} is not a configuration this package builds.
            \\
            \\The only accepted value is `c`, and it is the only one this package can
            \\build, on every target:
            \\
            \\  * WITH_SIMD is not defined, nothing under src/simd/ is compiled, and
            \\    SIMD_ARCHITECTURE is NONE.
            \\  * x86 and x86-64 SIMD is NASM assembly (56 files in src/simd/i386/, 35
            \\    in src/simd/x86_64/, assembled through enable_language(ASM_NASM) at
            \\    src/simd/CMakeLists.txt:61). Zig 0.16.0's toolchain contains no NASM
            \\    and its clang does not accept NASM syntax, so those 91 files cannot be
            \\    assembled from this build graph on x86_64-linux-gnu or
            \\    x86_64-windows-gnu.
            \\  * The other families are plain C with intrinsics and would compile, but
            \\    upstream *generates* simd/arm/neon-compat.h from capability probes it
            \\    runs itself (src/simd/CMakeLists.txt:349, probes at :289-333) and
            \\    selects the source list by CPU_TYPE. Reproducing that would be
            \\    inventing configuration rather than porting it.
            \\
            \\This is upstream's own fallback: with REQUIRE_SIMD defaulting FALSE
            \\(src/CMakeLists.txt:252-255), src/simd/CMakeLists.txt:1-10 emits
            \\"Performance will suffer" and sets WITH_SIMD 0 and SIMD_ARCHITECTURE
            \\NONE, and :53-61 does the same when NASM is missing.
            \\
            \\Upstream's README states libjpeg-turbo is generally 2-6x as fast as
            \\libjpeg on such systems (src/README.md:4-10). That advantage is NOT
            \\available from this package, which makes no parity claim with the
            \\full-speed x86 configuration.
            \\
        , .{simd});
        @panic("libjpeg-turbo: -Dsimd accepts `c` and nothing else");
    }

    const linkage: std.builtin.LinkMode = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Deliver the native library as `libjpeg.a` (the default) or as a real " ++
            "shared object with upstream's own numbers, `libjpeg.so.62.4.0` and " ++
            "soname `libjpeg.so.62` (src/CMakeLists.txt:373-397 and " ++
            "src/sharedlib/CMakeLists.txt:58-59). This selects the delivery and " ++
            "never the dispatch: the same 98 C units are compiled either way.",
    ) orelse .static;

    // Linkage controls delivery; runtime controls dispatch.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve the native entry points at run time instead of linking them. " ++
            "The facade keeps the same translated headers and the same public " ++
            "types; each of the 66 functions the four public headers declare " ++
            "becomes a dispatch through one process-lifetime table that an explicit " ++
            "load(source) fills, and the module links no archive. Independent of " ++
            "-Dlinkage, which still decides which artifact this build delivers and " ++
            "installs. Default off, and a linked build is unchanged in every respect.",
    ) orelse false;

    // Keep manifest and upstream source versions in sync.
    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches `set(VERSION 3.2.0)` at " ++
            "src/CMakeLists.txt:17; see UPSTREAM.md");
    }

    // Validate target/refusal partitions before creating build graphs.
    checkMatrixPartition(b);

    if (refusalFor(target.result.os.tag) != null) refuseTarget(b, target);

    const delivered = deliveredLinkage(target, linkage);
    if (delivered != linkage) {
        std.log.warn(
            "libjpeg-turbo: -Dlinkage={s} was requested and the selected target " ++
                "cannot carry it, so this build delivers {s}. See deliveredLinkage.",
            .{ @tagName(linkage), @tagName(delivered) },
        );
    }

    const generated = addGeneratedHeaders(b, target);
    const published = addGraph(b, target, optimize, delivered, runtime_loaded, true, generated);

    b.installArtifact(published.c_lib);
    add_pkg_config(b);
    install_licence_records(b);

    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, published.module);
    const example = b.addExecutable(.{
        .name = "libjpeg-turbo-smoke",
        .root_module = example_mod,
    });
    b.getInstallStep().dependOn(&example.step);

    const run_example = b.addRunArtifact(example);
    run_example.has_side_effects = true;
    if (b.args) |args| run_example.addArgs(args);
    b.step("smoke", "Run the deterministic example program").dependOn(&run_example.step);

    // The test root must declare test blocks; re-export-only roots discover none.
    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, published.module);
    const unit_tests = b.addTest(.{
        .name = "libjpeg-turbo-tests",
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.has_side_effects = true;
    b.step("test", "Run the behavioural tests").dependOn(&run_tests.step);

    // Run the consumer only when the host can execute the target; otherwise install.
    b.step("consumer", "Build or run the consumer/ package for the selected target")
        .dependOn(&runConsumer(b, target, optimize, delivered, runtime_loaded).step);

    // Cross-target checks compile artifacts but never execute them.
    const check_step = b.step(
        "check",
        "Compile the native library, the facade, the tests and the example for " ++
            "the six check targets without running any of them",
    );
    if (!target.query.isNative()) {
        add_target_check(b, check_step, target.query, optimize, delivered, runtime_loaded);
    } else {
        // Linkage selects the artifact, not the cross-target set.
        for (check_targets[0..]) |query| {
            add_target_check(b, check_step, query, optimize, delivered, runtime_loaded);
        }
    }

    std.debug.print(
        "libjpeg-turbo: {d} C units from src/CMakeLists.txt:653-690, with " ++
            "WITH_ARITH_ENC, WITH_ARITH_DEC, WITH_PROFILE, WITH_SIMD, WITH_TOOLS, " ++
            "WITH_TESTS and WITH_TURBOJPEG all off and WITH_JPEG7/WITH_JPEG8 at " ++
            "upstream's own default FALSE\n",
        .{core_sources.len},
    );
    std.debug.print("libjpeg-turbo: {s}\n", .{switch (delivered) {
        .static => "static archive libjpeg.a (default)",
        .dynamic => b.fmt(
            "shared object libjpeg.so.{d}.{d}.{d}, soname libjpeg.so.{d} " ++
                "(src/CMakeLists.txt:373-397 SO_MAJOR_VERSION {d}, SO_AGE {d}, " ++
                "SO_MINOR_VERSION {d}; src/sharedlib/CMakeLists.txt:58-59)",
            .{
                abi_version.major,
                abi_version.minor,
                abi_version.patch,
                abi_version.major,
                abi_version.major,
                abi_version.major,
                abi_version.minor,
            },
        ),
    }});
    std.debug.print(
        "libjpeg-turbo: SIMD configuration is the portable C one (-Dsimd=c, the only " ++
            "accepted value). WITH_SIMD is undefined, SIMD_ARCHITECTURE is NONE, and no " ++
            "file under src/simd/ is compiled on any target. x86/x86-64 SIMD is NASM " ++
            "assembly (91 files) and Zig 0.16.0 carries no NASM; the other families " ++
            "are C intrinsics that upstream selects by running its own capability " ++
            "probes (src/simd/CMakeLists.txt:289-333). Upstream's 2-6x speed claim " ++
            "(src/README.md:4-10) does NOT apply to this package.\n",
        .{},
    );
    std.debug.print(
        "libjpeg-turbo: jconfig.h, jconfigint.h and jversion.h are generated by " ++
            "tools/jconfig.zig from src/src/{{jconfig.h.in, jconfigint.h.in, " ++
            "jversion.h.in}} for THIS target (SIZEOF_SIZE_T={d} from the target being " ++
            "built, not the generator's host) into the build cache, on the include " ++
            "line ahead of {s}; @BUILD@ is the fixed value \"{s}\" because upstream's " ++
            "string(TIMESTAMP) at src/CMakeLists.txt:91 is not reproducible\n",
        .{ target.result.ptrBitWidth() / 8, source_dir, build_stamp },
    );
    std.debug.print(
        "libjpeg-turbo: the public ABI is libjpeg v6b (JPEG_LIB_VERSION {d}, " ++
            "src/CMakeLists.txt:378-384), LIBJPEG_TURBO_VERSION_NUMBER {d} " ++
            "(src/CMakeLists.txt:34-39); the library needs libc and nothing else\n",
        .{ jpeg_lib_version, libjpeg_turbo_version_number },
    );
    if (runtime_loaded) {
        std.debug.print(
            "libjpeg-turbo: -Druntime is on: the facade module links NO archive and " ++
                "every native call goes through one process-lifetime dispatch table " ++
                "that an explicit load(source) fills. The artifact described above is " ++
                "still built and installed, because delivery and dispatch are separate " ++
                "questions.\n",
            .{},
        );
    } else {
        std.debug.print("libjpeg-turbo: -Druntime is off: the facade links {s} directly.\n", .{
            if (delivered == .dynamic) "libjpeg.so.62.4.0" else "libjpeg.a",
        });
    }
    if (target.result.os.tag == .macos and delivered == .dynamic) {
        std.debug.print(
            "libjpeg-turbo: Mach-O has no version script, so libjpeg.dylib from this " ++
                "build exports libjpeg-turbo's internals as well as its jpeg_* API. " ++
                "That is a real difference from the ELF object and it is reported " ++
                "rather than hidden.\n",
            .{},
        );
    }
    std.debug.print(
        "libjpeg-turbo: a dependent reaches this package as b.dependency(\"{s}\", ..) " ++
            "and dep.module(\"{s}\"); the C artifact is dep.artifact(\"{s}\")\n",
        .{ package_name, lib_name, artifact_name },
    );
}

const Generated = struct {
    jconfig: std.Build.LazyPath,
    jconfigint: std.Build.LazyPath,
    jversion: std.Build.LazyPath,

    /// Generated headers precede source headers because includes use bare names.
    fn dirname(self: Generated) std.Build.LazyPath {
        return self.jconfig.dirname();
    }
};

/// Run the host generator to produce target-specific configuration headers.
/// Declared outputs are cacheable; do not set `has_side_effects`.
fn addGeneratedHeaders(b: *std.Build, target: std.Build.ResolvedTarget) Generated {
    const generator = b.addExecutable(.{
        .name = "jconfig-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path(generator_source),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });

    return generateHeaders(b, generator, target);
}

/// Pass all three templates in one invocation; the generator requires each one.
fn generateHeaders(
    b: *std.Build,
    generator: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) Generated {
    const run = b.addRunArtifact(generator);
    run.setName("generate jconfig.h, jconfigint.h and jversion.h");

    var generated: Generated = undefined;
    for (templates) |which| {
        run.addArg(which.inFlag());
        run.addFileArg(b.path(which.source()));
        run.addArg(which.outFlag());
        const out = run.addOutputFileArg(which.outputName());
        switch (which) {
            .jconfig => generated.jconfig = out,
            .jconfigint => generated.jconfigint = out,
            .jversion => generated.jversion = out,
        }
    }

    // The generator rejects missing substitutions rather than writing partial headers.
    // Keep this table in the build allocator; it must outlive this stack frame.
    const values = plainValues(b, target);
    for (values) |value| {
        run.addArg("--define");
        run.addArg(b.fmt("{s}={s}", .{ value.name, value.value }));
    }
    // Leave optional configuration macros undefined for the portable build.
    for (undefinedMacros) |name| {
        run.addArg("--cmake-undef");
        run.addArg(name);
    }
    return generated;
}

const PlainValue = struct { name: []const u8, value: []const u8 };

/// Return build-allocated substitutions; `SIZE_T` uses the target's width.
fn plainValues(b: *std.Build, target: std.Build.ResolvedTarget) []const PlainValue {
    return b.allocator.dupe(PlainValue, &.{
        // src/CMakeLists.txt:378-384
        .{ .name = "JPEG_LIB_VERSION", .value = b.fmt("{d}", .{jpeg_lib_version}) },
        // src/CMakeLists.txt:17
        .{ .name = "VERSION", .value = versionText(b, upstream_version) },
        // src/CMakeLists.txt:34-39
        .{
            .name = "LIBJPEG_TURBO_VERSION_NUMBER",
            .value = b.fmt("{d}", .{libjpeg_turbo_version_number}),
        },
        // src/CMakeLists.txt:16
        .{ .name = "CMAKE_PROJECT_NAME", .value = cmake_project_name },
        // src/CMakeLists.txt:18, into jversion.h's JCOPYRIGHT
        .{ .name = "COPYRIGHT_YEAR", .value = copyright_year },
        // src/CMakeLists.txt:546-551
        .{ .name = "HIDDEN", .value = "__attribute__((visibility(\"hidden\")))" },
        // CMake's first Clang-compatible `INLINE` candidate (`src/CMakeLists.txt:554-576`).
        .{ .name = "INLINE", .value = "__inline__ __attribute__((always_inline))" },
        // src/CMakeLists.txt:582-586
        .{ .name = "THREAD_LOCAL", .value = "__thread" },
        // Use target pointer width; CMake probes this property (`src/CMakeLists.txt:507`).
        .{
            .name = "SIZE_T",
            .value = b.fmt("{d}", .{target.result.ptrBitWidth() / 8}),
        },
        // src/CMakeLists.txt:709-712, the else() arm of if(WITH_SIMD)
        .{ .name = "SIMD_ARCHITECTURE", .value = "NONE" },
        // Fixed for reproducible headers (`src/CMakeLists.txt:91`).
        .{ .name = "BUILD", .value = build_stamp },
    }) catch @panic("OOM");
}

const undefinedMacros = [_][]const u8{
    // jconfig.h.in:13 and jconfigint.h.in:64; WITH_ARITH_ENC is
    // src/CMakeLists.txt:260-263.
    "C_ARITH_CODING_SUPPORTED",
    // jconfig.h.in:16 and jconfigint.h.in:68; WITH_ARITH_DEC is
    // src/CMakeLists.txt:256-259.
    "D_ARITH_CODING_SUPPORTED",
    // jconfig.h.in:22 and jconfigint.h.in:72; see the module comment.
    "WITH_SIMD",
    // jconfigint.h.in:75.
    "WITH_PROFILE",
    // jconfigint.h.in:40.
    "HAVE_INTRIN_H",
    // CMake probes signed shifts at runtime; Clang shifts arithmetically (`src/CMakeLists.txt:519-543`).
    // Leave the optional `ctzl` path disabled when target widths differ (`src/CMakeLists.txt:510-514`).
    "RIGHT_SHIFT_IS_UNSIGNED",
};

fn versionText(b: *std.Build, version: std.SemanticVersion) []const u8 {
    return b.fmt("{d}.{d}.{d}", .{ version.major, version.minor, version.patch });
}

const Graph = struct {
    /// Bundled C library; system integration is rejected.
    c_lib: *std.Build.Step.Compile,
    module: *std.Build.Module,
};

/// Build one target graph.
/// Matrix graphs keep modules private because names are unique per build.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    public: bool,
    generated: Generated,
) Graph {
    const delivered = deliveredLinkage(target, linkage);

    const c_lib = add_c_library(b, target, optimize, delivered, artifactLabel(b, target, public), generated);

    // Generated headers must precede source headers; `jpeglib.h` uses bare includes.
    const translate = b.addTranslateC(.{
        .root_source_file = b.path(translate_header),
        .target = target,
        .optimize = optimize,
        // `jpeglib.h` uses `FILE` and `size_t` without including their system headers.
        .link_libc = true,
    });
    translate.addIncludePath(generated.dirname());
    translate.addIncludePath(b.path(source_dir));

    const module = if (public)
        b.addModule(lib_name, .{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

    if (runtime_loaded) {
        // Do not link the archive in runtime-loaded mode; that would bypass dispatch.
        module.addImport("c", graph.createModule(b, translate, target, optimize));
    } else {
        // Do not register translated headers as a module without their linked library.
        module.addImport("c", translate.createModule());
        // Share the loader core so public `LoadSource` and `LoadError` types are identical.
        module.addImport("rt", graph.createCoreModule(b, target, optimize));
        module.linkLibrary(c_lib);
    }

    // Match dependent include paths to the archive's generated/source header order.
    module.addIncludePath(generated.dirname());
    module.addIncludePath(b.path(source_dir));

    return .{ .c_lib = c_lib, .module = module };
}

/// Build the 98 upstream C units; artifact and pkg-config linkage must match.
fn add_c_library(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    name: []const u8,
    generated: Generated,
) *std.Build.Step.Compile {
    const c_lib = b.addLibrary(.{
        .name = name,
        .linkage = linkage,
        .version = if (linkage == .dynamic) abi_version else null,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = if (linkage == .dynamic) true else null,
        }),
    });
    const c_mod = c_lib.root_module;

    // Generated headers must precede source headers because includes use bare names.
    c_mod.addIncludePath(generated.dirname());
    c_mod.addIncludePath(b.path(source_dir));

    // Keep configuration in generated headers; compile-line macros could disagree.
    for (core_sources) |source| {
        c_mod.addCSourceFile(.{
            .file = b.path(source),
            // gnu99 keeps POSIX `setenv` visible; strict c99 hides it (`src/src/jinclude.h:137`).
            .flags = &.{"-std=gnu99"},
        });
    }

    if (linkage == .dynamic) setVersionScript(b, c_lib, target);

    for (public_headers) |header| {
        c_lib.installHeader(
            if (header.generated) generated.jconfig else b.path(source_dir).path(b, header.source),
            header.source,
        );
    }

    return c_lib;
}

/// ELF exports the `jpeg_*` API and localizes other symbols (`src/CMakeLists.txt:604-609`).
/// Mach-O has no version-script equivalent, so other symbols remain exported there.
fn setVersionScript(
    b: *std.Build,
    c_lib: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) void {
    if (target.result.ofmt != .elf) return;

    const files = b.addWriteFiles();
    c_lib.setVersionScript(files.add("libjpeg.map",
        \\{
        \\  global:
        \\    jpeg_*;
        \\  local:
        \\    *;
        \\}
    ));
}

/// Compile one target's library, facade, tests, and example without execution.
fn add_target_check(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
) void {
    const cross_target = b.resolveTargetQuery(query);
    // Name check artifacts by target triple.
    const triple = cross_target.result.zigTriple(b.allocator) catch @panic("unspellable target");

    if (refusalFor(cross_target.result.os.tag) != null) refuseTarget(b, cross_target);

    // Generate headers per target because `SIZE_T` is target-dependent.
    const generated = addGeneratedHeaders(b, cross_target);

    const cross = addGraph(b, cross_target, optimize, linkage, runtime_loaded, false, generated);

    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addTest(.{
        .name = b.fmt("libjpeg-turbo-tests-{s}", .{triple}),
        .root_module = test_mod,
    }).step);

    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addExecutable(.{
        .name = b.fmt("libjpeg-turbo-smoke-{s}", .{triple}),
        .root_module = example_mod,
    }).step);

    step.dependOn(&cross.c_lib.step);
}

/// Run the separate consumer build with this graph's resolved options.
fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
) *std.Build.Step.Run {
    const triple = target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    // The triple omits the CPU; forward the resolved CPU selection separately.
    // `addArg` copies the values, so their temporary strings can be freed.
    const cpu = target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    // Use the Zig executable running this build.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(linkage)}));
    run.addArg(b.fmt("-Druntime={s}", .{if (runtime_loaded) "true" else "false"}));
    // Keep the nested build's SIMD setting identical.
    run.addArg("-Dsimd=c");
    // Forward the resolved negative system flag so the nested graph stays bundled.
    run.addArg(b.fmt("-fno-sys={s}", .{artifact_name}));
    if (b.enable_darling) run.addArg("-fdarling");
    if (b.enable_qemu) run.addArg("-fqemu");
    if (b.enable_rosetta) run.addArg("-frosetta");
    if (b.enable_wasmtime) run.addArg("-fwasmtime");
    if (b.enable_wine) run.addArg("-fwine");
    if (b.libc_runtimes_dir) |runtimes| run.addArgs(&.{ "--libc-runtimes", runtimes });
    run.addArg("-j8");
    run.addArg("--summary");
    run.addArg("all");
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
    }
    // Reuse the parent's global package cache.
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArg("--global-cache-dir");
        run.addArg(global_cache);
    }
    // Forward an absolute install prefix; the nested build runs from `consumer/`.
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    // Place program arguments after `--` so the nested build does not parse them as options.
    if (b.args) |args| {
        run.addArg("--");
        run.addArgs(args);
    }
    run.has_side_effects = true;
    return run;
}

/// Whether this host can execute the target with its enabled runners.
fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const host = &b.graph.host.result;
    const candidate = &target.result;
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .allow_darling = b.enable_darling,
        .allow_qemu = b.enable_qemu,
        .allow_wasmtime = b.enable_wasmtime,
        .allow_wine = b.enable_wine,
        // The consumer executable has no linkage, so Run's musl linker gate does not apply.
        .qemu_fixes_dl = candidate.isGnuLibC() and b.libc_runtimes_dir != null,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(b.graph.io, host, candidate, options)) {
        .native, .rosetta => true,
        // `Run` applies the same switches before enabling each executor.
        .wine, .wasmtime, .darling => true,
        // QEMU needs GNU libc runtimes; otherwise install the cross target instead.
        .qemu => !(candidate.isGnuLibC() and b.libc_runtimes_dir == null),
        .bad_dl, .bad_os_or_cpu => false,
    };
}

/// Keep upstream's description; it names the library, not this portable-C build.
fn add_pkg_config(b: *std.Build) void {
    const files = b.addWriteFiles();
    // Add the returned install step; otherwise the `.pc` file is not installed.
    const install_pc = b.addInstallFile(
        files.add("libjpeg.pc", b.fmt(
            \\# libjpeg.pc for the libjpeg-turbo {s} SDK.
            \\#
            \\# Generated from upstream's own template, src/release/libjpeg.pc.in, by
            \\# substituting the five @VAR@s configure_file would. `prefix` is
            \\# pcfiledir-relative so the installed file is correct wherever --prefix put
            \\# it. build.zig's add_pkg_config names the upstream line each field
            \\# comes from.
            \\#
            \\# BUILT CONFIGURATION: the portable C one. WITH_SIMD is off,
            \\# SIMD_ARCHITECTURE is NONE, and no file under src/simd/ is compiled on
            \\# any target. The Description line below is upstream's own wording and is
            \\# preserved, not rewritten: it names the library, whose upstream README
            \\# makes the same claim for every configuration upstream ships.
            \\prefix=${{pcfiledir}}/../..
            \\exec_prefix=${{prefix}}
            \\libdir=${{prefix}}/lib
            \\includedir=${{prefix}}/include
            \\
            \\Name: libjpeg
            \\Description: A SIMD-accelerated JPEG codec that provides the libjpeg API
            \\Version: {s}
            \\
            \\Libs: -L"${{libdir}}" -ljpeg
            \\Cflags: -I"${{includedir}}"
            \\
        , .{ versionText(b, upstream_version), versionText(b, upstream_version) })),
        "lib/pkgconfig/libjpeg.pc",
    );
    b.getInstallStep().dependOn(&install_pc.step);
}

/// Install the IJG and BSD licence texts; IJG terms require distributor attribution.
fn install_licence_records(b: *std.Build) void {
    for (licence_records) |record| {
        const install_record = b.addInstallFileWithDir(
            b.path(record.source),
            .prefix,
            b.fmt("share/licenses/libjpeg-turbo/{s}", .{record.basename}),
        );
        b.getInstallStep().dependOn(&install_record.step);
    }
}

fn refusalFor(os: std.Target.Os.Tag) ?[]const u8 {
    switch (os) {
        else => return null,
    }
}

fn refuseTarget(_: *std.Build, target: std.Build.ResolvedTarget) noreturn {
    const reason = refusalFor(target.result.os.tag) orelse
        unreachable; // called only when refusalFor answered non-null
    std.log.err("libjpeg-turbo: refusing to build for {s}: {s}", .{
        @tagName(target.result.os.tag),
        reason,
    });
    @panic("libjpeg-turbo: refusing to build for this target");
}

/// Validate that each target is attempted or has a refusal reason.
fn checkMatrixPartition(b: *std.Build) void {
    for (refused_check_targets) |query| {
        const os = query.os_tag orelse b.graph.host.result.os.tag;
        if (refusalFor(os) == null) {
            std.log.err(
                "libjpeg-turbo: refused_check_targets names {s}, but refusalFor does " ++
                    "not refuse it. Either the entry or the decision function is " ++
                    "wrong, and a target in that state is silently dropped.",
                .{query.zigTriple(b.allocator) catch @panic("unspellable target")},
            );
            @panic("libjpeg-turbo: the check matrix is not a partition");
        }
    }
    for (check_targets) |query| {
        const os = query.os_tag orelse b.graph.host.result.os.tag;
        if (refusalFor(os) != null) {
            std.log.err(
                "libjpeg-turbo: check_targets names {s}, which refusalFor refuses. " ++
                    "A refused target cannot also be a matrix row.",
                .{query.zigTriple(b.allocator) catch @panic("unspellable target")},
            );
            @panic("libjpeg-turbo: the check matrix is not a partition");
        }
    }
}

/// WASI has no shared-object form; deliver static if dynamic was requested.
/// This selects artifact form, not whether the library compiles for the target.
fn deliveredLinkage(target: std.Build.ResolvedTarget, requested: std.builtin.LinkMode) std.builtin.LinkMode {
    return switch (requested) {
        .static => .static,
        .dynamic => switch (target.result.os.tag) {
            .wasi => .static,
            else => .dynamic,
        },
    };
}

fn artifactLabel(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    public: bool,
) []const u8 {
    if (public) return artifact_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}-{s}", .{ artifact_name, lib_name, triple });
}
