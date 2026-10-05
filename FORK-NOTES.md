# FORK-NOTES.md

Working notes for the libjpeg-turbo SDK. Every entry is in the
**condition / symptom / fix / targets bound** shape AGENTS.md §10 requires, and
every entry names its boundary. An entry without a boundary is not promotable,
so one is stated in each.

`STATUS`: **every entry below is `PENDING-VERIFICATION` or `CONSTRAINT`.** No
gate has been run for this package. Nothing here has been built, executed,
cross-compiled or formatted, and nothing below is a `VERIFIED` result. Nothing
here is `OBSERVED` about a build; the source citations are `SOURCE-CONFIRMED`
reads of files in this repository.

---

## 1. SIMD is not compiled — the central boundary

**Condition.** libjpeg-turbo's performance claim rests on SIMD
(`src/README.md:4-10`: *"generally 2-6x as fast as libjpeg"*). This package's
toolchain is Zig 0.16.0.

**Symptom.** `WITH_SIMD` cannot be defined for x86 or x86-64. Those SIMD
modules are **NASM assembly** — 56 `.asm` files under `src/simd/i386/` and 35
under `src/simd/x86_64/`, selected at `src/simd/CMakeLists.txt:137` and `:148`
and assembled through `enable_language(ASM_NASM)` at `:61`. Zig 0.16.0's
toolchain contains no NASM, and its clang does not accept NASM syntax. This is
not a configuration that can be enabled; the assembler is not in the toolchain.

The other families are a different matter and saying "SIMD is NASM" would be
wrong: ARM NEON (`src/simd/arm/`, `aarch32/`, `aarch64/`), PowerPC
(`src/simd/powerpc/`), RISC-V RVV (`src/simd/riscv64/`) and MIPS MSA /
LoongArch LSX (`src/simd/mips64/`) are **plain C with compiler intrinsics**,
16 `.c` units each, plus exactly one GNU-as `.S`
(`src/simd/riscv64/jsimdcpu.S`, `src/simd/CMakeLists.txt:477`). Those *are*
compilable by a Zig build.

**Fix.** Compile the portable C configuration: `WITH_SIMD` undefined,
`SIMD_ARCHITECTURE NONE`, nothing under `src/simd/` compiled. Every `jsimd_*`
call site is behind `#ifdef WITH_SIMD` — the full guard/call-site table is in
UPSTREAM.md — so this is a configuration choice and not a source edit.

The intrinsics families are excluded for a **different** reason, and the reason
matters for any future wave: CMake does not merely list their sources, it
**generates** `simd/arm/neon-compat.h` at `src/simd/CMakeLists.txt:349` from
capability probes CMake runs itself — `check_c_source_compiles` for `HAVE_NEON`
(`:289-295`), `HAVE_VLD1_S16_X3` (`:301-311`), `HAVE_VLD1_U16_X2` (`:312-322`),
`HAVE_VLD1Q_U8_X4` (`:323-333`) — plus `getauxval`/`elf_aux_info` symbol
probes (`:361-372`) that set `HAVE_GETAUXVAL`/`HAVE_ELF_AUX_INFO` on
`jsimdcpu.c`. The per-architecture source list is chosen by `CPU_TYPE` at
`:234`, `:386`, `:444` and `:508`. Porting that faithfully would mean writing
those probes ourselves: **inventing configuration rather than porting it**,
which AGENTS.md §4 forbids. So they are out, and the reason is stated rather
than left to be guessed at.

`build.zig` makes the boundary unignorable in three places: a `-Dsimd` option
whose **only accepted value is `c`**, a configure-time summary naming the
configuration that was built, and this entry.

**Upstream does the same thing.** `src/simd/CMakeLists.txt:1-10` defines
`simd_fail`, which — with `REQUIRE_SIMD` defaulting **FALSE**
(`src/CMakeLists.txt:252-255`) — warns *"Performance will suffer"*, sets
`WITH_SIMD 0` and `SIMD_ARCHITECTURE NONE`, and returns; it is called at
`:53-61` with *"SIMD extensions disabled: could not find NASM compiler"*.
`WITH_SIMD` defaults **ON** upstream (`:281-283`). This package therefore ships
a configuration upstream itself produces and supports — **not** the full-speed
x86 configuration, and **no parity claim** is made.

**Targets bound.** All six. There is no target on which `-Dsimd` may name
anything but `c`, and no target on which this SDK provides SIMD. Enabling it
for the intrinsics families is a separate piece of work whose precondition is a
port of upstream's probe suite; it is not a flag flip.

---

## 2. The command-line tools are not built

**Condition.** `cjpeg`, `djpeg` and `jpegtran` exist upstream, gated by
`WITH_TOOLS`, and users of a JPEG library sometimes expect them.

**Symptom.** They cannot be built here without a second zlib and a PNG
decoder. `src/CMakeLists.txt:884-927` shows `cjpeg` and `djpeg` pulling in
`rdbmp.c`, `rdgif.c`, `rdtarga.c`, three `wrapper/rdpng-*.c`, three
`wrapper/rdppm-*.c` **plus `${ZLIB_STATIC_SOURCES}` and
`${SPNG_STATIC_SOURCES}`**, with `CDJPEG_COMPILE_FLAGS` at `:882-883` turning
on `-DBMP_SUPPORTED -DGIF_SUPPORTED -DPNG_SUPPORTED -DSPNG_STATIC
-DPPM_SUPPORTED -DTARGA_SUPPORTED`. The bundled zlib is
`src/src/spng/zlib/`; the bundled PNG library is `src/src/spng/`.

**Fix.** `WITH_TOOLS` off. The library is the deliverable. `jpegtran` is the
cheapest of the three — it needs only `transupp.c`, no readers, no zlib — and
it is still excluded, because a consistent boundary is worth more than a
package-by-package exception. Nothing is stubbed: the tools are absent, not
faked.

**Targets bound.** All six, and every linkage. Taking the tools would mean
either adding `.dependencies` to `build.zig.zon` (currently `.{}`) or vendoring
a second zlib and a PNG decoder into the closure — either changes what this
package *is*, and both need their own licences recorded in NOTICE.md.

---

## 3. Three headers are generated rather than checked in

**Condition.** Upstream's build generates `jversion.h`, `jconfig.h` and
`jconfigint.h` from `.in` templates with CMake `configure_file`
(`src/CMakeLists.txt:631`, `:716`, `:717`).

**Symptom.** None of the three exists in the tarball, and all three are needed.
`src/src/jinclude.h:25-26` includes `jconfig.h` and `jconfigint.h` by bare
name, and `jinclude.h` is the first include of essentially every library unit;
`src/src/jerror.c:27` includes `jversion.h`, and `jerror.c` is in
`JPEG_SOURCES`. **`jconfigint.h` is the one that is easy to miss**: a generator
that produces only `jconfig.h` and `jversion.h` fails on every unit that
includes `jinclude.h`.

**Fix.** `tools/jconfig.zig` performs CMake's `@VAR@` and `#cmakedefine VAR 1`
substitution from all three templates, per target, into a generated directory
that `build.zig` places **before** `src/src/` on every include line. The
ordering is load-bearing: `jinclude.h:25-26` uses bare names, so the generated
directory has to win against the template directory.

Two values are genuinely **target-dependent**, so AGENTS.md §5 governs them:
`@SIZE_T@`, which upstream computes by compiling a probe
(`src/CMakeLists.txt:507`), and `@SIMD_ARCHITECTURE@`, which is `NONE` on the
no-SIMD path (`src/CMakeLists.txt:709-712`). Neither may come from the machine
running the generator. The full substitution table, with each value's source
line, is in UPSTREAM.md.

`@BUILD@` is the one value **not** taken from upstream: upstream uses
`string(TIMESTAMP "%Y%m%d")` at `src/CMakeLists.txt:91-92`, which is not
reproducible. This build substitutes a fixed string and `build.zig` says so.

**Targets bound.** All six, per target. A cross target must not receive the
generator host's `sizeof(size_t)`; that is the failure mode this note exists to
prevent, and the 32-bit cells of the matrix are where it would show.

---

## 4. `.fingerprint` is deliberately absent

**Condition.** `build.zig.zon` names a package, and Zig packages may carry a
`.fingerprint` field.

**Symptom.** A fingerprint is an identifier the Zig toolchain **derives** for a
named package. Deriving one means running the compiler.

**Fix.** Leave it out. No gate has been run for this package, so any value
written now would be an invented identifier — which AGENTS.md §2 rule 3 forbids
outright. The first observed `zig build` prints the value the toolchain computes
for `.libjpeg_turbo`; the driver records it in this file and adds it to
`build.zig.zon` in the same change. Nothing in this package's source, build
graph or tests reads the field, so nothing is blocked by its absence.

**Targets bound.** None — this is manifest-level, not per-target. It is bound
to the *package* and to the moment before the first observed `zig build`.

---

## 5. `wasm32-wasi` is unknown

**Condition.** The compile-target matrix is six targets, and one of them is
`wasm32-wasi`.

**Symptom.** **Not observed.** No compile has been attempted for
`wasm32-wasi` or for any other target. There is no error message, no failure
output and no identified cause — which means there is no symptom in the
AGENTS.md sense at all, only an absence of evidence.

What to watch when it is attempted, so the entry is useful to a later wave: the
98 `JPEG_SOURCES` units use `jinclude.h:36-39`, which pulls in `<stddef.h>`,
`<stdlib.h>`, `<stdio.h>` and `<string.h>`. Whether Zig's wasm32-wasi libc
supplies all four, and whether a shared `libjpeg.so` is meaningful for a target
whose linking model differs, are the two open questions — both are questions,
not findings.

**Targets bound.** `wasm32-wasi` only. The other five are named in the README's
matrix and equally unattempted, but no specific question attaches to them yet.

---

## 6. No gate has been run — the status of everything above

**Condition.** AGENTS.md §2 separates an observation from a verified result,
and this file records decisions.

**Symptom.** Every entry above is a decision with a citation, and not one of
them has been executed. The SIMD exclusion is `SOURCE-CONFIRMED` as a fact
about the sources; whether the remaining 98 units compile without `src/simd/`
is **not** known, because nothing has been run.

**Fix.** Every entry lands `PENDING-VERIFICATION` and the driver runs the gates
in README.md, "The gates the driver must run": `zig build`, `zig build test` in
Debug and ReleaseSafe, `zig build smoke`, `zig build check` over the six
targets, `tools/check-provenance.sh`, and `zig build run` in `consumer/`. Only
the driver moves an entry to `VERIFIED`, and only beside an observed run
recording command, optimize mode, target, exit code, date and receipt path.

`tools/check-provenance.sh` has **not** been run — running it is itself a gate.
The reads that *were* done while preparing this file, each of which only reads
bytes and compiles nothing, are: `find src -type f` returned 613 paths, matching
the 613 records `UPSTREAM.sha256` declares; `sha256sum` on the four fixtures
matched their recorded digests; and `cmp src/README.md README.upstream.md`
reported no difference. Those are observations of files, not gates, and
AGENTS.md §2 keeps them in a different category from a build result.

**Targets bound.** All six, plus both linkages, plus the consumer package.

---

## 7. libjpeg-turbo exports no version symbol

**Condition.** A runtime-loaded provider has to be checked for compatibility
with the consumer that loads it.

**Symptom.** There is nothing to check against. `JPEG_LIB_VERSION`,
`LIBJPEG_TURBO_VERSION` and `LIBJPEG_TURBO_VERSION_NUMBER` are compile-time
constants in the *generated* `jconfig.h` (`src/src/jconfig.h.in:4,7,10`). They
live in a header, not in the shared object's symbol table, so `dlsym` cannot ask
a provider which release it is.

**Fix.** No version check, and no invented substitute for one. The honest
self-check through the resolved table is behavioural and is described in
README.zig.md: `jpeg_std_error` returns non-NULL; a 1×1 greyscale image
compresses and decompresses completely through the same table and reads back
the original sample. A provider whose structs disagree fails there rather than
passing a string comparison.

**Targets bound.** The `-Druntime=true` route on every target. It does not
affect the linked route, where the linker does the symbol matching.

---

## 8. `std.testing.allocator` is not a leak oracle for this library

**Condition.** AGENTS.md §4 asks that a test prove behaviour, and a leak check
is the obvious one.

**Symptom.** libjpeg-turbo allocates through the **C library's own** allocator
inside `jmemmgr.c`, and `jpeg_mem_dest`/`jpeg_mem_src` transfer a buffer to the
library rather than taking one from Zig's allocator. A test that allocated
through `std.testing.allocator` and reported "0 leaked" would be measuring the
wrong allocator, and would stay silent if the library leaked its own.

**Fix.** Prove **ownership transitions** instead: a decompress object destroyed
exactly once, a compress object destroyed exactly once after
`jpeg_finish_compress`, and — where a custom allocator *is* installed through
the `jpeg_mem_` manager overrides — a count of that installer's own allocations
and frees over a full compress-then-decompress cycle. That last path is a real
oracle, for the allocator under test. The limitation is stated plainly in
`tests.zig` and `smoke.zig` so a reader does not read a green allocator report
as more than it is.

**Targets bound.** The test route on every target. It is a test-design rule, not
a platform one, but the custom-allocator path is only exercised where the test
actually runs — a `build_only` cell compiles it and does not run it.

---

## 9. Upstream's precision wrappers are pre-generated, and this build uses them

**Condition.** `src/src/wrapper/*.c` exists as a directory of 88 files, and
upstream has a `wrappers` custom target that generates them
(`src/CMakeLists.txt:649-651`).

**Symptom.** A reader could reasonably assume the build must run
`GenerateWrappers.cmake` first. It must not: all 88 files ship in the tarball
with digests in `UPSTREAM.sha256`, each being a `#define BITS_IN_JSAMPLE` plus
an `#include "../<parent>.c"` (for example `src/src/wrapper/jccolor-8.c:12-14`).
Running the generator would write into `src/`, which this package never does.

**Fix.** Compile the shipped wrappers as they are. 71 of the 88 are in
`JPEG_SOURCES`; the other 17 are the reader and writer wrappers the excluded
tools would have used. The count is stated in UPSTREAM.md so a later wave does
not re-derive it.

**Targets bound.** All six. The wrapper set is fixed by the tarball, and
`BITS_IN_JSAMPLE` comes from the file's own `#define`, not from a generated
header.

---
## 10. The 53-platform matrix, as observed

**Condition.** AGENTS.md §6 requires `cross-test` over the full published
53-platform matrix from the package root, and this package ships
`cross-test.profile.sh` for exactly that.

**Symptom — and entry 5 is now partly superseded.** The worker ran it: run id
`20261005-191619-21172-4913`, **53 targets**, harness **exit code 1** after
1610 s, harness counts `pass 20, fail 14, build_only 19, partial 0`, no
per-phase timeout, `bookkeeping_failure false`. 300 tests executed, 15 on each
of the 20 executing cells, all under QEMU user mode except `x86_64-linux`
(native).

**Entry 5 is answered, and not in the direction it predicted.** `wasm32-wasi`
is **not** refused and does not fail. It compiled the whole 98-unit archive
(`compile lib jpeg Debug wasm32-wasi success 2m`), translated the facade
(`translate-c success`), linked the test binary, and then **skipped** the run
because the host has no wasmtime. That is a `build_only` cell — compiled,
never executed, never a pass. Entry 5's open question ("whether Zig's
wasm32-wasi libc supplies `<stddef.h>`, `<stdlib.h>`, `<stdio.h>` and
`<string.h>`", `jinclude.h:36-39`) is answered **yes**, with the qualifier that
nothing was executed. The refusal machinery never fired on any cell:
`refused_check_targets` (`build.zig:415`) is empty, `refusalFor`
(`build.zig:1506-1513`) returns `null` for every OS, and no log contains
`refusing to build`. So the count of `refused` cells is **0**, and entry 5's
"unknown" becomes **observed: builds, unrun**.

Entry 6's "no gate has been run" now describes the pre-matrix state. What is
observed so far is this matrix, and nothing else in this file.

**The 14 failing cells are an aro limitation, not a defect in this package.**
Every one fails in the `translate-c` step — Zig 0.16.0's **aro** translator.
**`compile lib jpeg` succeeded on all 14**, so the 98-unit C closure compiles
for every BSD target; it is the header-to-Zig translation that does not. All 14
reproduce from a translation unit containing no libjpeg-turbo source at all:

```sh
printf '#include <stddef.h>\n#include <stdio.h>\nint main(void){return 0;}\n' > /t.c
"$ZIG" translate-c -target <target> -lc /t.c
```

Run over the whole matrix, that reproduces **exactly these 14 and no others**.
Three distinct causes, all inside the pinned toolchain's own headers:

1. **NetBSD `_Pragma` (9 cells):** `aarch64-netbsd`, `aarch64_be-netbsd`,
   `arm-netbsd`, `armeb-netbsd`, `mips-netbsd`, `mipsel-netbsd`,
   `powerpc-netbsd`, `x86-netbsd`, `x86_64-netbsd`.
   `lib/libc/include/generic-netbsd/stdio.h:151` uses `__END_DECLS`, which
   `sys/cdefs.h:431-432` maps to `__END_PUBLIC_DECLS`, which
   `sys/cdefs.h:413` defines as `__END_EXTERN_C _Pragma("GCC visibility pop")`.
   aro expands the `_Pragma` into a scratch buffer and then lexes the resulting
   `#pragma GCC visibility pop` as an identifier, giving
   `unknown type name 'pragma'`. A bare `_Pragma` and `#include <sys/cdefs.h>`
   both translate fine; `__END_DECLS` used directly does not.
2. **OpenBSD `size_t` (3 cells):** `arm-openbsd`, `powerpc-openbsd`,
   `x86-openbsd`. aro injects **its own** `lib/compiler/aro/include/stddef.h:8`
   (`typedef __SIZE_TYPE__ size_t`) and
   `lib/libc/include/generic-openbsd/sys/types.h:171-174` then redefines
   `size_t` from `__size_t`: `typedef redefinition with different types`.
   Both headers are needed — `stdio.h` alone and `sys/types.h` alone each
   pass, and only the pair fails. That is why `x86_64-openbsd`,
   `aarch64-openbsd`, `powerpc64-openbsd` and `riscv64-openbsd` are unaffected.
3. **OpenBSD mips64 endianness (2 cells):** `mips64-openbsd`,
   `mips64el-openbsd`. `lib/libc/include/generic-openbsd/mips64/endian.h:36-40`
   `#error`s without `__MIPSEL__` or `__MIPSEB__`. clang predefines them
   (`zig cc -dM -E` shows `__MIPSEL__` for `mips64el-openbsd`, `__MIPSEB__` for
   `mips64-openbsd`); aro predefines neither, probed directly.

**Fix.** None here, and deliberately so. The identical source and target
translate cleanly under `zig cc` (clang) and fail under `translate-c` (aro) for
`x86-openbsd`, `x86-netbsd` and `mips64el-openbsd` alike — the headers are
sound, the translator is not. The gap is upstream of this package: aro's
`_Pragma` handling, its bundled `stddef.h` injection, and its mips64 predefined
macros. Patching `zig/translate.h` to dodge it would hide a toolchain defect
behind a fork-local shim.

`refusalFor` keys on **OS tag only**, and the gap is **per target**:
`x86_64-openbsd`, `aarch64-openbsd`, `powerpc64-openbsd`, `riscv64-openbsd` and
every FreeBSD cell build. An `.openbsd` or `.netbsd` refusal would be false and
would drop passing cells, so `refused_check_targets` stays empty and this entry
is the record. `checkMatrixPartition` (`build.zig:1534`) still enforces that the
table and the decision function agree.

**Targets bound.** Exactly 14 of the 53 matrix cells, listed above, and only
under Zig 0.16.0's aro. None of the six `check_targets` (`build.zig:397-404`)
is in the failing set, so this does not touch the six-target compile matrix. A
toolchain that fixes aro changes the bound; re-run the reproduction above to
find out. The 20 `pass` and 19 `build_only` cells are bound to this host's
runner set: add a runner and a `build_only` cell becomes executable, which is a
different claim from this one.

**Receipts.** Summary
`$HOST_SCRATCH_ROOT/scratch/foundation-libs/cross/libjpeg-turbo/cross-test-summary.json`,
per-run directory
`$HOST_SCRATCH_ROOT/scratch/foundation-libs/cross/libjpeg-turbo/runs/20261005-191619-21172-4913/`
(53 build logs + `summary.json`), and the written summary with the full
per-cell table at
`$HOST_SCRATCH_ROOT/scratch/foundation-libs/cross/libjpeg-turbo/CROSS-TEST-SUMMARY.md`.

---

## 11. Open questions after the matrix

Entry 5 is answered above; entry 10 records it. Still open, and still
`SOURCE-CONFIRMED`-only:

* Does `jconfig.zig` need `@SIZE_T@` per target rather than per build? Entry 3
  says it does. The matrix does not answer it, because no cell compared two
  targets' generated `jconfig.h` against each other.
* What does the first observed `zig build` report as the package fingerprint?
  Entry 4. Still not observed.
* Does `jerror.c:27`'s include of `jversion.h` resolve before or after
  `jconfig.h` on the include line? Entry 3's ordering claim is about
  `jinclude.h`'s bare-name includes; `jerror.c:25-28` includes `jinclude.h`
  first, so it should, but no compile has confirmed it.

`zig build check` itself has **not** been run for this package, so entry 5's
original wording ("what does `zig build check` print for `wasm32-wasi`") is
answered for the `test` step only. The `check` step over the six targets is
still unobserved.
