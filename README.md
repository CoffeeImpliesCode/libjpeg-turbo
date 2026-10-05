# libjpeg-turbo

libjpeg-turbo 3.2.0 — the libjpeg API JPEG codec — as a standalone Zig SDK
built from the official release tarball with Zig 0.16.0: no CMake, no
autotools, no build-time download, no system library, and no sibling
dependency. The library links libc and nothing else.

Read the **first section before anything else**. This package ships the
**portable C configuration**: no SIMD is compiled, on any target, and the
reasons are given there rather than in a footnote.

`STATUS`: every claim below about bytes, sources and configuration is
`SOURCE-CONFIRMED`, read out of a file in this repository. **No gate has been
run for this package.** Nothing here has been built, tested, smoked or
cross-compiled, and no cell in any table below is a pass. See
[What has not been run](#what-has-not-been-run).

## Native-source deviations

**None.** All 613 files under `src/` are byte-identical to
`libjpeg-turbo-3.2.0.tar.gz`, verified with `diff -rq` against the extracted
tarball and recorded file by file in [`UPSTREAM.sha256`](UPSTREAM.sha256). No
portability patch, no reformatting, no comment edit, no renamed file, no added
file.

`README.upstream.md` is a byte copy of upstream's own `src/README.md`, and
`tools/check-provenance.sh` re-runs that `cmp` so the two cannot drift.

## Native-build deviations

What the compiled package does that upstream's CMake build does not. Each is a
fork decision with a stated reason; none of them changes an algorithm.

### 1. No SIMD — the portable C configuration only

**This is the deviation a reader must see first.** `WITH_SIMD` is not defined,
nothing under `src/simd/` is compiled, and `SIMD_ARCHITECTURE` is `NONE`. This
package **does not deliver libjpeg-turbo's full-speed x86 configuration and
makes no parity claim with it.** Upstream's own README states that on systems
with common CPU architectures libjpeg-turbo is generally 2–6× as fast as libjpeg
(`src/README.md:4-10`); that advantage is **not available here**.

This is upstream's own fallback configuration, not an improvisation:

* `src/simd/CMakeLists.txt:1-10` defines `simd_fail`, which — because
  `REQUIRE_SIMD` defaults **FALSE** (`src/CMakeLists.txt:252-255`) — emits
  *"Performance will suffer"*, sets `WITH_SIMD 0` and `SIMD_ARCHITECTURE NONE`,
  and returns. `WITH_SIMD` defaults **ON** upstream
  (`src/CMakeLists.txt:281-283`).
* `src/simd/CMakeLists.txt:53-61` calls it with *"SIMD extensions disabled:
  could not find NASM compiler"* and returns.

So upstream itself produces exactly this configuration when the assembler is
missing, and it ships and supports it.

**Why x86 SIMD cannot be here.** x86 and x86-64 SIMD is **NASM assembly**:
56 `.asm` files under `src/simd/i386/` and 35 under `src/simd/x86_64/`,
selected at `src/simd/CMakeLists.txt:137` and `:148` and assembled through
`enable_language(ASM_NASM)` at `:61`. Zig 0.16.0's toolchain contains no NASM,
and the clang it does contain does not accept NASM syntax. Those 91 files
cannot be assembled from this build graph at all.

**The other families are not assembly, and saying otherwise would be wrong.**
ARM NEON (`src/simd/arm/`, `aarch32/`, `aarch64/`), PowerPC
(`src/simd/powerpc/`), RISC-V RVV (`src/simd/riscv64/`) and MIPS MSA /
LoongArch LSX (`src/simd/mips64/`) are **plain C with compiler intrinsics** —
16 `.c` units each — plus exactly one GNU-as `.S` for RISC-V
(`src/simd/riscv64/jsimdcpu.S`, via `enable_language(ASM)` at
`src/simd/CMakeLists.txt:477`). Those *are* compilable by a Zig build. They are
excluded for a different, stated reason: CMake selects the per-architecture
source list by `CPU_TYPE` and **generates** `simd/arm/neon-compat.h` from
capability probes it runs itself (`src/simd/CMakeLists.txt:349`, probes at
`:289-333`), plus `getauxval`/`elf_aux_info` symbol probes (`:361-372`).
Reproducing that selection here would mean writing those probes ourselves —
**inventing configuration rather than porting it.**

Every `jsimd_*` call site is behind `#ifdef WITH_SIMD`, so the exclusion is a
configuration choice and not a source edit. The complete table of guards and
call sites is in [`UPSTREAM.md`](UPSTREAM.md), "Every `jsimd_*` call site is
behind `#ifdef WITH_SIMD`".

**No silent substitution.** `build.zig` exposes a `-Dsimd` option whose **only
accepted value is `c`** and refuses anything else with the reason printed; the
configure-time summary states which configuration was built; and this README,
`UPSTREAM.md` and `FORK-NOTES.md` say the same thing in the same words.

### 2. The command-line tools are not built

`cjpeg`, `djpeg` and `jpegtran` are **not** in this package. Upstream gates them
behind a separate `WITH_TOOLS` option, and `src/CMakeLists.txt:884-927` shows
what they pull in: `cjpeg` needs `rdbmp.c`, `rdgif.c`, three `wrapper/rdpng-*.c`,
three `wrapper/rdppm-*.c`, `rdtarga.c` **plus the bundled zlib and the bundled
libspng**; `CDJPEG_COMPILE_FLAGS` at `:882-883` turns on `-DBMP_SUPPORTED
-DGIF_SUPPORTED -DPNG_SUPPORTED -DSPNG_STATIC -DPPM_SUPPORTED
-DTARGA_SUPPORTED`. Taking them would mean vendoring a second zlib and a PNG
decoder into the closure, or adding dependencies this package otherwise does not
have.

**The library is the deliverable; the tools are not part of it.**

### 3. Three headers are generated, not checked in

`jconfig.h`, `jconfigint.h` and `jversion.h` are produced from upstream's own
`.in` templates by `tools/jconfig.zig`, per target, into the build cache — with
upstream's CMake `@VAR@` and `#cmakedefine` rules. This is a deterministic build
step from a host-target generator (AGENTS.md §4), never a hand-written
stand-in, and `@SIZE_T@` comes from the **target being built**, not from the
machine running the generator (AGENTS.md §5).

All three are required: `src/src/jinclude.h:25-26` includes `jconfig.h` and
`jconfigint.h` by bare name, and `src/src/jerror.c:27` includes `jversion.h`
while `jerror.c` is a library unit. The generated directory is placed **before**
`src/src/` on every include line, which is why the bare-name includes resolve.
Full substitution table in [`UPSTREAM.md`](UPSTREAM.md), "Generated inputs".

### 4. Options upstream turns on by default, off here

| Option | Upstream | Here | Effect |
|---|---|---|---|
| `WITH_ARITH_ENC` | `TRUE` (`:260-263`) | off | `jcarith.c` excluded |
| `WITH_ARITH_DEC` | `TRUE` (`:256-259`) | off | `jdarith.c` excluded |
| `WITH_PROFILE` | `FALSE` | off | `tjutil.c` excluded |
| `WITH_SIMD` | `TRUE` (`:281-283`) | off | all of `src/simd/` excluded |
| `WITH_TOOLS` | `TRUE` | off | `cjpeg`, `djpeg`, `jpegtran` excluded |
| `WITH_TESTS` | `TRUE` | off | `example`, `jcstest`, `bmpsizetest` not built |
| `WITH_TURBOJPEG` | `TRUE` | off | `turbojpeg*.c` excluded |
| `WITH_JPEG7` / `WITH_JPEG8` | `FALSE` | `FALSE` (upstream's own default) | libjpeg v6b API/ABI |

### 5. Upstream's own test material ships but does not run

`src/doc/`, `src/testimages/`, `src/test/`, `src/fuzz/`, the `tj*` and
`strtest.c` sources — all present, all digested, none compiled, none deleted.
**Upstream's test suites are not deleted by this fork.** This SDK's own tests
are independent known answers; see README.zig.md.

### 6. A hand-written pkg-config file, and the name `jpeg`

The C artifact is named `jpeg`, as upstream names it
(`src/sharedlib/CMakeLists.txt:55` `add_library(jpeg SHARED ...)`,
`src/CMakeLists.txt:770` `OUTPUT_NAME jpeg`), so `dep.artifact("jpeg")` resolves
and Zig emits `libjpeg.a` / `libjpeg.so.62.4.0` with soname `libjpeg.so.62` —
the soname upstream computes at `src/sharedlib/CMakeLists.txt:58-59` from
`SO_MAJOR_VERSION` 62, `SO_AGE` 4, `SO_MINOR_VERSION` 0
(`src/CMakeLists.txt:373-397`, `:408-413`).

The pkg-config file is `libjpeg.pc`, with `Name: libjpeg`,
`Libs: -L${libdir} -ljpeg` and `Cflags: -I${includedir}` — the same fields as
upstream's own template at `src/release/libjpeg.pc.in:6-10`, generated by
`build.zig` rather than by CMake's `configure_file`.

### 7. One consumer requirement upstream documents in prose

`src/src/jpeglib.h:21-29` states that the header deliberately does **not**
include `<stdio.h>` even though it uses `FILE` and `size_t`, and that calling
programs must *"include system headers that define at least the typedefs `FILE`
and `size_t`"* before including it. That requirement is upstream's and it is
unchanged here: a C consumer includes `<stdio.h>` before `<jpeglib.h>`. See
README.zig.md.

### History of these deviations

The deviations above are the current state. [`CHANGELOG.md`](CHANGELOG.md)
numbers each one with the date it landed, and [`FORK-NOTES.md`](FORK-NOTES.md)
records each in the condition / symptom / fix / targets-bound shape with its
boundary named.

## Current support matrix

### What has been observed

The **53-platform `cross-test` matrix has been run**. Nothing else has: the
`zig build` / `test` / `smoke` / `check` gates, the installed-C check, the
runtime route, the consumer and `tools/check-provenance.sh` have not been run
by this worker, and every row below that is not about the matrix is still a
**stated intention** or a **source-confirmed fact**, never a result.

| | Status |
|---|---|
| 53-platform `cross-test` matrix | `OBSERVED` — exit **1**, 53 targets, 20 `pass` / 19 `build_only` / 14 `build_fail` / 0 `refused` / 0 `runtime_fail`; see below and FORK-NOTES.md entry 10 |
| Native build, Debug | `PENDING-VERIFICATION` — not run by this worker |
| Native build, ReleaseSafe | `PENDING-VERIFICATION` — not run by this worker |
| `zig build test` | `PENDING-VERIFICATION` — not run by this worker |
| `zig build smoke` | `PENDING-VERIFICATION` — not run by this worker |
| `zig build check` | `PENDING-VERIFICATION` — not run by this worker |
| Installed C surface + `libjpeg.pc` | `PENDING-VERIFICATION` — never run |
| `-Druntime=true` route | `PENDING-VERIFICATION` — never run |
| `consumer/` in both linkages | `PENDING-VERIFICATION` — never run |
| `tools/check-provenance.sh` | `PENDING-VERIFICATION` — not run; running it is itself a gate |

### The observed 53-platform matrix

Run id `20261005-191619-21172-4913`, harness **exit code 1**, 1610 s,
`bookkeeping_failure false`, no per-phase timeout. 300 tests executed — 15 on
each of the 20 executing cells, natively for `x86_64-linux` and under QEMU user
mode for the other 19.

| Class | Cells | Notes |
|---|---|---|
| `pass` | 20 | built **and** executed, 15 tests each |
| `build_only` | 19 | built, **never executed**; no runner on this host |
| `build_fail` | 14 | all BSD; all 14 fail in `translate-c`, none in this tree |
| `refused` | 0 | this package refuses nothing; see FORK-NOTES.md entry 10 |
| `runtime_fail` | 0 | no cell that built also failed to run |

The **14 failures are a Zig 0.16.0 aro limitation**, not a defect in this
package: `compile lib jpeg` **succeeded** on all 14, so the 98-unit C closure
compiles for every one of them. All 14 reproduce from a translation unit holding
no libjpeg-turbo source, and the same source translates cleanly under
`zig cc` (clang). Causes, named with file and line, are in FORK-NOTES.md
entry 10: NetBSD `_Pragma` (9 cells), OpenBSD `size_t` (3), OpenBSD mips64
endianness (2).

### The six compile targets

These are the targets `zig build check` is specified against. **`check` has not
been run**, so the middle column states an intention. The right-hand column
records what the matrix observed for the same target through the `test` step.

| Target | Intended `zig build check` | Native test run possible? | `check` status | Observed in the matrix (`test` step) |
|---|---|---|---|---|
| `x86_64-linux-gnu` | yes | yes, natively | `PENDING-VERIFICATION` | `pass` — 15 tests, native |
| `aarch64-linux-gnu` | yes | under QEMU user mode | `PENDING-VERIFICATION` | `pass` — 15 tests under QEMU |
| `aarch64-macos-none` | yes | on a macOS host only | `PENDING-VERIFICATION` | `build_only` (`aarch64-macos`, `build_only` — no macOS host) |
| `x86_64-windows-gnu` | yes | under Wine | `PENDING-VERIFICATION` | `build_only` (`x86_64-windows` — no Wine) |
| `riscv64-linux-gnu` | yes | under QEMU user mode | `PENDING-VERIFICATION` | `pass` — 15 tests under QEMU |
| `wasm32-wasi` | yes | under wasmtime | `PENDING-VERIFICATION` | **`build_only`** — see below |

**`wasm32-wasi` builds.** It is **not** refused and does not fail: the matrix
compiled the whole 98-unit archive (`compile lib jpeg Debug wasm32-wasi
success 2m`), translated the facade, and linked the test binary. The run step
was **skipped** because this host has no wasmtime, so the cell is
`build_only` — compiled, never executed, never a pass. FORK-NOTES.md entry 5
recorded this target as **unknown** with no run behind it; that is now
superseded by this observation for the `test` step. `zig build check` for
`wasm32-wasi` is still unobserved, and the package's own refusal machinery
(`build.zig:415`, `build.zig:1506-1513`) refuses nothing, so **no cell in the
matrix was refused**.

The 19 `build_only` cells are missing a runtime on this host, not a property of
this package. Adding a runner would turn one into an executable result, which
is a different claim from this one.

`cross-test` over the full published 53-platform matrix is a host-local gate
run from the package root against `cross-test.profile.sh`. It is **not** covered
by anything in `.github/workflows/verify.yml`, and a foreign target with no
executor is reported as `build_only` — compiled, never executed, never counted
as a pass.

### The gates the driver must run

Per AGENTS.md §6, with the real Zig 0.16.0 from the approved cache and
`--summary all`, `-j8` and a cache directory on approved scratch:

```sh
zig build                       # the library, both linkages
zig build test                  # Debug
zig build test -Doptimize=ReleaseSafe
zig build smoke                 # both linkages
zig build check                 # every public entry point, six targets
tools/check-provenance.sh       # bytes, file set, notices, fixture digests
cd consumer && zig build run    # both linkages
```

The behavioural proof each gate still has to produce is described in
README.zig.md, "What the tests prove".

### Provenance, observed by reading files

These are not gates; they are reads of bytes, and they are what the provenance
records rest on.

* `README.upstream.md` was produced with `cp src/README.md` and confirmed with
  `cmp`, which reported no difference. 17722 bytes, sha256
  `a44ba17ac66c57edaf0ea7c6e4b31358f08322c780e4e6af092082abb3e20793`.
* `UPSTREAM.sha256` records 613 files, 9246273 bytes, and `find src -type f`
  returns 613 paths.

### The fixtures and their exact decoded answers

Four fixtures, written by `tools/make-fixtures.py` from ITU-T T.81 using **no
image library**. Their expected decoded pixels are hand-computed, so the test
compares the decoder against arithmetic rather than against itself.

| File | sha256 | Bytes | Decodes to, exactly |
|---|---|---:|---|
| `fixtures/grey8x8-200.jpg` | `f7f10aee901395fe1a12f424cd8d91f9bf2e181642cf0ab069b406d938cb9e2d` | 549 | every sample exactly **200** |
| `fixtures/grey16x16-halves.jpg` | `b2e2490ff88768780f7e48f1739d1a608dfc7b5c17a54c2665db29db8b51f4bf` | 555 | rows 0–7 exactly **0**, rows 8–15 exactly **255** |
| `fixtures/rgb8x8-grey64.jpg` | `0704223b42ce860b9a28892da837fa160de3603ebd6cc8cd385dbb8a71f18684` | 629 | every pixel exactly **(64, 64, 64)** |
| `fixtures/rgb8x8-grey200.jpg` | `e31f0659abba47da10e4600fde1a3da25afdcacee2f1dde5029aeddade972b98` | 629 | every pixel exactly **(200, 200, 200)** |

Three facts produce all four: both quantisation tables are all ones, so
quantisation is exact; every block is flat, so its only coefficient is
`F(0,0) = 8·(sample − 128)` and the inverse DCT returns that divided by eight
before the level shift; and the JFIF luma constants `19595 + 38470 + 7471 =
2^16` exactly, so `R = G = B = v` gives `Y = v` and `Cb = Cr = 128`, whose
inverse is the identity. The full derivation is in
[`UPSTREAM.md`](UPSTREAM.md), "The expected decoded samples, spelled out".

### What has not been run

Stated once, plainly, because everything above depends on it:

* **No `zig build` of any kind has been run.** Nothing in this package is known
  to compile.
* **No test has been executed.** The expectations above are written down; none
  has been compared against a decoder.
* **No target other than the ones named above has been considered**, and no
  cross target has been attempted.
* **`.fingerprint` is absent from `build.zig.zon`** and no value has been
  invented for it.
* **No lock file exists** — `flake.lock` and `devenv.lock` are absent, and
  neither belongs to this fork's tooling.

## Consumption

Full detail is in [`README.zig.md`](README.zig.md). In brief:

| From | Route |
|---|---|
| Zig, typed | `dep.module("libjpeg_turbo")`, then `@import("libjpeg_turbo")` |
| Zig, raw C | `pub const c` — the translated `jpeglib.h`, `jmorecfg.h`, `jerror.h` |
| Zig, runtime-loaded | `-Druntime=true`, one process-lifetime table |
| C | `dep.artifact("jpeg")` → `libjpeg.a` / `libjpeg.so.62.4.0`, plus `include/*.h` and `libjpeg.pc` |
| Nix | `nix build`, or `devenv shell` for the development shell |

Installed layout:

```
include/jconfig.h  include/jerror.h  include/jmorecfg.h  include/jpeglib.h
lib/libjpeg.a  |  lib/libjpeg.so.62.4.0  +  lib/libjpeg.so.62 -> libjpeg.so.62.4.0
lib/pkgconfig/libjpeg.pc
share/licenses/libjpeg-turbo/
```

Four public headers, as upstream installs them at `src/CMakeLists.txt:2065-2069`
— `jconfig.h` (generated), `jerror.h`, `jmorecfg.h`, `jpeglib.h`.

## Commands

```sh
zig build                       # libjpeg.a, headers, libjpeg.pc
zig build -Dlinkage=dynamic     # libjpeg.so.62.4.0
zig build test                  # behavioural tests (Debug)
zig build test -Doptimize=ReleaseSafe
zig build smoke                 # deterministic example
zig build check                 # compile-only, six targets
zig build -Dsimd=c              # the only accepted -Dsimd value
cd consumer && zig build run    # the package as a dependent sees it
tools/check-provenance.sh       # bytes, file set, licences, fixture digests
python3 tools/make-fixtures.py fixtures   # regenerate the four fixtures
```

`-Dsimd` accepts **`c` and nothing else**. Any other value is refused with the
reason from UPSTREAM.md rather than ignored.

## Licence

libjpeg-turbo is **dual-licensed**, and one label would be wrong.

* The **IJG (Independent JPEG Group) License** applies to the libjpeg API
  library and associated programs, including code inherited from libjpeg and
  modifications to it (`src/LICENSE.md:6-11`; full text
  `src/README.ijg:126-157`).
* The **Modified (3-clause) BSD License** applies to the TurboJPEG API library
  and associated programs, libspng, and the build/test system
  (`src/LICENSE.md:13-24`; text `src/LICENSE.md:119-147`).
* The **zlib** term covers the SIMD sources and the bundled zlib, subsumed by
  the IJG terms in the libjpeg/cjpeg/djpeg context (`src/LICENSE.md:37-40`);
  **PNG Reference Library License v2** and **BSD-2-Clause** cover parts of
  libspng (`src/LICENSE.md:42-50`).
* `src/simd/jsimd.h:1-21` and `src/simd/jsimd.c:1-31` carry their own
  **multi-author BSD-2-style** notice — a fourth grant that upstream's own
  roll-up does not enumerate.

The per-file inventory is [`NOTICE.md`](NOTICE.md). The grant for this fork's
own files is [`FORK-LICENSE.md`](FORK-LICENSE.md): **MIT**, owner-authorized,
and no upstream source was copied into any fork-authored file.

A consumer shipping a binary still owes the IJG acknowledgement: *"This
software is based in part on the work of the Independent JPEG Group"*
(`src/LICENSE.md:88-89`). The installed tree ships `README.ijg` and
`src/LICENSE.md` so that obligation can be discharged.

## Upstream README, verbatim

Upstream's own README is reproduced in full, at the end, because that is where a
reader should find it. The same 17722 bytes are preserved as
[`README.upstream.md`](README.upstream.md), and `src/README.md` inside the
vendored tree is the imported original. `tools/check-provenance.sh` fails if
either ever differs from the other.

---

Background
==========

libjpeg-turbo is a JPEG image codec that uses SIMD instructions to accelerate
baseline and progressive JPEG compression and decompression on systems with
common CPU architectures.  On such systems, libjpeg-turbo is generally 2-6x as
fast as libjpeg, all else being equal.  On other types of systems,
libjpeg-turbo can still outperform libjpeg by a significant amount, by virtue
of its highly-optimized Huffman coding routines.  In many cases, the
performance of libjpeg-turbo rivals that of proprietary high-speed JPEG codecs.

libjpeg-turbo implements both the traditional libjpeg API as well as the less
powerful but more straightforward TurboJPEG API.  libjpeg-turbo also features
colorspace extensions that allow it to compress from/decompress to 32-bit and
big-endian pixel buffers (RGBX, XBGR, etc.)

libjpeg-turbo was originally based on libjpeg/SIMD, an MMX-accelerated
derivative of libjpeg v6b developed by Miyasaka Masaru.  The TigerVNC and
VirtualGL projects made numerous enhancements to the codec in 2009, and in
early 2010, libjpeg-turbo spun off into an independent project, with the goal
of making high-speed JPEG compression/decompression technology available to a
broader range of users and developers.  libjpeg-turbo is an ISO/IEC and ITU-T
reference implementation of the JPEG standard.

More information about libjpeg-turbo can be found at
<https://libjpeg-turbo.org>.


Funding
=======

libjpeg-turbo is an independent open source project, but we rely on patronage
and funded development in order to maintain that independence.  The easiest way
to ensure that libjpeg-turbo remains community-focused and free of any one
organization's agenda is to
[sponsor our project through GitHub](https://github.com/sponsors/libjpeg-turbo).
All sponsorship money goes directly toward funding the labor necessary to
maintain libjpeg-turbo, support the user community, and implement bug fixes and
strategically important features.

[![Sponsor libjpeg-turbo](https://img.shields.io/github/sponsors/libjpeg-turbo?label=Sponsor&logo=GitHub)](https://github.com/sponsors/libjpeg-turbo)


License
=======

libjpeg-turbo is covered by three compatible BSD-style open source licenses.
Refer to [LICENSE.md](LICENSE.md) for a roll-up of license terms.


Building libjpeg-turbo
======================

Refer to [BUILDING.md](BUILDING.md) for complete instructions.


Using libjpeg-turbo
===================

libjpeg-turbo includes two APIs that can be used to compress and decompress
JPEG images:

- **TurboJPEG API**<br>
  This API provides an easy-to-use interface for compressing and decompressing
  JPEG images in memory.  It also provides some functionality that would not be
  straightforward to achieve using the underlying libjpeg API, such as
  generating planar YUV images and performing multiple simultaneous lossless
  transforms on an image.  The TurboJPEG API is recommended for first-time
  users of libjpeg-turbo.  Refer to [tjcomp.c](src/tjcomp.c),
  [tjdecomp.c](src/tjdecomp.c), [tjtran.c](src/tjtran.c),
  [TJComp.java](jna/TJComp.java), [TJDecomp.java](jna/TJDecomp.java), and
  [TJTran.java](jna/TJTran.java) for examples of its usage and to
  <https://libjpeg-turbo.org/Documentation/Documentation> for API
  documentation.

- **libjpeg API**<br>
  This is the de facto industry-standard API for compressing and decompressing
  JPEG images.  It is more difficult to use than the TurboJPEG API but also
  more powerful.  The libjpeg API implementation in libjpeg-turbo is both
  API/ABI-compatible and mathematically compatible with libjpeg v6b.  It can
  also optionally be configured to be API/ABI-compatible with libjpeg v7 and v8
  (see below.)  Refer to [cjpeg.c](src/cjpeg.c) and [djpeg.c](src/djpeg.c) for
  examples of its usage and to [libjpeg.txt](doc/libjpeg.txt) for API
  documentation.

There is no significant performance advantage to either API when both are used
to perform similar operations.

Colorspace Extensions
---------------------

libjpeg-turbo includes extensions that allow JPEG images to be compressed
directly from (and decompressed directly to) buffers that use BGR, BGRX,
RGBX, XBGR, and XRGB pixel ordering.  This is implemented with ten new
colorspace constants:

    JCS_EXT_RGB   /* red/green/blue */
    JCS_EXT_RGBX  /* red/green/blue/x */
    JCS_EXT_BGR   /* blue/green/red */
    JCS_EXT_BGRX  /* blue/green/red/x */
    JCS_EXT_XBGR  /* x/blue/green/red */
    JCS_EXT_XRGB  /* x/red/green/blue */
    JCS_EXT_RGBA  /* red/green/blue/alpha */
    JCS_EXT_BGRA  /* blue/green/red/alpha */
    JCS_EXT_ABGR  /* alpha/blue/green/red */
    JCS_EXT_ARGB  /* alpha/red/green/blue */

Setting `cinfo.in_color_space` (compression) or `cinfo.out_color_space`
(decompression) to one of these values will cause libjpeg-turbo to read the
red, green, and blue values from (or write them to) the appropriate position in
the pixel when compressing from/decompressing to an RGB buffer.

Your application can check for the existence of these extensions at compile
time with:

    #ifdef JCS_EXTENSIONS

At run time, attempting to use these extensions with a libjpeg implementation
that does not support them will result in a "Bogus input colorspace" error.
Applications can trap this error in order to test whether run-time support is
available for the colorspace extensions.

When using the RGBX, BGRX, XBGR, and XRGB colorspaces during decompression, the
X byte is undefined, and in order to ensure the best performance, libjpeg-turbo
can set that byte to whatever value it wishes.  If an application expects the X
byte to be used as an alpha channel, then it should specify `JCS_EXT_RGBA`,
`JCS_EXT_BGRA`, `JCS_EXT_ABGR`, or `JCS_EXT_ARGB`.  When these colorspace
constants are used, the X byte is guaranteed to be 0xFF, which is interpreted
as opaque.

Your application can check for the existence of the alpha channel colorspace
extensions at compile time with:

    #ifdef JCS_ALPHA_EXTENSIONS

[jcstest.c](src/jcstest.c), located in the libjpeg-turbo source tree,
demonstrates how to check for the existence of the colorspace extensions at
compile time and run time.

libjpeg v7 and v8 API/ABI Emulation
-----------------------------------

With libjpeg v7 and v8, new features were added that necessitated extending the
compression and decompression structures.  Unfortunately, due to the exposed
nature of those structures, extending them also necessitated breaking backward
ABI compatibility with previous libjpeg releases.  Thus, programs that were
built to use libjpeg v7 or v8 did not work with libjpeg-turbo, since it is
based on the libjpeg v6b code base.  Although libjpeg v7 and v8 are not
as widely used as v6b, enough programs (including a few Linux distros) made
the switch that there was a demand to emulate the libjpeg v7 and v8 ABIs
in libjpeg-turbo.  It should be noted, however, that this feature was added
primarily so that applications that had already been compiled to use libjpeg
v7+ could take advantage of accelerated baseline JPEG encoding/decoding
without recompiling.  libjpeg-turbo does not claim to support all of the
libjpeg v7+ features, nor to produce identical output to libjpeg v7+ in all
cases (see below.)

By passing an argument of `-DWITH_JPEG7=1` or `-DWITH_JPEG8=1` to `cmake`, you
can build a version of libjpeg-turbo that emulates the libjpeg v7 or v8 ABI, so
that programs that are built against libjpeg v7 or v8 can be run with
libjpeg-turbo.  The following section describes which libjpeg v7+ features are
supported and which aren't.

### Support for libjpeg v7 and v8 Features

#### Fully supported

- **libjpeg API: IDCT scaling extensions in decompressor**<br>
  libjpeg-turbo supports IDCT scaling with scaling factors of 1/8, 1/4, 3/8,
  1/2, 5/8, 3/4, 7/8, 9/8, 5/4, 11/8, 3/2, 13/8, 7/4, 15/8, and 2/1 (only 1/4
  and 1/2 are SIMD-accelerated.)

- **libjpeg API: Arithmetic coding**

- **libjpeg API: In-memory source and destination managers**<br>
  See notes below.

- **cjpeg: Separate quality settings for luminance and chrominance**<br>
  Note that the libpjeg v7+ API was extended to accommodate this feature only
  for convenience purposes.  It has always been possible to implement this
  feature with libjpeg v6b (see rdswitch.c for an example.)

- **cjpeg: 32-bit BMP support**

- **cjpeg: `-rgb` option**

- **jpegtran: Lossless cropping**

- **jpegtran: `-perfect` option**

- **jpegtran: Forcing width/height when performing lossless crop**

- **rdjpgcom: `-raw` option**

- **rdjpgcom: Locale awareness**


#### Not supported

NOTE:  As of this writing, extensive research has been conducted into the
usefulness of DCT scaling as a means of data reduction and SmartScale as a
means of quality improvement.  Readers are invited to peruse the research at
<https://libjpeg-turbo.org/About/SmartScale> and draw their own conclusions,
but it is the general belief of our project that these features have not
demonstrated sufficient usefulness to justify inclusion in libjpeg-turbo.

- **libjpeg API: DCT scaling in compressor**<br>
  `cinfo.scale_num` and `cinfo.scale_denom` are silently ignored.
  There is no technical reason why DCT scaling could not be supported when
  emulating the libjpeg v7+ API/ABI, but without the SmartScale extension (see
  below), only scaling factors of 1/2, 8/15, 4/7, 8/13, 2/3, 8/11, 4/5, and
  8/9 would be available, which is of limited usefulness.

- **libjpeg API: SmartScale**<br>
  `cinfo.block_size` is silently ignored.
  SmartScale is an extension to the JPEG format that allows for DCT block
  sizes other than 8x8.  Providing support for this new format would be
  feasible (particularly without full acceleration.)  However, until/unless
  the format becomes either an official industry standard or, at minimum, an
  accepted solution in the community, we are hesitant to implement it, as
  there is no sense of whether or how it might change in the future.  It is
  our belief that SmartScale has not demonstrated sufficient usefulness as a
  lossless format nor as a means of quality enhancement, and thus our primary
  interest in providing this feature would be as a means of supporting
  additional DCT scaling factors.

- **libjpeg API: Fancy downsampling in compressor**<br>
  `cinfo.do_fancy_downsampling` is silently ignored.
  This requires the DCT scaling feature, which is not supported.

- **jpegtran: Scaling**<br>
  This requires both the DCT scaling and SmartScale features, which are not
  supported.

- **Lossless RGB JPEG files**<br>
  This requires the SmartScale feature, which is not supported.

### What About libjpeg v9?

libjpeg v9 introduced yet another field to the JPEG compression structure
(`color_transform`), thus making the ABI backward incompatible with that of
libjpeg v8.  This new field was introduced solely for the purpose of supporting
lossless SmartScale encoding.  Furthermore, there was actually no reason to
extend the API in this manner, as the color transform could have just as easily
been activated by way of a new JPEG colorspace constant, thus preserving
backward ABI compatibility.

Our research (see link above) has shown that lossless SmartScale does not
generally accomplish anything that can't already be accomplished better with
existing, standard lossless formats.  Therefore, at this time it is our belief
that there is not sufficient technical justification for software projects to
upgrade from libjpeg v8 to libjpeg v9, and thus there is not sufficient
technical justification for us to emulate the libjpeg v9 ABI.

In-Memory Source/Destination Managers
-------------------------------------

By default, libjpeg-turbo 1.3 and later includes the `jpeg_mem_src()` and
`jpeg_mem_dest()` functions, even when not emulating the libjpeg v8 API/ABI.
Previously, it was necessary to build libjpeg-turbo from source with libjpeg v8
API/ABI emulation in order to use the in-memory source/destination managers,
but several projects requested that those functions be included when emulating
the libjpeg v6b API/ABI as well.  This allows the use of those functions by
programs that need them, without breaking ABI compatibility for programs that
don't, and it allows those functions to be provided in the "official"
libjpeg-turbo binaries.

Note that, on most Un*x systems, the dynamic linker will not look for a
function in a library until that function is actually used.  Thus, if a program
is built against libjpeg-turbo 1.3+ and uses `jpeg_mem_src()` or
`jpeg_mem_dest()`, that program will not fail if run against an older version
of libjpeg-turbo or against libjpeg v7- until the program actually tries to
call `jpeg_mem_src()` or `jpeg_mem_dest()`.  Such is not the case on Windows.
If a program is built against the libjpeg-turbo 1.3+ DLL and uses
`jpeg_mem_src()` or `jpeg_mem_dest()`, then it must use the libjpeg-turbo 1.3+
DLL at run time.

Both cjpeg and djpeg have been extended to allow testing the in-memory
source/destination manager functions.  See their respective man pages for more
details.


Mathematical Compatibility
==========================

For the most part, libjpeg-turbo should produce identical output to libjpeg
v6b.  There are two exceptions:

1. When decompressing a JPEG image that uses 4:4:0 chrominance subsampling, the
outputs of libjpeg v6b and libjpeg-turbo can differ because libjpeg-turbo
implements a "fancy" (smooth) 4:4:0 upsampling algorithm and libjpeg did not.

2. When using the floating point DCT/IDCT, the outputs of libjpeg v6b and
libjpeg-turbo can differ for the following reasons:

    - The SSE/SSE2 floating point DCT implementation in libjpeg-turbo is ever
      so slightly more accurate than the implementation in libjpeg v6b, but not
      by any amount perceptible to human vision (generally in the range of 0.01
      to 0.08 dB gain in PNSR.)

    - When not using the SIMD extensions, libjpeg-turbo uses the more accurate
      (and slightly faster) floating point IDCT algorithm introduced in libjpeg
      v8a as opposed to the algorithm used in libjpeg v6b.  It should be noted,
      however, that this algorithm basically brings the accuracy of the
      floating point IDCT in line with the accuracy of the accurate integer
      IDCT.  The floating point DCT/IDCT algorithms are mainly a legacy
      feature, and they do not produce significantly more accuracy than the
      accurate integer algorithms.  (To put numbers on this, the typical
      difference in PNSR between the two algorithms is less than 0.10 dB,
      whereas changing the quality level by 1 in the upper range of the quality
      scale is typically more like a 1.0 dB difference.)

    - If the floating point algorithms in libjpeg-turbo are not implemented
      using SIMD instructions on a particular platform, then the accuracy of
      the floating point DCT/IDCT can depend on the compiler settings.

While libjpeg-turbo does emulate the libjpeg v8 API/ABI, under the hood it is
still using the same algorithms as libjpeg v6b, so there are several specific
cases in which libjpeg-turbo cannot be expected to produce the same output as
libjpeg v8:

- When decompressing using scaling factors of 1/2 and 1/4, because libjpeg v8
  implements those scaling algorithms differently than libjpeg v6b does, and
  libjpeg-turbo's SIMD extensions are based on the libjpeg v6b behavior.

- When using chrominance subsampling, because libjpeg v8 implements this
  with its DCT/IDCT scaling algorithms rather than with a separate
  downsampling/upsampling algorithm.  In our testing, the subsampled/upsampled
  output of libjpeg v8 is less accurate than that of libjpeg v6b for this
  reason.

- When decompressing using a scaling factor > 1 and merged (AKA "non-fancy" or
  "non-smooth") chrominance upsampling, because libjpeg v8 does not support
  merged upsampling with scaling factors > 1.


Performance Pitfalls
====================

Restart Markers
---------------

The optimized Huffman decoder in libjpeg-turbo does not handle restart markers
in a way that makes the rest of the libjpeg infrastructure happy, so it is
necessary to use the slow Huffman decoder when decompressing a JPEG image that
has restart markers.  This can cause the decompression performance to drop by
as much as 20%, but the performance will still be much greater than that of
libjpeg.  Many consumer packages, such as Photoshop, use restart markers when
generating JPEG images, so images generated by those programs will experience
this issue.

Fast Integer Forward DCT at High Quality Levels
-----------------------------------------------

The algorithm used by the SIMD-accelerated quantization function cannot produce
correct results whenever the fast integer forward DCT is used along with a JPEG
quality of 98-100.  Thus, libjpeg-turbo must use the non-SIMD quantization
function in those cases.  This causes performance to drop by as much as 40%.
It is therefore strongly advised that you use the accurate integer forward DCT
whenever encoding images with a JPEG quality of 98 or higher.


Memory Debugger Pitfalls
========================

Valgrind and Memory Sanitizer (MSan) can generate false positives
(specifically, incorrect reports of uninitialized memory accesses) when used
with libjpeg-turbo's SIMD extensions.  There are two ways to work around this
when testing libjpeg-turbo with Valgrind, MSan, or other memory debuggers:

1. Disable the SIMD extensions, either by passing an argument of
   `-DWITH_SIMD=0` to `cmake` when configuring the build or by setting the
   environment variable `JSIMD_FORCENONE` to `1` at run time.
2. Define the `ZERO_BUFFERS` preprocessor macro (for instance, by adding
   `-DZERO_BUFFERS=1` to `CMAKE_C_FLAGS`.)
