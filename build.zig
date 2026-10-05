// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers, and NOTICE.md for the
// per-file inventory of the upstream material this package ships.

//! The build graph for libjpeg-turbo 3.2.0 as a standalone Zig SDK.
//!
//! Four things happen here and nothing else does:
//!
//!   1. `src/src/jconfig.h.in`, `src/src/jconfigint.h.in` and
//!      `src/src/jversion.h.in` are turned into the three headers the library
//!      needs, **per target**, by a host-target generator run by this build.
//!   2. The 98 C units of upstream's own `JPEG_SOURCES`
//!      (`src/CMakeLists.txt:653-690`) are compiled - the whole closure, no
//!      CMake, no autotools, no build-time download, no system library, and no
//!      sibling dependency.
//!   3. `zig/translate.h` is translated for the same target and configuration,
//!      and `zig/root.zig` is wrapped around it as the published module
//!      `dep.module("libjpeg_turbo")`.
//!   4. The C artifact is installed as `libjpeg.a` or `libjpeg.so.62.4.0` with
//!      soname `libjpeg.so.62`, together with the four public headers, a
//!      hand-written `libjpeg.pc` and the licence texts.
//!
//! Every claim below about upstream is `SOURCE-CONFIRMED`: it is read out of a
//! file in this repository and named with that file and line. **No gate has
//! been run for this package**, so nothing here reports a result. See
//! `FORK-NOTES.md` entry 6.
//!
//! # Commands
//!
//! ```
//!   zig build                       # libjpeg.a, the headers, libjpeg.pc
//!   zig build -Dlinkage=dynamic     # libjpeg.so.62.4.0 and its soname symlink
//!   zig build test                  # tests.zig, in Debug
//!   zig build smoke                 # smoke.zig, run
//!   zig build check                 # compile-only, six targets, nothing run
//!   zig build consumer              # the consumer/ package as a nested build
//!   zig build -Dsimd=c              # the only accepted -Dsimd value
//! ```
//!
//! # Published surface
//!
//! Two names, and they are not interchangeable:
//!
//!   * `dep.module("libjpeg_turbo")`, then `@import("libjpeg_turbo")` in source.
//!     The underscore is a Zig identifier spelling; the directory is
//!     `libjpeg-turbo` and the dependency-map key is `"libjpeg-turbo"`.
//!   * `dep.artifact("jpeg")`, the C artifact. It is upstream's own name -
//!     `add_library(jpeg SHARED ...)` at `src/sharedlib/CMakeLists.txt:58` and
//!     `OUTPUT_NAME jpeg` for the static library at `src/CMakeLists.txt:770` -
//!     which is what Zig emits as `libjpeg.a` / `libjpeg.so.62.4.0`.
//!
//! # THE SIMD BOUNDARY, which a reader must see before the rest
//!
//! **This package builds the portable C configuration only. `WITH_SIMD` is not
//! defined, nothing under `src/simd/` is compiled, and `SIMD_ARCHITECTURE` is
//! `NONE` on every target. There is no silent substitution anywhere in this
//! file**: `-Dsimd` accepts the single value `c` and refuses every other value
//! with the reason printed and a non-zero exit, the configure-time summary says
//! which configuration was built, and no branch of this graph ever reaches an
//! assembler.
//!
//! *Where the C fallback is not a choice but the only option.* x86 and x86-64
//! SIMD is **NASM assembly**: 56 `.asm` files under `src/simd/i386/` and 35
//! under `src/simd/x86_64/`, selected at `src/simd/CMakeLists.txt:137` and
//! `:148` and assembled through `enable_language(ASM_NASM)` at `:61`. Zig
//! 0.16.0's toolchain contains no NASM and the clang in it does not accept NASM
//! syntax, so those 91 files **cannot be assembled from this build graph on
//! `x86_64-linux-gnu` or `x86_64-windows-gnu`**, and asking for them would
//! require adding a NASM toolchain this SDK does not carry. The 98-unit closure
//! compiles without them, and upstream itself produces exactly this
//! configuration when the assembler is missing (`src/simd/CMakeLists.txt:1-10`,
//! `:53-61`, with `REQUIRE_SIMD` defaulting **FALSE** at
//! `src/CMakeLists.txt:252-255`).
//!
//! *Where the C fallback is a stated choice, not a toolchain limit.* ARM NEON
//! (`src/simd/arm/`, `aarch32/`, `aarch64/`), PowerPC (`src/simd/powerpc/`),
//! RISC-V RVV (`src/simd/riscv64/`) and MIPS MSA / LoongArch LSX
//! (`src/simd/mips64/`) are **plain C with compiler intrinsics**, which this
//! toolchain *can* compile. They are excluded for a different and stated
//! reason: CMake picks the per-architecture source list by `CPU_TYPE` and
//! **generates** `simd/arm/neon-compat.h` from capability probes it runs itself
//! (`src/simd/CMakeLists.txt:349`, probes at `:289-333`), plus `getauxval` /
//! `elf_aux_info` symbol probes (`:361-372`). Reproducing that selection here
//! would mean writing those probes ourselves, which is inventing configuration
//! rather than porting it. The one exception in the tree is
//! `src/simd/riscv64/jsimdcpu.S`, a GNU-as file reached through
//! `enable_language(ASM)` at `src/simd/CMakeLists.txt:477`; it is inside the
//! excluded directory and is therefore not compiled either.
//!
//! *What the exclusion costs.* Upstream's own README states that on systems
//! with common CPU architectures libjpeg-turbo is generally 2-6x as fast as
//! libjpeg (`src/README.md:4-10`). **That advantage is not available here** and
//! this package makes no parity claim with upstream's full-speed x86
//! configuration. Every `jsimd_*` call site is behind `#ifdef WITH_SIMD`, so the
//! exclusion is configuration and not a source edit; `UPSTREAM.md` carries the
//! complete table.
//!
//! # Three headers are generated, not checked in, and none is optional
//!
//! Upstream writes them with `configure_file` at `src/CMakeLists.txt:631`
//! (`jversion.h`), `:716` (`jconfig.h`) and `:717` (`jconfigint.h`). All three
//! are required:
//!
//!   * `src/src/jerror.c:27` includes `"jversion.h"`, and `jerror.c` is one of
//!     the 98 units (`src/CMakeLists.txt:688`).
//!   * `src/src/jinclude.h:25` includes `"jconfig.h"` by bare name, and
//!     `src/src/jpeglib.h:41-42` does the same, so every consumer of this
//!     package needs it too.
//!   * `src/src/jinclude.h:26` includes `"jconfigint.h"`, and `jinclude.h` is
//!     the first include of essentially every unit in the closure.
//!
//! `tools/jconfig.zig` performs CMake's `@VAR@` and `#cmakedefine` substitution
//! from upstream's own `.in` templates. It is a **host** program that is handed
//! the **target's** `SIZEOF_SIZE_T`, per AGENTS.md §5: a cross build never sees
//! the generator host's word size. The generated directory is placed **before**
//! `src/src/` on every include line, which is the whole of the ordering
//! argument - the bare-name includes have to find the generated copy and nothing
//! else may.
//!
//! One substitution is **not** upstream's: `@BUILD@`. Upstream fills it with
//! `string(TIMESTAMP "%Y%m%d")` (`src/CMakeLists.txt:91`), which is not
//! reproducible. This build substitutes the fixed string `zig-3.2.0` and says
//! so rather than reproducing an unreproducible value.
//!
//! # Options upstream turns off here
//!
//! `WITH_ARITH_ENC` (`src/CMakeLists.txt:260-263`), `WITH_ARITH_DEC` (`:256-259`),
//! `WITH_PROFILE`, `WITH_SIMD` (`:281-283`), `WITH_TOOLS`, `WITH_TESTS` and
//! `WITH_TURBOJPEG` all default to **TRUE** upstream and are **off** here.
//! `WITH_JPEG7` and `WITH_JPEG8` are `FALSE` here, which is upstream's own
//! default, so the ABI this package delivers is libjpeg **v6b**. The
//! consequences are concrete: `jcarith.c`, `jdarith.c`, `jaricom.c` and
//! `tjutil.c` are not compiled, `cjpeg`/`djpeg`/`jpegtran` are not built, and
//! `turbojpeg*.c` is not built. `README.md` states each one and why.
//!
//! The command-line tools are out for a reason worth naming: upstream gates them
//! behind `WITH_TOOLS`, and `src/CMakeLists.txt:884-927` shows what `cjpeg`
//! pulls in - `rdbmp.c`, `rdgif.c`, three `wrapper/rdpng-*.c`, three
//! `wrapper/rdppm-*.c`, `rdtarga.c` **plus the bundled zlib and the bundled
//! libspng**, with `CDJPEG_COMPILE_FLAGS` at `:882-883` turning on
//! `-DBMP_SUPPORTED -DGIF_SUPPORTED -DPNG_SUPPORTED -DSPNG_STATIC
//! -DPPM_SUPPORTED -DTARGA_SUPPORTED`. Taking them would mean vendoring a second
//! zlib and a PNG decoder into the closure. **The library is the deliverable;
//! the tools are not part of it.**
//!
//! # The linker, and what the library needs
//!
//! libc, and nothing else. `src/src/jinclude.h:36-39` pulls in `<stddef.h>`,
//! `<stdlib.h>`, `<stdio.h>` and `<string.h>`, and `src/src/jmemnobs.c:31-58`
//! reaches `malloc`/`free` through `MALLOC`. No unit in the closure reaches a
//! third-party library; upstream's own zlib dependency belongs to the
//! command-line tools and to TurboJPEG, neither of which this package builds
//! (`src/sharedlib/CMakeLists.txt:30-41`).
//!
//! An ELF shared object gets upstream's restricted export surface: the whole
//! `jpeg_*` namespace global and everything else local. Upstream writes a
//! version script it generates from a symbol list; this writes the namespace,
//! which cannot omit a header-declared function and so cannot have the defect a
//! generated list has. **Mach-O has no equivalent**: a `libjpeg.dylib` from this
//! build exports libjpeg-turbo's internals as well as its API. That is a real
//! difference from the ELF object and `build` prints it rather than hiding it.
//!
//! # System mode is vacuous here
//!
//! There is no `-Dsystem` option, and `b.systemIntegrationOption("jpeg", ...)`
//! refuses the flag rather than honouring it. A system mode would have to
//! translate the *installed* `jconfig.h` next to the installed `jpeglib.h` from
//! the same prefix, because `src/src/jpeglib.h:41-42` includes `jconfig.h` by
//! bare name and that file is generated per configuration; compiling this tree's
//! headers against an older installed libjpeg is the silent-ABI failure
//! AGENTS.md rule 4 forbids, and no `b.dependency` performs the check that would
//! catch it. The rule is recorded as **vacuous**, not satisfied
//! (`WISDOM.md` W14).
//!
//! # Two configurations: linked and runtime-loaded
//!
//! `-Dlinkage` and `-Druntime` are orthogonal. `-Dlinkage` decides which
//! artifact this build **delivers and installs**; `-Druntime` decides whether
//! the Zig facade **links** it or resolves its entry points through one
//! process-lifetime dispatch table an explicit `load(source)` fills. Under
//! `-Druntime` the facade module links no archive at all - linking it as well
//! would let the linker resolve the symbols statically and the runtime route
//! would quietly be a linked one - while the artifact is still built and
//! installed, because delivery and dispatch are separate questions.
//!
//! `runtime/graph.zig` owns the seam and exposes exactly two entry points,
//! `createModule` and `createCoreModule`; this file only chooses between them.
//! The generated dispatch imports the loader core, and the facade in the linked
//! branch imports *that same* core module, because there must be exactly one
//! `LoadSource` and one `LoadError` in a build.
//!
//! # What is deliberately absent
//!
//! `.fingerprint` is missing from `build.zig.zon` because it is an identifier
//! the toolchain derives and no gate has been run (`FORK-NOTES.md` entry 4).
//! `src/simd/` is carried, digested and never compiled. `src/doc/`,
//! `src/test/`, `src/testimages/`, `src/fuzz/`, `src/jna/`, `src/win/` and the
//! `tj*` / `strtest.c` sources ship uncompiled and undeleted - **upstream's test
//! suites are not deleted by this fork**, and this SDK's own tests are
//! independent known answers instead.

const std = @import("std");

/// `build.zig.zon` itself. `@import` of the manifest is how a build script
/// reads `.version` without a second copy of it.
const manifest = @import("build.zig.zon");

/// `build.zig.zon .version`, parsed. The parse is the loud part: a manifest
/// whose `.version` is not a semantic version fails to configure here rather
/// than being silently compared as something else.
const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon: .version is not a semantic version");

/// The runtime-loading build half, owned by the API role.
///
/// `createModule` builds the generated dispatch that replaces
/// `translate.createModule()` under `-Druntime`; it makes the loader-core
/// module itself and re-exports `LoadSource`/`LoadError` from it.
/// `createCoreModule` builds that same core module for the *linked* branch.
///
/// The two branches must not both call `createCoreModule`: `LoadSource` and
/// `LoadError` are this SDK's public types, so they have to be the *same* types
/// in one build. `addGraph` is the only place that calls either of them.
const graph = @import("runtime/graph.zig");

/// The name `b.dependency("libjpeg-turbo", ...)` takes and the key the
/// dependent's manifest spells.
///
/// The hyphen is a directory name; a Zig package name is an identifier, so the
/// manifest's `.name` is `.libjpeg_turbo` and `dep.module("libjpeg_turbo")` is
/// what the module is reached through. The map key is still the hyphenated
/// string.
const package_name = "libjpeg-turbo";

/// The module name: `dep.module("libjpeg_turbo")`, then
/// `@import("libjpeg_turbo")` in source.
const lib_name = "libjpeg_turbo";

/// The C artifact name: `dep.artifact("jpeg")`.
///
/// It is upstream's own name, which is why it differs from the module name on
/// purpose. Zig prepends the platform's `lib` prefix to an artifact name.
const artifact_name = "jpeg";

/// The upstream release this graph compiles, read out of `src/CMakeLists.txt:17`
/// (`set(VERSION 3.2.0)`). `build` compares it with `build.zig.zon`'s `.version`
/// and refuses to configure when they disagree, so the manifest, the shared
/// object's file name and the pkg-config `Version:` field cannot describe three
/// different releases.
const upstream_version: std.SemanticVersion = .{ .major = 3, .minor = 2, .patch = 0 };

/// `src/CMakeLists.txt:378-384`, the libjpeg API version this configuration
/// emulates. `WITH_JPEG7` and `WITH_JPEG8` are both off, so this is v6b.
const jpeg_lib_version = 62;

/// `src/CMakeLists.txt:34-39`: major, then minor and revision zero-padded to
/// three digits.
const libjpeg_turbo_version_number = 3002000;

/// `src/CMakeLists.txt:18`, which feeds `JCOPYRIGHT` in `jversion.h`.
const copyright_year = "1991-2026";

/// `src/CMakeLists.txt:16`.
const cmake_project_name = "libjpeg-turbo";

/// The fixed value substituted for `@BUILD@`, and the reason it is not
/// upstream's: `src/CMakeLists.txt:91` is `string(TIMESTAMP "%Y%m%d")`, which is
/// not reproducible, so reproducing it here would make the generated header
/// differ between two builds of the same source.
const build_stamp = "zig-3.2.0";

/// The shared object's numbers, which are upstream's and not this build's
/// choice. `src/CMakeLists.txt:373-397` computes `SO_MAJOR_VERSION 62`,
/// `SO_AGE 4` and `SO_MINOR_VERSION 0`; `src/sharedlib/CMakeLists.txt:58-59`
/// turns those into `SOVERSION 62` and `VERSION 62.4.0`. So the file is
/// `libjpeg.so.62.4.0` and the soname is `libjpeg.so.62`.
const abi_version: std.SemanticVersion = .{ .major = 62, .minor = 4, .patch = 0 };

/// Where upstream's own source lives, relative to this package root.
///
/// `src/CMakeLists.txt` *is* the tarball root, so a CMake path of
/// `src/jcapimin.c` is `<tarball>/src/src/jcapimin.c` and a CMake path of
/// `src/wrapper/jcapistd-8.c` is `<tarball>/src/src/wrapper/jcapistd-8.c`.
const source_dir = "src/src";

/// The Zig facade, `zig/root.zig`. It re-exports the translated module as `c`.
const facade_source = "zig/root.zig";

/// The one header this package translates, `zig/translate.h`. It is a
/// fork-authored wrapper whose whole job is to name the four public headers and
/// the two system headers `jpeglib.h` refuses to include itself.
const translate_header = "zig/translate.h";

/// The host generator for the three configure-time headers, `tools/jconfig.zig`.
const generator_source = "tools/jconfig.zig";

/// Test root: `tests.zig`.
const test_source = "tests.zig";

/// The deterministic example program: `smoke.zig`.
const example_source = "smoke.zig";

/// The 98 C units of upstream's own closure, transcribed line for line from
/// `src/CMakeLists.txt:653-690`.
///
/// **This list is the deliverable and nothing may be dropped from it.** The
/// three conditional appends that follow that `set()` in upstream's file are
/// *not* here, because this package turns each of them off: `WITH_PROFILE`
/// (`:691-693`, `tjutil.c`), `WITH_ARITH_ENC OR WITH_ARITH_DEC` (`:695-697`,
/// `jaricom.c`), `WITH_ARITH_ENC` (`:699-701`, `jcarith.c`) and
/// `WITH_ARITH_DEC` (`:703-705`, `jdarith.c`). `WITH_SIMD` (`:707`) adds the
/// SIMD objects, which the module comment above covers at length.
///
/// `src/src/jpeg_nbits.c` at `:687` is in the list even though a reader may not
/// expect it: it is upstream's data-driven tables for the Huffman decoder, and
/// omitting it removes `LZ_CODE` support from `jdhuff.c`.
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

/// The public headers, as upstream installs them at `src/CMakeLists.txt:2065-2069`:
///
/// ```cmake
/// install(FILES ${CMAKE_CURRENT_BINARY_DIR}/jconfig.h
///               src/jerror.h src/jmorecfg.h src/jpeglib.h
///         DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
/// ```
///
/// The order is upstream's and it is kept, because `jconfig.h` is the generated
/// one and its position in the list is how a reader knows it.
const public_headers = [_]struct { source: []const u8, generated: bool }{
    // Generated: `src/CMakeLists.txt:716`. It installs from the build cache, not
    // from this tree, which is what makes `jpeglib.h:41-42`'s bare-name include
    // resolve for an installed consumer.
    .{ .source = "jconfig.h", .generated = true },
    // The other three are upstream's own files, byte for byte.
    .{ .source = "jerror.h", .generated = false },
    .{ .source = "jmorecfg.h", .generated = false },
    .{ .source = "jpeglib.h", .generated = false },
};

/// The licence texts a consumer of the installed tree needs, installed under
/// upstream's own names so the IJG obligation can be discharged from the
/// install alone.
///
/// `README.ijg` carries the IJG licence text (`src/README.ijg:126-157`) and
/// `src/LICENSE.md` is the roll-up upstream's own file. Both are copied from
/// `src/`, unaltered, which `tools/check-provenance.sh` re-checks.
const licence_records = [_]struct { source: []const u8, basename: []const u8 }{
    .{ .source = "src/README.ijg", .basename = "README.ijg" },
    .{ .source = "src/LICENSE.md", .basename = "LICENSE.md" },
};

/// The six compile targets, per AGENTS.md §6. None of them is dropped, and none
/// is dropped silently: a row that cannot be attempted belongs in
/// `refused_check_targets` below with a reason.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// Matrix cells this package refuses to attempt, with the reason each one would
/// carry.
///
/// **Empty today, and the emptiness is deliberate rather than convenient.** No
/// platform limit has been *observed* for this package, because no gate has been
/// run (`FORK-NOTES.md` entry 5). `wasm32-wasi` is therefore **unknown**, not
/// refused and not working, and `checkMatrixPartition` fails any build that adds
/// a refusal without saying so here. Promoting that row to a refusal needs a run
/// that printed the failure.
const refused_check_targets = [_]std.Target.Query{};

/// The three configure-time templates, by the switch name each pair uses.
const Template = enum {
    jconfig,
    jconfigint,
    jversion,

    /// The template's path in this package.
    fn source(self: Template) []const u8 {
        return switch (self) {
            .jconfig => source_dir ++ "/jconfig.h.in",
            .jconfigint => source_dir ++ "/jconfigint.h.in",
            .jversion => source_dir ++ "/jversion.h.in",
        };
    }

    /// The generator's `--*-in` switch.
    fn inFlag(self: Template) []const u8 {
        return switch (self) {
            .jconfig => "--jconfig-in",
            .jconfigint => "--jconfigint-in",
            .jversion => "--jversion-in",
        };
    }

    /// The generator's `--*-out` switch, which is the same stem.
    fn outFlag(self: Template) []const u8 {
        return switch (self) {
            .jconfig => "--jconfig-out",
            .jconfigint => "--jconfigint-out",
            .jversion => "--jversion-out",
        };
    }

    /// The output file's name, which is the template's name without `.in`.
    fn outputName(self: Template) []const u8 {
        return switch (self) {
            .jconfig => "jconfig.h",
            .jconfigint => "jconfigint.h",
            .jversion => "jversion.h",
        };
    }
};

/// Every template, in the order the generator's `main` walks its table
/// (`tools/jconfig.zig:228-236`). The order is the generator's, not this
/// build's: it renders all three before it writes any.
const templates = [_]Template{ .jconfig, .jversion, .jconfigint };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ---------------------------------------------------------------- system
    //
    // Refused rather than ignored. See "System mode is vacuous here" in the
    // module comment.
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

    // The key is the artifact name, not the module name: it is what the build
    // runner's `-fsys=` flag names and what a dependent's own
    // `systemIntegrationOption` call has to match.
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

    // ------------------------------------------------------------------ SIMD
    //
    // The one option whose whole purpose is to make the boundary visible. There
    // is exactly one legal value, and every other value is a configure-time
    // refusal that prints the reason and exits non-zero. Accepting a value and
    // quietly building the same graph would be the silent substitution the
    // module comment forbids.
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

    // --------------------------------------------------------------- linkage
    const linkage: std.builtin.LinkMode = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Deliver the native library as `libjpeg.a` (the default) or as a real " ++
            "shared object with upstream's own numbers, `libjpeg.so.62.4.0` and " ++
            "soname `libjpeg.so.62` (src/CMakeLists.txt:373-397 and " ++
            "src/sharedlib/CMakeLists.txt:58-59). This selects the delivery and " ++
            "never the dispatch: the same 98 C units are compiled either way.",
    ) orelse .static;

    // ---------------------------------------------------------------- runtime
    //
    // Orthogonal to `-Dlinkage`, and the distinction is the point.
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

    // `build.zig.zon .version` and `src/CMakeLists.txt:17` are one fact. The
    // comparison catches a manifest edited without the source it describes,
    // including an upstream re-sync that moved that line without moving the
    // manifest. It happens at configure time, before any compiler runs.
    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches `set(VERSION 3.2.0)` at " ++
            "src/CMakeLists.txt:17; see UPSTREAM.md");
    }

    // Two lists, one decision function, checked before any graph is configured.
    checkMatrixPartition(b);

    if (refusalFor(target.result.os.tag) != null) refuseTarget(b, target);

    const delivered = deliveredLinkage(target, linkage);
    if (delivered != linkage) {
        // Stated, never silent: the summary below prints the delivered form, and
        // this line says why it is not the requested one.
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

    // `zig build` also compiles the example. It is the cheapest thing that
    // proves the facade, the translated headers and the C archive agree on
    // types, symbols and link-time dependencies. It is compiled, not installed:
    // it is a proof, not a deliverable.
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

    // `zig build smoke` deliberately does not depend on the install step:
    // installing is `zig build`'s job and conflating the two would make a smoke
    // run depend on the install layout.
    const run_example = b.addRunArtifact(example);
    run_example.has_side_effects = true;
    if (b.args) |args| run_example.addArgs(args);
    b.step("smoke", "Run the deterministic example program").dependOn(&run_example.step);

    // The test root is `tests.zig`, which names the test blocks; a root that
    // only re-exported them would discover no tests and still exit zero.
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

    // The separate consumer package, built as its own `zig build`. It runs when
    // this host can execute the selected target and installs when it cannot, so
    // a foreign cell is compile evidence and nothing more.
    b.step("consumer", "Build or run the consumer/ package for the selected target")
        .dependOn(&runConsumer(b, target, optimize, delivered, runtime_loaded).step);

    // The cross-target gate: compile the library, the facade, the tests and the
    // example for each target. Nothing runs here, so every result it produces is
    // compile evidence and not a claim that a foreign binary executed.
    const check_step = b.step(
        "check",
        "Compile the native library, the facade, the tests and the example for " ++
            "the six check targets without running any of them",
    );
    if (!target.query.isNative()) {
        add_target_check(b, check_step, target.query, optimize, delivered, runtime_loaded);
    } else {
        // One matrix, whatever the delivery. `-Dlinkage` selects the artifact,
        // not the set of targets: a target whose OS cannot carry a shared object
        // is a delivery refusal at `deliveredLinkage`, not a missing matrix row.
        for (check_targets[0..]) |query| {
            add_target_check(b, check_step, query, optimize, delivered, runtime_loaded);
        }
    }

    // What this configuration is, read out of the build rather than inferred
    // from a cache directory. These are configure-time lines, not gate results:
    // nothing has been compiled when they print.
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
    // SIMD, stated at configure time because "which configuration" is the
    // question a reader of a support matrix has, and silence reads as
    // "upstream's default" rather than as a decision.
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

// ---------------------------------------------------------------------------
// Generated inputs
// ---------------------------------------------------------------------------

/// The three generated headers for one target.
const Generated = struct {
    jconfig: std.Build.LazyPath,
    jconfigint: std.Build.LazyPath,
    jversion: std.Build.LazyPath,

    /// The directory that goes first on every include line. `jinclude.h:25-26`
    /// includes `jconfig.h` and `jconfigint.h` by bare name and
    /// `jpeglib.h:41-42` includes `jconfig.h`, so the generated copy has to win.
    fn dirname(self: Generated) std.Build.LazyPath {
        return self.jconfig.dirname();
    }
};

/// Builds `tools/jconfig.zig` for the host and runs it **once**, returning the
/// three generated headers.
///
/// The generator is a host program: it is the machine running `zig build` that
/// executes it. What it writes is a **target** configuration, which is why the
/// `--define SIZE_T=` argument below is the width of the target being compiled
/// (AGENTS.md §5) and not the width of the machine running the generator.
///
/// The run steps are cacheable, so `has_side_effects` is deliberately *not*
/// set: the only outputs are the declared output files, which the build system
/// already knows how to hash. Setting the flag would re-run the generator on
/// every invocation for no gain.
fn addGeneratedHeaders(b: *std.Build, target: std.Build.ResolvedTarget) Generated {
    const generator = b.addExecutable(.{
        .name = "jconfig-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path(generator_source),
            // Host, at a fixed mode: this is a build-time program that never
            // enters the artifact, so its optimize mode is this build's business.
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });

    return generateHeaders(b, generator, target);
}

/// One `tools/jconfig.zig` invocation, with every substitution named.
///
/// One run step carries all three templates, because the generator is written
/// to produce all three or none: `tools/jconfig.zig:176-189` rejects a command
/// line that is missing any one of the six paths, and `tools/jconfig.zig:238-256`
/// renders every template before writing any of them. Three run steps of one
/// argument each is not a shape that program accepts, and each would also
/// re-render the other two headers.
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

    // Every `@VAR@`, with the upstream line that computes it.
    // `tools/jconfig.zig` names a value it was not given rather than writing a
    // partial header, so a value missing from this list fails loudly instead of
    // producing a header that breaks deep inside `jmorecfg.h`.
    // `plainValues` returns the table **by value**. A `[]const PlainValue`
    // return would point into that function's own stack frame, which is dead
    // by the time the loop reads it; the stack of the thread that ran
    // `generateHeaders` has already been reused by then. See the note on
    // `plainValues`.
    const values = plainValues(b, target);
    for (values) |value| {
        run.addArg("--define");
        run.addArg(b.fmt("{s}={s}", .{ value.name, value.value }));
    }
    // Every `#cmakedefine` is taken as absent. The reasoning is in the module
    // comment and in UPSTREAM.md; the short form is that each of them selects a
    // branch in upstream's own `.c` units or a block this package does not
    // compile, and `jconfigint.h.in:63` re-derives `WITH_SIMD` from its own
    // `#cmakedefine` at `:74` only after an `#undef`, so with both absent the
    // macro is undefined on every path through the library.
    for (undefinedMacros) |name| {
        run.addArg("--cmake-undef");
        run.addArg(name);
    }
    return generated;
}

const PlainValue = struct { name: []const u8, value: []const u8 };

/// The `@VAR@` substitutions, each with the upstream line that computes it.
///
/// **PENDING-VERIFICATION.** No `tools/jconfig.zig` run has been observed for
/// this package, because no gate has been run. Every value below is
/// `SOURCE-CONFIRMED` as a claim about upstream's files; whether the generator
/// accepts them all, and whether the 98 units compile with the headers they
/// produce, is for the first observed `zig build` to answer.
/// The table is **copied into the build arena**, never returned as a slice of
/// this function's own frame. Half of the values are built at configure time
/// by `b.fmt`, so the array literal is not a comptime constant and lands in
/// `plainValues`'s stack frame. Returning a slice of it hands the caller a
/// pointer into a dead frame, and the caller reads whatever the reused stack
/// holds: observed as `panic: OOM` inside `b.fmt`, with `VERSION`'s `name.len`
/// read back as 0 and its `value.len` as 140728028633904.
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
        // src/CMakeLists.txt:554-576, the first candidate that compiles. Every
        // target this package builds is a clang target, where this candidate is
        // the one upstream reaches. There is no probe here, because a probe
        // would be a configure-time compile (AGENTS.md §4).
        .{ .name = "INLINE", .value = "__inline__ __attribute__((always_inline))" },
        // src/CMakeLists.txt:582-586
        .{ .name = "THREAD_LOCAL", .value = "__thread" },
        // AGENTS.md §5: the width of the TARGET being compiled. Upstream computes
        // this by compiling a probe (src/CMakeLists.txt:507); a Zig build reads
        // it off the resolved target instead, which is the same value and needs
        // no host program and no run.
        .{
            .name = "SIZE_T",
            .value = b.fmt("{d}", .{target.result.ptrBitWidth() / 8}),
        },
        // src/CMakeLists.txt:709-712, the else() arm of if(WITH_SIMD)
        .{ .name = "SIMD_ARCHITECTURE", .value = "NONE" },
        // NOT upstream's: src/CMakeLists.txt:91 is string(TIMESTAMP "%Y%m%d"),
        // which is not reproducible. See the module comment.
        .{ .name = "BUILD", .value = build_stamp },
    }) catch @panic("OOM");
}

/// The `#cmakedefine` lines this build takes as absent.
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
    // jconfig.h.in:53. Upstream defines this only when a runtime probe finds
    // that the compiler shifts signed values as if unsigned
    // (src/CMakeLists.txt:519-543); Zig's clang shifts them arithmetically, so
    // the probe's answer on these targets is "no", and running the probe would
    // be a configure-time run this build graph does not do.
    //
    // This is the one substitution whose value upstream computes by *running*
    // something, and it is the one place where this build resolves a probe by
    // reading a target property instead. `HAVE_BUILTIN_CTZL`
    // (jconfigint.h.in:38) is left out for the same reason: its upstream
    // condition is `sizeof(unsigned long) == sizeof(size_t)`
    // (src/CMakeLists.txt:510-514), which is a target ABI property, and leaving
    // it undefined selects upstream's ordinary `jpeg_nbits`-based path rather
    // than the optional builtin. Both choices are the conservative direction:
    // they can cost speed and cannot produce a wrong decode.
    "RIGHT_SHIFT_IS_UNSIGNED",
};

fn versionText(b: *std.Build, version: std.SemanticVersion) []const u8 {
    return b.fmt("{d}.{d}.{d}", .{ version.major, version.minor, version.patch });
}

// ---------------------------------------------------------------------------
// One target's graph
// ---------------------------------------------------------------------------

/// What one target's build produces.
const Graph = struct {
    /// The C library. Always present: this graph has no system branch, and
    /// `build` refuses `-fsys=jpeg` before any graph is configured.
    c_lib: *std.Build.Step.Compile,
    /// The module a dependent imports.
    module: *std.Build.Module,
};

/// Builds one target's library, generated headers and facade.
///
/// `public` chooses between the package module set, which is what a dependent
/// reaches through `dep.module("libjpeg_turbo")`, and a private module. A
/// cross-target check needs the private form: modules are registered by name
/// against the whole build, so registering `libjpeg_turbo` once per matrix target
/// would leave only the last of them reachable and silently stop checking the
/// rest.
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

    // The same generated directory and the same `src/src` on the translation
    // line as on the compile line, in that order: `jpeglib.h:41-42` includes
    // `jconfig.h` by bare name.
    const translate = b.addTranslateC(.{
        .root_source_file = b.path(translate_header),
        .target = target,
        .optimize = optimize,
        // `<stdio.h>` and `<stddef.h>` are in `zig/translate.h` because
        // `src/src/jpeglib.h:21-29` uses `FILE` and `size_t` and says in as many
        // words that it deliberately does not include them itself.
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
        // A loaded provider must arrive through the platform loader, so the link
        // line names nothing. Linking the archive as well would make the linker
        // resolve the same symbols statically and the runtime route would
        // quietly be a linked one. The artifact is still built and installed,
        // because delivery and dispatch are separate questions.
        module.addImport("c", graph.createModule(b, translate, target, optimize));
    } else {
        // The translated headers are imported, never registered: registering
        // them under a name would let `dep.module("c")` resolve and hand a
        // dependent the same declarations without the library that satisfies
        // them.
        module.addImport("c", translate.createModule());
        // The linked branch needs the loader core for the two public types
        // `LoadSource` and `LoadError`, which must be the same types a caller
        // names in either configuration. `graph.createModule` creates the one
        // core instance the generated dispatch uses and re-exports both types
        // from it; a second instance here would be a *different* `LoadSource`.
        // One instance per build, no more.
        module.addImport("rt", graph.createCoreModule(b, target, optimize));
        module.linkLibrary(c_lib);
    }

    // The same two include directories as the archive's own module, in the same
    // order, on the module a dependent actually imports, so a dependent that
    // compiles its own C against this package finds the headers the core was
    // compiled with.
    module.addIncludePath(generated.dirname());
    module.addIncludePath(b.path(source_dir));

    return .{ .c_lib = c_lib, .module = module };
}

/// Compiles the C library for one target: the 98 units, and nothing else.
///
/// `linkage` is what this target can carry, not what the caller asked for;
/// `deliveredLinkage` resolves the difference and both `addGraph` and `build`
/// call it, so the artifact, the declarations paired with it and the installed
/// `libjpeg.pc` cannot describe different linkages.
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
        // Null for a static archive, which has no soname and no versioned file
        // name.
        .version = if (linkage == .dynamic) abi_version else null,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            // libc, because `src/src/jinclude.h:36-39` includes `<stddef.h>`,
            // `<stdlib.h>`, `<stdio.h>` and `<string.h>` for essentially every
            // unit, and `src/src/jmemnobs.c:31-58` reaches `malloc`/`free`
            // through `MALLOC`. The standard vocabulary is upstream's own
            // requirement, not an addition by this build.
            .link_libc = true,
            // A shared library is position-independent whether or not this says
            // so; naming it makes the requirement explicit.
            .pic = if (linkage == .dynamic) true else null,
        }),
    });
    const c_mod = c_lib.root_module;

    // Two include directories, in this order, and the order is the whole of the
    // argument: `jinclude.h:25-26` includes `jconfig.h` and `jconfigint.h` by
    // bare name, so the generated directory has to come first for there to be
    // exactly one copy of each in the search path. Nothing is ever written into
    // `src/`, which is what lets `build.zig.zon` name `"src"` as a bare
    // directory.
    c_mod.addIncludePath(generated.dirname());
    c_mod.addIncludePath(b.path(source_dir));

    // No command-line macro is added, and that is a decision rather than an
    // omission. `BITS_IN_JSAMPLE` is 8 in both templates already
    // (`src/src/jconfig.h.in:27-31`, `src/src/jconfigint.h.in:52-55`) and
    // `MEM_SRCDST_SUPPORTED` is a plain `#define`
    // (`src/src/jconfig.h.in:18-19`), so neither is needed on the compile line.
    // Every other configuration decision upstream makes is a substitution in
    // the generated headers, which is where this build keeps it too: a macro on
    // the compile line that the headers do not agree with would be two
    // configurations at once, and the header is what `jpeglib.h` consumers see.
    for (core_sources) |source| {
        c_mod.addCSourceFile(.{
            .file = b.path(source),
            // C99, which is what the closure is written in: `src/src` uses
            // `//`-free C89 comments but also `inline` declarations and
            // `stdint.h`-style widths through `jmorecfg.h`, and the default mode
            // Zig's clang would pick is not something to leave to chance.
            //
            // `gnu`, not `c`: upstream passes no `-std=` at all
            // (`src/CMakeLists.txt` sets no `CMAKE_C_STANDARD` and no
            // `CMAKE_C_FLAGS` standard flag), so it compiles with the
            // compiler's own default dialect, which is `__STRICT_ANSI__` off.
            // `-std=c99` turns `__STRICT_ANSI__` on, which hides the POSIX
            // declarations that dialect exposes, and `src/src/jinclude.h:137`
            // then fails on an undeclared `setenv`. The standard level stays
            // C99; only the strictness changes.
            .flags = &.{"-std=gnu99"},
        });
    }

    if (linkage == .dynamic) setVersionScript(b, c_lib, target);

    // The four public headers. `jconfig.h` installs from the build cache and the
    // other three from this tree, byte for byte. Installing them also puts them
    // on the include path of anything that links this artifact, so a C consumer
    // needs nothing from this tree to call it - and it is what makes
    // `jpeglib.h:41-42`'s bare-name include of `jconfig.h` resolve for an
    // installed consumer rather than only inside this build.
    for (public_headers) |header| {
        c_lib.installHeader(
            if (header.generated) generated.jconfig else b.path(source_dir).path(b, header.source),
            header.source,
        );
    }

    return c_lib;
}

/// Gives an ELF shared library upstream's restricted export surface.
///
/// Every public declaration in `src/src/jpeglib.h` is an `EXTERN(...)` function
/// named `jpeg_`, `jpeg12_` or `jpeg16_`, so exporting the namespace globally
/// and everything else locally is upstream's export surface expressed without
/// the symbol list upstream generates with a `-Wl,--version-script`
/// (`src/CMakeLists.txt:604-609`). No cataloguing step can omit a
/// header-declared function this way, which is the defect a generated list has.
///
/// Mach-O has no version script that GNU ld or lld reads the same way, so this
/// does nothing for Darwin; `build` prints the difference rather than hiding it.
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

/// Compiles the library, the facade, the tests and the example for one matrix
/// target and attaches all of them to `step`.
///
/// Building the test binary and the example is what makes this a check of the
/// facade rather than of an unreferenced archive: Zig analyses a function body
/// only when something calls it, and `tests.zig` and `smoke.zig` call the
/// facade. The full 98-unit C closure is compiled by the same graph, and each
/// cell generates its own three headers, because `@SIZE_T@` is target-dependent
/// (AGENTS.md §5). Nothing is run here, so every result this step produces is
/// compile evidence and not a claim that a cross-built binary executed.
fn add_target_check(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
) void {
    const cross_target = b.resolveTargetQuery(query);
    // The triple names the cross artifacts. Six targets in one build graph
    // otherwise produce six steps called `jpeg`, which makes `--summary all`
    // useless for telling them apart.
    const triple = cross_target.result.zigTriple(b.allocator) catch @panic("unspellable target");

    if (refusalFor(cross_target.result.os.tag) != null) refuseTarget(b, cross_target);

    // Generated per cell, for the reason the module comment gives.
    const generated = addGeneratedHeaders(b, cross_target);

    // The archive is built here and not merely referenced: the test binary and
    // the example both link it, so a cell where the 98 units do not compile
    // fails at this step rather than at the first install.
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

    // A target where the 98 units do not compile is a target this SDK does not
    // support, and the matrix says so at build time rather than at install.
    step.dependOn(&cross.c_lib.step);
}

// ---------------------------------------------------------------------------
// The consumer package
// ---------------------------------------------------------------------------

/// Runs the consumer package as its own `zig build` in `consumer/`.
///
/// The consumer is a separate package on purpose: a manifest dependency here
/// would close a cycle, because its manifest points back at this package by
/// path. Running it as a separate build is what makes the proof real - that a
/// package which only writes `b.dependency("libjpeg-turbo", ...)` and
/// `dep.module("libjpeg_turbo")` gets a working, correctly linked library.
///
/// Everything this build resolved travels with it: the target and CPU, the
/// optimize mode, the linkage and dispatch shapes, the SIMD configuration, the
/// system-integration decision, the executor switches, both cache directories,
/// the install prefix, the job width and the summary. An argument left behind
/// would be a proof of a configuration nobody asked for - and `-Dsimd` is one of
/// them, because a nested build that did not receive it would resolve its own
/// default rather than this cell's.
fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
) *std.Build.Step.Run {
    const triple = target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    // The triple names the architecture, the OS and the ABI; it carries no CPU
    // model and no feature set (`lib/std/Target/Query.zig:421-423`), and `cpu` is
    // a separate option. `serializeCpu` writes `native` for a query that named
    // no CPU and `baseline` for a cross query, and `Target.Query.parseCpu`
    // recognises both spellings, so the nested `standardTargetOptions` resolves
    // this build's selection rather than one of its own. `addArg` copies each
    // argument, so these temporaries can go right after.
    const cpu = target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    // `b.graph.zig_exe` is the compiler running this build script, so the nested
    // build is the same toolchain rather than whatever is on PATH.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(linkage)}));
    run.addArg(b.fmt("-Druntime={s}", .{if (runtime_loaded) "true" else "false"}));
    // The only accepted SIMD value, forwarded so the cell's configuration is
    // stated rather than inferred from a default.
    run.addArg("-Dsimd=c");
    // The mode *this* build resolved, which is a different question from which
    // option asked for it. `b.systemIntegrationOption` is fed by the build
    // runner's `-fsys=`/`-fno-sys=` flags
    // (`lib/compiler/build_runner.zig:169-174`) and is never an entry in the
    // `-D` map, so forwarding `-Dsystem` would set the nested graph's *default*
    // and leave the answer to that graph's own runner instead of this build's.
    // The flag itself goes instead, so the dependency's own
    // `systemIntegrationOption(artifact_name, ...)` resolves the answer this
    // build already reached.
    //
    // The key is the artifact name, and only the negative spelling is possible:
    // this graph has no system branch, so a nested build told `-fsys=jpeg` would
    // stop with its own message while the outer build that launched it was
    // compiling the bundled tree - two answers to one cell.
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
    // A null `path` means "the current directory", and the working directory is
    // already the consumer package, so the default is right.
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
    }
    // The global cache is inherited whole rather than subdirectoryed: it is one
    // shared store of packages and hashes, so a nested build left to resolve its
    // own would fetch again what this one already holds, and would write outside
    // the root this workspace approved. Two tokens, as documented at
    // `lib/compiler/build_runner.zig:1675`.
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArg("--global-cache-dir");
        run.addArg(global_cache);
    }
    // The install prefix this invocation resolved, handed on when the caller
    // named one. A nested `zig build` left to resolve its own installs into
    // `consumer/zig-out` - a build artefact inside a source package - rather
    // than into the directory the caller asked for. A relative `--prefix` would
    // resolve against the working directory set above, `consumer/`, and not
    // against this build's root, so it is made absolute before it is handed on.
    // `DESTDIR` needs no forwarding, because the nested build inherits the
    // environment this one ran with.
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    // The caller's own arguments, last and behind `--`: `--` is where the build
    // runner stops parsing options and keeps the rest as `b.args`
    // (`lib/compiler/build_runner.zig:428-430`), so this `--` has to follow
    // every argument above - those are this package's own bookkeeping with the
    // nested build, and only what the caller typed after `--` belongs to the
    // program. `consumer/src/main.zig` documents a command-line input, and this
    // is the only place those words can enter the nested graph at all.
    if (b.args) |args| {
        run.addArg("--");
        run.addArgs(args);
    }
    // The nested build is the step's only observable effect.
    run.has_side_effects = true;
    return run;
}

/// True when this build can execute `target`'s binaries.
///
/// `std.zig.system.getExternalExecutor` is the predicate
/// `std.Build.Step.Run` applies to the artifact it is about to spawn
/// (`lib/std/Build/Step/Run.zig:1268`), and `allow_*` carries this build's own
/// executor switches, so the two cannot disagree. `link_libc` holds in every
/// mode this package builds; the `.qemu` arm carries `Run`'s own second gate.
fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const host = &b.graph.host.result;
    const candidate = &target.result;
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .allow_darling = b.enable_darling,
        .allow_qemu = b.enable_qemu,
        .allow_wasmtime = b.enable_wasmtime,
        .allow_wine = b.enable_wine,
        // `consumer/` builds its executable with `b.addExecutable` and no
        // linkage, so `Run`'s musl half of `need_cross_libc` never holds here.
        .qemu_fixes_dl = candidate.isGnuLibC() and b.libc_runtimes_dir != null,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(b.graph.io, host, candidate, options)) {
        .native, .rosetta => true,
        // Reachable only for an executor the switches above enabled, each of
        // which `Run` gates on the same switch and nothing else.
        .wine, .wasmtime, .darling => true,
        // Not a yes on its own: `Run` fails a cross GNU libc target given no
        // `--libc-runtimes`, so this step installs it instead.
        .qemu => !(candidate.isGnuLibC() and b.libc_runtimes_dir == null),
        // Same OS and CPU with no dynamic linker to load, or an architecture and
        // system this build has no enabled executor for.
        .bad_dl, .bad_os_or_cpu => false,
    };
}

// ---------------------------------------------------------------------------
// Installed tree
// ---------------------------------------------------------------------------

/// Writes `lib/pkgconfig/libjpeg.pc` and installs it.
///
/// Upstream ships the template, `src/release/libjpeg.pc.in`, and CMake
/// substitutes its five `@VAR@`s. Every one is named here with the line it comes
/// from:
///
///   * `@CMAKE_INSTALL_PREFIX@` (`:1`) and `:2`, which sets `exec_prefix` to the
///     same value. Substituted as `${pcfiledir}/../..`, which is correct wherever
///     the file is installed, including a Nix store path that is only known at
///     build time.
///   * `@CMAKE_INSTALL_FULL_LIBDIR@` (`:3`) is `${prefix}/lib`, matching the
///     `lib/` this build installs into.
///   * `@CMAKE_INSTALL_FULL_INCLUDEDIR@` (`:4`) is `${prefix}/include`.
///
/// The four static fields are upstream's own text, unchanged: `Name: libjpeg`
/// and `Description:` (`:6-7`), `Version:` (`:8`, `src/CMakeLists.txt:17`),
/// `Libs: -L${libdir} -ljpeg` (`:9`) and `Cflags: -I${includedir}` (`:10`).
///
/// The description says "SIMD-accelerated" and that wording is **preserved
/// rather than rewritten**, because it identifies the *library*: upstream's own
/// README makes the same claim for every configuration upstream ships, including
/// the non-SIMD one this package builds. Rewriting it would make the field
/// describe something other than the library it names. What this package built is
/// stated in the `.pc`'s own header comment, in `README.md`, and in the
/// configure-time summary `zig build` prints.
///
/// No `Libs.private` is added. The library needs libc and nothing else, so a
/// static consumer needs no second `-l`, and upstream's template has no such
/// line either.
fn add_pkg_config(b: *std.Build) void {
    const files = b.addWriteFiles();
    // The returned step is bound to the install step. `addInstallFileWithDir`
    // *creates* a `Step.InstallFile` and nothing more - dropping the return value
    // builds nothing and installs nothing, and the omission is silent: the step
    // exists, it is simply never in the graph, so an install missing its `.pc`
    // would still report success.
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

/// Installs the carried licence texts under `share/licenses/libjpeg-turbo/`.
///
/// A private repository removes no upstream obligation, and libjpeg-turbo is
/// dual-licensed: the IJG License covers the libjpeg API library
/// (`src/LICENSE.md:6-11`, full text `src/README.ijg:126-157`) and the
/// Modified (3-clause) BSD License covers TurboJPEG, libspng and the build and
/// test system (`src/LICENSE.md:13-24`, text `src/LICENSE.md:119-147`). A binary
/// distributor still owes the acknowledgement at `src/LICENSE.md:88-89`, and
/// installing both texts under their own names is what lets that obligation be
/// discharged from the install alone.
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

// ---------------------------------------------------------------------------
// Refusals, matrix bookkeeping and helpers
// ---------------------------------------------------------------------------

/// The reason this package refuses `os`, or null when it refuses nothing.
///
/// **Every entry is empty today, and the emptiness has to stay earned.** No
/// platform limit has been observed for this package, because no gate has been
/// run (`FORK-NOTES.md` entry 5). `wasm32-wasi` is **unknown**, not refused and
/// not working; promoting it to either answer needs a run that printed the
/// answer.
fn refusalFor(os: std.Target.Os.Tag) ?[]const u8 {
    switch (os) {
        // Every target in `check_targets` is accepted, on the record that none
        // of them has been attempted. This is deliberately a function rather
        // than an empty list so that adding a refusal has somewhere to go.
        else => return null,
    }
}

/// The refusal message for one OS, printed before any compiler runs.
fn refuseTarget(_: *std.Build, target: std.Build.ResolvedTarget) noreturn {
    const reason = refusalFor(target.result.os.tag) orelse
        unreachable; // called only when refusalFor answered non-null
    std.log.err("libjpeg-turbo: refusing to build for {s}: {s}", .{
        @tagName(target.result.os.tag),
        reason,
    });
    @panic("libjpeg-turbo: refusing to build for this target");
}

/// Fails the build if the two matrix lists could describe different targets.
///
/// Two lists, one decision function, checked before any graph is configured. A
/// target cannot be quietly wrong in either direction: a refusal that is not in
/// `refused_check_targets` has nowhere to be recorded, and a row in
/// `refused_check_targets` that `refusalFor` does not refuse would be dropped
/// without a message, which is exactly the "quietly dropped target" this
/// workspace forbids.
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

/// The linkage this target can actually carry.
///
/// `-Dlinkage=dynamic` is not available everywhere. `wasm32-wasi` has no
/// shared-object form this build can deliver: a WASI module is not a dynamic
/// library, and asking for one would produce an artifact no consumer could
/// `dlopen` and no `libjpeg.so.62.4.0` filename. This resolves the difference
/// once, and `build` prints both the requested and the delivered form, so the
/// difference is stated rather than silent. Every other target in
/// `check_targets` carries a shared object normally.
///
/// `FORK-NOTES.md` entry 5 records the open question for `wasm32-wasi` - whether
/// the 98 units and `jinclude.h:36-39`'s four standard headers even compile for
/// it. That question is untouched here; this function only answers what delivery
/// would be **if** they do.
fn deliveredLinkage(target: std.Build.ResolvedTarget, requested: std.builtin.LinkMode) std.builtin.LinkMode {
    return switch (requested) {
        .static => .static,
        .dynamic => switch (target.result.os.tag) {
            .wasi => .static,
            else => .dynamic,
        },
    };
}

/// The name one artifact carries in this build graph.
///
/// The published graph installs `libjpeg.a` / `libjpeg.so.62.4.0`, which is
/// upstream's name, and a check graph installs nothing, so its artifacts carry
/// the target triple instead: six targets in one build graph would otherwise
/// produce six steps called `jpeg`, which makes `--summary all` impossible to
/// read.
fn artifactLabel(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    public: bool,
) []const u8 {
    if (public) return artifact_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}-{s}", .{ artifact_name, lib_name, triple });
}