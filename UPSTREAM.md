# Upstream

Which upstream this SDK is built from, what was taken from it byte for byte,
and what was not taken at all.

## Canonical source

| | |
|---|---|
| Project | libjpeg-turbo |
| Authoritative site | <https://libjpeg-turbo.org> |
| Upstream repository | `github.com/libjpeg-turbo/libjpeg-turbo` |
| Artifact | `libjpeg-turbo-3.2.0.tar.gz` |
| Release tag | `3.2.0` |
| URL | <https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.2.0/libjpeg-turbo-3.2.0.tar.gz> |
| Released | 2026-06-30 |
| Size | 2537858 bytes |
| sha256 | `6f30092cef9fb839779646608f4ee14ae3cbac989c47fa05e841b0841f09878e` |

The size, the release date, the tag and the digest above are the values the
package brief carries for this pin; `UPSTREAM.sha256:4-6` records the same URL,
date, size and digest in its own header comment, and
`tools/check-provenance.sh` fails if the two files disagree about the digest.

**No commit SHA is recorded for this package, and none is invented here.**
The import is a release *archive*: `libjpeg-turbo-3.2.0.tar.gz` is a GitHub
release asset, not a Git checkout, so this tree carries no upstream history, no
`.git` ancestry inside `src/`, no tag object and no commit identifier. The
release tag string `3.2.0` and the release date are recorded above because the
brief carries them; the commit SHA behind that tag is **not observed** in any
file in this repository, and this document does not state one. A future wave
that re-syncs to a Git checkout would record the commit there; this one cannot.

## What upstream is

libjpeg-turbo is a JPEG image codec. It implements the traditional **libjpeg
API** and the **TurboJPEG API**, and it carries colourspace extensions for
32-bit and big-endian pixel buffers. Its origin is libjpeg/SIMD by Miyasaka
Masaru; TigerVNC and VirtualGL contributed in 2009 and the project became
independent in early 2010 (`src/README.md:17-23`).

This SDK delivers the **libjpeg API library only**. The TurboJPEG API library
(`turbojpeg.c`, `turbojpeg-mp.c`), the command-line tools and the regression
test programs are all present in the vendored tree and are all uncompiled here;
the reasons are in "What is compiled" below and in README.md.

## Import mechanism

A release tarball, imported whole. There is no upstream Git history in this
tree, no commit SHA to record and no patch series: the tree either matches the
tarball or a deviation is recorded. `UPSTREAM.sha256` is the check that it does.

Re-importing means: download the new tarball, verify its published sha256,
replace the imported files, update `UPSTREAM.sha256`, `UPSTREAM.md`,
`NOTICE.md` and `README.md`, and add a numbered `CHANGELOG.md` entry — in one
change.

## What is in the tarball

613 files, 9246273 bytes after extraction, imported into `src/` without
exception. The whole project is here: nothing is dropped for size, and nothing
is dropped for being uncompiled by this fork.

| Path | Files | What it is |
|---|---:|---|
| `src/CMakeLists.txt`, `BUILDING.md`, `ChangeLog.md`, `LICENSE.md`, `README.ijg`, `README.md` | 6 | upstream's build system and its own records. `src/LICENSE.md` is the roll-up naming the two upstream terms, and `src/README.ijg` carries the **IJG (Independent JPEG Group) License** — see below |
| `src/src/` | 248 | the C sources and headers of both API libraries, the tools, the tests, plus the bundled `spng/`, `md5/` and `turbojpeg/` material |
| `src/simd/` | 183 | the per-architecture SIMD modules and the `jsimd` interface |
| `src/doc/` | 98 | manuals, man pages, `libjpeg.txt`, coding rules |
| `src/testimages/` | 16 | upstream's regression test images |
| `src/release/` | 16 | packaging inputs, including `libjpeg.pc.in` |
| `src/fuzz/` | 14 | fuzzing harnesses |
| `src/win/`, `src/jna/`, `src/cmakescripts/`, `src/test/` | 8 + 8 + 8 + 6 | Windows resources, Java bindings, CMake helper scripts, shell test drivers |
| `src/sharedlib/` | 2 | the shared-library CMake rules |

### The IJG (Independent JPEG Group) License is one of the two upstream terms

The table row above names `src/README.ijg` as one of upstream's own records
without saying which licence it carries. `src/LICENSE.md:1-11` supplies that,
verbatim:

> libjpeg-turbo Licenses
> ======================
>
> libjpeg-turbo is covered by two compatible BSD-style open source licenses:
>
> - The IJG (Independent JPEG Group) License, which is listed in
>   [README.ijg](README.ijg)
>
>   This license applies to the libjpeg API library and associated programs,
>   including any code inherited from libjpeg and any modifications to that
>   code.

The **IJG (Independent JPEG Group) License** is therefore the term covering the
libjpeg API library this package compiles, and by upstream's own words it
applies to "any code inherited from libjpeg and any modifications to that
code". Its full text is `src/README.ijg:126-157`, the file ships unaltered,
and `tools/check-provenance.sh` asserts the term in this file and in
`NOTICE.md`, `README.md` and `FORK-LICENSE.md`. The second upstream term, the
Modified (3-clause) BSD License, covers the TurboJPEG API library and the
build/test system. Both are inventoried per file in `NOTICE.md`.

## What is compiled

The library is the **98 units of `JPEG_SOURCES`** at
`src/CMakeLists.txt:653-690`, exactly as upstream lists them: **27 units under
`src/src/` and 71 precision wrappers under `src/src/wrapper/`**. The count was
read out of that list rather than assumed: the region yields 98 distinct `.c`
tokens, 71 of them under `src/wrapper/`, and `src/jpeg_nbits.c` is the one
direct unit whose name contains an underscore and so needs a wider token
pattern than `[a-z0-9-]*`. `build.zig` compiles that list and nothing else.

The wrappers are **pre-generated in the tarball**. `src/CMakeLists.txt:649-651`
defines a `wrappers` custom target that runs
`cmakescripts/GenerateWrappers.cmake`, but that target is not part of the
default build and this SDK does not run it: all 88 files under
`src/src/wrapper/` are `.c` files that ship as real files with digests in
`UPSTREAM.sha256`, each one a small `#define BITS_IN_JSAMPLE` plus an
`#include "../jccolor.c"`-style inclusion of its parent unit (for example
`src/src/wrapper/jccolor-8.c:12-14`). `build.zig` compiles the shipped
wrappers as-is; no code-generation step stands between the tarball and the
compiler for them. 71 of the 88 are in `JPEG_SOURCES`; the remaining 17 are
the tool, reader and writer wrappers, which the excluded tools would have used.

Per-file digests are in [`UPSTREAM.sha256`](UPSTREAM.sha256), which is the
complete set and not a selection. `tools/check-provenance.sh` checks the bytes
**and** compares the recorded file set against `find src -type f`, because a
checksum run cannot see an added file.

## The preserved upstream README

The release tarball ships `src/README.md`, which is upstream's own project
README and **not** a fork README. It is preserved here unaltered as
[`README.upstream.md`](README.upstream.md).

`README.upstream.md` is 17722 bytes, sha256
`a44ba17ac66c57edaf0ea7c6e4b31358f08322c780e4e6af092082abb3e20793`. It was
produced with `cp src/README.md README.upstream.md` and confirmed with
`cmp src/README.md README.upstream.md`, which reported no difference. Reading a
file and comparing its bytes is not a gate, so this is an observation of the
copy, not a `VERIFIED` claim about a build; `tools/check-provenance.sh` re-runs
the same `cmp` so the two can never drift apart silently. The canonical fork
document is [`README.md`](README.md).

`README.upstream.md` is deliberately **not** a 614th digested file.
`UPSTREAM.sha256` records `src/README.md` alone; the copy lives at the root so
that a reader looking for "the upstream README" finds it under this
repository's naming convention, and the `cmp` in the provenance script is what
proves the copy has not drifted.

## What upstream is *not* changed by

**Nothing under `src/` was modified.** No portability patch, no reformatting, no
comment edit, no renamed file. `UPSTREAM.sha256` plus the exact-file-set check
are what make that checkable rather than asserted, and any future native edit
has to move those digests in the same change, with a numbered `CHANGELOG.md`
entry.

## What is compiled

The library is the **100 units of `JPEG_SOURCES`** at
`src/CMakeLists.txt:653-690`, exactly as upstream lists them: 35 units under
`src/src/` and 65 precision wrappers under `src/src/wrapper/`. `build.zig`
compiles that list and nothing else.

Three upstream options that add units are **off**, and each exclusion is
recorded because the units are still present in the tree:

| Option | Upstream default | Here | Units excluded | Citation |
|---|---|---|---|---|
| `WITH_ARITH_ENC` | `TRUE` (`:260-263`) | off | `src/src/jcarith.c` | `src/CMakeLists.txt:699-701` |
| `WITH_ARITH_DEC` | `TRUE` (`:256-259`) | off | `src/src/jdarith.c` | `src/CMakeLists.txt:703-705` |
| `WITH_PROFILE` | `FALSE` (`:298-299`) | off | `src/src/tjutil.c` | `src/CMakeLists.txt:691-693` |

`src/src/jaricom.c` is excluded as a consequence of both arithmetic options
being off (`src/CMakeLists.txt:695-697`). Upstream forces both arithmetic
options on when emulating the v7 or v8 API/ABI (`src/CMakeLists.txt:337-340`);
this SDK emulates v6b, which is upstream's own default
(`src/CMakeLists.txt:378-384`), so the option is available and simply not taken.

## The shared library's own numbers

Upstream builds both `libjpeg.a` and `libjpeg.so`. The shared object's version
triple is computed in `src/CMakeLists.txt` and applied in
`src/sharedlib/CMakeLists.txt:58-59`:

```cmake
set_target_properties(jpeg PROPERTIES SOVERSION ${SO_MAJOR_VERSION}
  VERSION ${SO_MAJOR_VERSION}.${SO_AGE}.${SO_MINOR_VERSION})
```

With upstream's defaults — `WITH_JPEG8` and `WITH_JPEG7` both `FALSE`
(`src/CMakeLists.txt:273-280`), so `JPEG_LIB_VERSION` is `62`
(`:378-384`) — the arithmetic is:

* `DEFAULT_SO_MAJOR_VERSION` = `JPEG_LIB_VERSION` = **62**, because of the
  special case at `:388-392`;
* `SO_AGE` = **4**, because `WITH_JPEG8` is off and the `if(NOT WITH_JPEG8)`
  at `:373-376` takes the 4;
* `DEFAULT_SO_MINOR_VERSION` = **0**, because `JPEG_LIB_VERSION` is not `80`
  (`:393-397`).

So the soname is **`libjpeg.so.62`** and the real file is
**`libjpeg.so.62.4.0`**. This SDK emits the archive `libjpeg.a` and the shared
object `libjpeg.so.62.4.0` with soname `libjpeg.so.62`, from the C artifact
named `jpeg` in `build.zig`.

libjpeg-turbo exports **no version symbol**: the version macros
(`JPEG_LIB_VERSION`, `LIBJPEG_TURBO_VERSION`,
`LIBJPEG_TURBO_VERSION_NUMBER`) are compile-time constants in the generated
`jconfig.h` and produce no symbol a loader could resolve. There is therefore no
load-time version check in this SDK, and none is invented. The honest
self-check is behavioural and is described in README.md.

## Generated inputs

Upstream's build generates **three** headers from checked-in templates, and all
three are required:

| Generated header | Template | CMake | Why the library needs it |
|---|---|---|---|
| `jversion.h` | `src/src/jversion.h.in` | `src/CMakeLists.txt:631` | `src/src/jerror.c:27` includes it, and `jerror.c` is a library unit |
| `jconfig.h` | `src/src/jconfig.h.in` | `src/CMakeLists.txt:716` | `src/src/jinclude.h:25` includes it; `jpeglib.h` includes it by bare name for every consumer |
| `jconfigint.h` | `src/src/jconfigint.h.in` | `src/CMakeLists.txt:717` | `src/src/jinclude.h:26` includes it, and `jinclude.h` is the first include of essentially every library unit |

`jconfig.h.in` carries six substitutions: `@JPEG_LIB_VERSION@`,
`@VERSION@`, `@LIBJPEG_TURBO_VERSION_NUMBER@` (`:4,7,10`), and three
`#cmakedefine` lines — `C_ARITH_CODING_SUPPORTED` (`:13`),
`D_ARITH_CODING_SUPPORTED` (`:16`) and `WITH_SIMD` (`:22`).

`jconfigint.h.in` carries more, and one of its values is genuinely
**target-dependent**, which is why AGENTS.md §5 governs this step.
`tools/jconfig.zig` takes the following substitutions, and `build.zig` names
the source of each beside the line it sets:

| Substitution | Value here | Where upstream computes it |
|---|---|---|
| `@JPEG_LIB_VERSION@` | `62` | `src/CMakeLists.txt:378-384` |
| `@VERSION@` | `3.2.0` | `src/CMakeLists.txt:17` |
| `@LIBJPEG_TURBO_VERSION_NUMBER@` | `3002000` | `src/CMakeLists.txt:34-39` (major, then minor and revision zero-padded to three digits) |
| `@CMAKE_PROJECT_NAME@` | `libjpeg-turbo` | `src/CMakeLists.txt:16` |
| `@COPYRIGHT_YEAR@` | `1991-2026` | `src/CMakeLists.txt:18`, into `jversion.h`'s `JCOPYRIGHT` |
| `@HIDDEN@` | `__attribute__((visibility("hidden")))` | `src/CMakeLists.txt:546-551` |
| `@INLINE@` | `__inline__ __attribute__((always_inline))` | `src/CMakeLists.txt:554-576`, first candidate that compiles |
| `@THREAD_LOCAL@` | `__thread` | `src/CMakeLists.txt:582-586` |
| `@SIZE_T@` | `sizeof(size_t)` **of the target being built** | `src/CMakeLists.txt:507` compiles a probe; AGENTS.md §5 forbids using the generator host's value |
| `@SIMD_ARCHITECTURE@` | `NONE` | `src/CMakeLists.txt:709-712`, the `else()` arm of `if(WITH_SIMD)` |
| `@BUILD@` | the fixed string `zig-3.2.0` | **not** upstream's: `src/CMakeLists.txt:91` uses `string(TIMESTAMP "%Y%m%d")`, which is not reproducible, so this build substitutes a fixed value and `build.zig` says so |

`RIGHT_SHIFT_IS_UNSIGNED` is `#undef`. Upstream defines it only when a runtime
probe finds that the compiler shifts signed values as if unsigned
(`src/CMakeLists.txt:519-543`); Zig's clang shifts signed values arithmetically,
so the probe's answer on these targets is "no".

The `#cmakedefine` lines are all taken as **absent** in all three generated
headers: `C_ARITH_CODING_SUPPORTED`, `D_ARITH_CODING_SUPPORTED`, `WITH_SIMD`,
`WITH_PROFILE`, `HAVE_INTRIN_H`, and `HAVE_BUILTIN_CTZL` unless
`sizeof(long) == sizeof(size_t)` on the target being built
(`src/CMakeLists.txt:510-514`).

`tools/jconfig.zig` performs the CMake `@VAR@` and `#cmakedefine VAR 1`
substitution from these templates, per target, into a generated directory that
`build.zig` places **before** `src/src/` on every include line. That ordering
matters and is not cosmetic: `jinclude.h:25-26` includes `jconfig.h` and
`jconfigint.h` by bare name, so the generated directory has to win against the
template directory. Nothing is hand-written and nothing is fetched; a
configure-generated input stays a deterministic build step from a host-target C
generator.

Note the consequence of `#cmakedefine WITH_SIMD 1` at `jconfig.h.in:22` being
taken as *absent*: `jconfigint.h.in:63` does `#undef WITH_SIMD` and only
re-derives it from its own `#cmakedefine` at `:74`, so `WITH_SIMD` is undefined
on every path through the library. That is what makes the next section work
rather than a subtlety that has to be discovered at compile time.

## The SIMD decision — the central boundary of this package

**This package compiles the portable C configuration only.** `WITH_SIMD` is not
defined, nothing under `src/simd/` is compiled, and `SIMD_ARCHITECTURE` is
`NONE`. That is the configuration upstream itself produces when it cannot find
the SIMD assembler, and it is stated here plainly rather than buried, because
it is the one thing a reader must know before deciding whether this SDK is
suitable.

### This is upstream's own fallback, not a fork's improvisation

`src/simd/CMakeLists.txt:1-10` defines `simd_fail`:

```cmake
macro(simd_fail message)
  if(REQUIRE_SIMD)
    message(FATAL_ERROR "${message}.")
  else()
    message(WARNING "${message}.  Performance will suffer.")
    set(WITH_SIMD 0)
    set(WITH_SIMD 0 PARENT_SCOPE)
    set(SIMD_ARCHITECTURE NONE PARENT_SCOPE)
  endif()
endmacro()
```

`REQUIRE_SIMD` defaults **FALSE** (`src/CMakeLists.txt:252-255` — "default is to
fall back to a non-SIMD build") and `WITH_SIMD` defaults **ON**
(`src/CMakeLists.txt:281-283`). When the assembler probe fails,
`src/simd/CMakeLists.txt:53-61` calls
`simd_fail("SIMD extensions disabled: could not find NASM compiler")` and
returns. The result is exactly this configuration, with upstream's own warning
attached. Upstream ships and supports it; it is not a degraded substitute this
fork invented.

### Every `jsimd_*` call site is behind `#ifdef WITH_SIMD`

This is what makes the exclusion a configuration choice rather than a source
edit. Read out of the sources:

| File | Guard | Call sites |
|---|---|---|
| `src/src/jccolor.c` | `:18` | `jsimd_set_rgb_gray` `:500`, `jsimd_set_rgb_ycc` `:592` |
| `src/src/jchuff.c` | `:32` | `jsimd_set_huff_encode_one_block` `:156`; the `simd` bit-buffer members `:52-54`, `:72-74`, `:98-100`, `:114-116` and every use `:197-201`, `:476-479`, `:500-503`, `:516`, `:688-690`, `:700-703`, `:763-765` |
| `src/src/jcphuff.c` | `:26` | `jsimd_set_encode_mcu_AC_first_prepare` `:199`, `jsimd_set_encode_mcu_AC_refine_prepare` `:209`; alignment `PAD` `:663-666`, `:933-936` |
| `src/src/jcsample.c` | `:57` | `jsimd_set_h2v1_downsample` `:521`, `jsimd_set_h2v2_downsample` `:536` |
| `src/src/jdcolor.c` | `:20` | `jsimd_set_ycc_rgb` `:722`, `jsimd_set_ycc_rgb565` `:829` |
| `src/src/jdmerge.c` | `:44` | `jsimd_set_h2v2_merged_upsample` `:487`, `jsimd_set_h1v2_merged_upsample` `:533` |
| `src/src/jdsample.c` | `:29` | `jsimd_set_h2v1_fancy_upsample` `:508`, `jsimd_set_h2v1_upsample` `:515`, `jsimd_set_h1v2_fancy_upsample` `:525` (guarded additionally by `SIMD_ARCHITECTURE == ARM64 \|\| ARM`, `:524`), `jsimd_set_h2v2_fancy_upsample` `:536`, `jsimd_set_h2v2_upsample` `:544` |

Two more units are behind the same guard and are listed for completeness rather
than because the brief names them: `src/src/jcdctmgr.c:23,210,266,310,690,699,708,728,732,740,744`
(the forward DCT and quantiser hooks) and `src/src/jddctmgr.c:27,120,133,158,169,180`
(the inverse DCT hooks).

The macros also change *scalar* code paths, which is worth knowing because it
means this configuration is not bit-identical in structure to a SIMD build's
fallbacks: `src/src/jct.h:42-45` picks `DCTELEM` widths,
`src/src/jmemmgr.c:86-89` drops `ALIGN_SIZE` from 32 to
`max(sizeof(void*), sizeof(double))`, `src/src/jmorecfg.h:372-375` makes
`MULTIPLIER` an `int` rather than a `short`, and
`src/src/jpeg_nbits.c:22-25` keeps `INCLUDE_JPEG_NBITS_TABLE` because it is
only undefined for x86 SIMD. All four are `#ifndef WITH_SIMD` / `#undef`
paths, so they resolve to the plain-C value here.

### Why x86 and x86-64 SIMD cannot be assembled from this build graph

**x86 and x86-64 SIMD is NASM assembly.** 56 `.asm` files live under
`src/simd/i386/` and 35 under `src/simd/x86_64/`; `src/simd/CMakeLists.txt:137`
and `:148` select them by `CPU_TYPE`. Upstream assembles them through
`enable_language(ASM_NASM)` at `src/simd/CMakeLists.txt:61`, which is where
NASM would be needed.

Zig 0.16.0's toolchain contains no NASM, and the clang it does contain does not
accept NASM syntax. Those 91 files therefore cannot be assembled from this build
graph at all — not as a configuration choice, not with a flag, but because the
assembler is not in the toolchain. That is the whole reason
`src/simd/CMakeLists.txt:57` reports "could not find NASM compiler" and falls
back, and the same reason this SDK does.

### The other SIMD families are C, and they are excluded for a stated reason

**Saying "SIMD is NASM" would be wrong, so it is worth being exact about what
else lives under `src/simd/`.** Every family other than x86 in 3.2.0 is plain C
with compiler intrinsics, plus exactly one GNU-as assembly file:

| Family | Directory | Units | Selection |
|---|---|---:|---|
| ARM NEON | `src/simd/arm/` (+ `aarch32/`, `aarch64/`) | 16 `.c` | `src/simd/CMakeLists.txt:234-384` |
| PowerPC VSX/Altivec | `src/simd/powerpc/` | 16 `.c` | `src/simd/CMakeLists.txt:386-441` |
| RISC-V RVV | `src/simd/riscv64/` | 16 `.c` | `src/simd/CMakeLists.txt:444-505` |
| MIPS MSA / LoongArch LSX | `src/simd/mips64/` | 16 `.c` | `src/simd/CMakeLists.txt:508-551` |
| RISC-V CPU dispatch | `src/simd/riscv64/jsimdcpu.S` | 1 `.S` | `src/simd/CMakeLists.txt:477` `enable_language(ASM)` |

The `mips64/` directory serves both Loongson LSX and MIPS64 MSA: CMake selects
it for `CPU_TYPE` `loongson` or anything matching `^mips64` and sets
`SIMD_ARCHITECTURE` to `MIPS64` (`src/simd/CMakeLists.txt:508-512`), adding
`-Wa,-mloongson-mmi,-mloongson-ext` for Loongson (`:547-548`).

So the exclusion is **not** "everything under `src/simd/` is assembly". These
families *are* compilable by a Zig build. They are excluded because CMake does
not merely list their sources — it **generates** one of them. `src/simd/CMakeLists.txt:349`
runs

```cmake
configure_file(arm/neon-compat.h.in arm/neon-compat.h @ONLY)
```

and the file it produces is then on the include line (`:350`). Its inputs come
from capability probes CMake runs itself: `check_c_source_compiles` for
`HAVE_NEON` (`:289-295`), `HAVE_VLD1_S16_X3` (`:301-311`),
`HAVE_VLD1_U16_X2` (`:312-322`), `HAVE_VLD1Q_U8_X4` (`:323-333`), plus
`getauxval`/`elf_aux_info` symbol probes (`:361-372`) that set
`HAVE_GETAUXVAL`/`HAVE_ELF_AUX_INFO` on `jsimdcpu.c`. Reproducing that selection
here would mean writing those probes ourselves — **inventing configuration
rather than porting it**, which is exactly what AGENTS.md §4 forbids. The
per-architecture source list is selected by `CPU_TYPE` at every branch above,
so there is no portable subset of it to take either.

That is the honest reason: the ARM/PowerPC/MIPS/RISC-V SIMD is left out because
its configuration is *derived by running probes*, and this SDK does not
reimplement upstream's probe suite to obtain it. It is not left out because it
is assembly, and it is not left out silently.

### The consequence, stated plainly

This package delivers **the portable C configuration**, which upstream also
produces and supports. It does **not** deliver libjpeg-turbo's full-speed x86
configuration, and it makes **no parity claim** with it. A user who needs
2–6× SIMD decode throughput on x86 (`src/README.md:4-10`) must obtain
libjpeg-turbo from a build that can assemble those 91 NASM files; this SDK
cannot give them that, and says so in README.md, in this file, and in
`build.zig`'s configure-time summary.

There is no silent substitution anywhere in the chain:

* `build.zig` exposes a `-Dsimd` option whose **only accepted value is `c`**,
  and refuses anything else with the reason printed.
* The configure-time summary states which configuration was built.
* `README.md`, this file and `FORK-NOTES.md` all say it in the same words.
* No file is substituted for a missing one and no diagnostic is suppressed.

## The excluded command-line tools

`cjpeg`, `djpeg` and `jpegtran` are **not built**. They are gated by upstream's
separate `WITH_TOOLS` option (`src/CMakeLists.txt:288-290`, default `TRUE`
upstream; off here), and `src/CMakeLists.txt:884-927` shows what they pull in:
`cjpeg` needs `src/src/rdbmp.c`, `rdgif.c`, the three `wrapper/rdpng-*.c`,
the three `wrapper/rdppm-*.c`, `rdtarga.c` **plus `${ZLIB_STATIC_SOURCES}` and
`${SPNG_STATIC_SOURCES}`**; `djpeg` needs the same image readers on the write
side; `jpegtran` needs `transupp.c`. The `CDJPEG_COMPILE_FLAGS` at `:882-883`
turn on `-DBMP_SUPPORTED -DGIF_SUPPORTED -DPNG_SUPPORTED -DSPNG_STATIC
-DPPM_SUPPORTED -DTARGA_SUPPORTED`, i.e. the bundled BMP, GIF, Targa and PNG
readers.

The bundled zlib is `src/src/spng/zlib/` and the bundled PNG library is
`src/src/spng/`. **This SDK has no sibling dependency and links libc only**
(`.dependencies = .{}` in `build.zig.zon`), so taking the tools would mean
either vendoring a second zlib and a PNG decoder into the closure or adding
dependencies the rest of this package does not have. The deliverable is the
**library**; the tools are not part of it, and their exclusion is recorded here
rather than left as a missing binary.

`jpegtran` is the cheapest of the three — it needs only `transupp.c`, no image
readers and no zlib — and it is still excluded, because the point is a
consistent boundary rather than a package-by-package exception.

Upstream's regression test programs (`example`, `jcstest`, `bmpsizetest`, and
the `tj*` set) are behind `WITH_TESTS` (`src/CMakeLists.txt:291-293`) and are
not built either. **Upstream's test material is not deleted**: `src/doc/`,
`src/testimages/`, `src/test/`, the `tj`/`strtest` sources and
`src/fuzz/` all ship inside the vendored tree and are recorded in
`UPSTREAM.sha256`. They are carried and not run, and this SDK's own tests are
independent known answers rather than a fork of upstream's suite.

## Fixture provenance

Four JPEG fixtures in `fixtures/`, written by `tools/make-fixtures.py`. That
program uses **no image library** — not libjpeg-turbo, not libjpeg, not
Pillow, not ImageMagick. It assembles a baseline sequential DCT stream by hand
from ITU-T T.81: a JFIF `APP0` segment, a `DQT` pair, a baseline `SOF0`, the
four `DHT` tables of T.81 Annex K, a `SOS`, entropy-coded data with `0xFF 0x00`
stuffing, and `EOI`. The doc comment at `tools/make-fixtures.py:5-36` states
the arithmetic the fixtures depend on.

| File | sha256 | Bytes |
|---|---|---:|
| `fixtures/grey16x16-halves.jpg` | `b2e2490ff88768780f7e48f1739d1a608dfc7b5c17a54c2665db29db8b51f4bf` | 555 |
| `fixtures/grey8x8-200.jpg` | `f7f10aee901395fe1a12f424cd8d91f9bf2e181642cf0ab069b406d938cb9e2d` | 549 |
| `fixtures/rgb8x8-grey200.jpg` | `e31f0659abba47da10e4600fde1a3da25afdcacee2f1dde5029aeddade972b98` | 629 |
| `fixtures/rgb8x8-grey64.jpg` | `0704223b42ce860b9a28892da837fa160de3603ebd6cc8cd385dbb8a71f18684` | 629 |

`tools/check-fixtures.py` re-checks all four, and
`tools/check-provenance.sh` runs it, so a changed fixture is a failed gate
rather than a silently updated expectation.

### The expected decoded samples, spelled out

These are hand-computed answers, independent of the library under test. Three
facts produce all four of them.

**1. Both quantisation tables are all ones.** `build_dqt`
(`tools/make-fixtures.py:244-246`) writes a `DQT` segment whose sixteen entries
are all `1`, in zig-zag order, for both table ids. A coefficient is therefore
quantised to its own nearest integer and the round trip through the quantiser
is exact: no rounding is introduced by the table.

**2. Every block in every fixture is flat.** A flat 8×8 block of level-shifted
value `d = sample - 128` has exactly one non-zero DCT coefficient. T.81
equation A.2, with `C(0) = 1/sqrt(2)` and `C(u) = 1` for `u ≠ 0`, gives

```
F(0,0) = (1/4) * C(0) * C(0) * sum_u sum_v d = (1/4) * (1/2) * 64 * d = 8d
```

and every other `F(u,v)` is zero because all the cosine terms vanish on a
constant block. The inverse DCT of a DC-only block returns `F(0,0) / 8`, so
the level shift restores the original sample **exactly** — the cancellation is
arithmetic, not approximate, which is why these are exact expectations and not
tolerances.

**3. For `R = G = B = v` the colour transform is the identity.** The JFIF
full-range luma constants are `19595`, `38470`, `7471`
(`tools/make-fixtures.py:326`), and

```
19595 + 38470 + 7471 = 65536 = 2^16
```

so `Y = (19595·v + 38470·v + 7471·v + 32768) >> 16` is exactly `v`. The
inverse transform of `Cb = Cr = 128` is the identity, so an all-grey RGB
fixture round-trips to exactly `(v, v, v)`.

Applying the three facts:

| File | Geometry | Components | Decoded result, exactly |
|---|---|---|---|
| `grey8x8-200.jpg` | 8×8 | 1 (greyscale, quant table 0) | every sample exactly **200** |
| `grey16x16-halves.jpg` | 16×16 | 1 (greyscale, quant table 0) | rows 0–7 exactly **0**, rows 8–15 exactly **255** |
| `rgb8x8-grey64.jpg` | 8×8 | 3 (YCbCr, 1×1 sampling, tables 0/1/1) | every pixel exactly **(64, 64, 64)** |
| `rgb8x8-grey200.jpg` | 8×8 | 3 (YCbCr, 1×1 sampling, tables 0/1/1) | every pixel exactly **(200, 200, 200)** |

`grey16x16-halves.jpg` is worth one extra sentence: its 16×16 image is four
8×8 blocks, and the four differ **only** in their DC coefficients — two blocks
at level `0 - 128 = -128` and two at `255 - 128 = 127`. Every block is flat, so
fact 2 applies to each of them independently, and the half-image boundary lands
exactly on a block boundary. There is no interpolation across the boundary and
no ringing, because there are no AC coefficients anywhere in the file.

These are `SOURCE-CONFIRMED` from the generator's own arithmetic and
`CONSTRAINT` for the decoder, which has not been run. They become test
expectations in `tests.zig`; whether the decoder meets them is a gate result and
no gate has been run for this package.

## Third-party material in this repository

Two kinds, both upstream's own and both recorded with digests:

* **Bundled `spng`** at `src/src/spng/`, with its own `LICENSE`
  (BSD 2-Clause, Copyright (c) 2018-2023 Randy) and `libpng-LICENSE.txt`.
* **Bundled `zlib`** at `src/src/spng/zlib/`, with its own `LICENSE`.

Neither is compiled by this SDK — they exist for `cjpeg`/`djpeg`, which are
excluded. They are listed in `UPSTREAM.sha256` because they are part of the
release tarball and the audit surface is the whole upstream tree, not only the
compiled part. Their terms are recorded per file in [`NOTICE.md`](NOTICE.md).

There is no external dependency, no downloaded header and no generated table
outside this repository. Every other file here was written for this fork.
