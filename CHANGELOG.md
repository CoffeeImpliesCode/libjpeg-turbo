# CHANGELOG

Numbered entries for the libjpeg-turbo SDK. Each entry names what changed, why,
and what its status is.

`STATUS`: entries below are **`PENDING-VERIFICATION`** or **`OBSERVED`**. Entry 2
records the one gate a worker has run — the 53-platform `cross-test` matrix —
and it is `OBSERVED`, red included. No other gate has been run for this package:
no `zig build`, no `test`, no `smoke`, no `check`, no installed-C check, no
consumer run. The source citations are `SOURCE-CONFIRMED` reads of files in this
repository; build results that do not exist are not claimed at all.

Only the driver moves an entry to `VERIFIED`, and only beside an observed run
recording command, optimize mode, target, exit code, date and receipt path.

---

---

## 1. 2026-10-05 — initial import of libjpeg-turbo 3.2.0

The first entry: this repository did not exist before it.

**Pinned upstream.** libjpeg-turbo **3.2.0**, GitHub release tag `3.2.0`,
published **2026-06-30**, from
`https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.2.0/libjpeg-turbo-3.2.0.tar.gz`,
**2537858 bytes**, sha256
`6f30092cef9fb839779646608f4ee14ae3cbac989c47fa05e841b0841f09878e`.

**Import mechanism.** A release archive, imported whole. This is not a Git
checkout: there is no upstream history in `src/`, no tag object and **no commit
SHA recorded or invented**. The tag string and the release date come from the
package brief; the commit behind the tag is not observed in any file here.
`UPSTREAM.md` says so in as many words rather than leaving a reader to infer it.

**Vendored scope.** All **613 files**, 9246273 bytes after extraction, into
`src/`, verified byte-identical to the extracted tarball by `diff -rq`. Nothing
is dropped for size and nothing is dropped for being uncompiled. Per-file
digests are in `UPSTREAM.sha256`, which is the complete set.

**Native source.** **Unchanged.** No portability patch, no reformatting, no
comment edit. `README.upstream.md` is a byte copy of upstream's `src/README.md`,
17722 bytes, sha256
`a44ba17ac66c57edaf0ea7c6e4b31358f08322c780e4e6af092082abb3e20793`, confirmed
with `cmp`.

**Build.** Hand-written Zig 0.16.0 build script; no CMake, no autotools, no
build-time download, no system library and **no sibling dependency**
(`.dependencies = .{}`). The library is the **98 units of `JPEG_SOURCES`** at
`src/CMakeLists.txt:653-690` — 27 direct and 71 pre-generated precision
wrappers. The C artifact is named `jpeg`, as upstream names it, giving
`libjpeg.a` and `libjpeg.so.62.4.0` with soname `libjpeg.so.62` — the numbers
upstream computes at `src/sharedlib/CMakeLists.txt:58-59`. Four public headers
installed, as upstream installs them at `src/CMakeLists.txt:2065-2069`.

**Decisions, each recorded in `FORK-NOTES.md` with its boundary:**

1. **No SIMD.** `WITH_SIMD` undefined, nothing under `src/simd/` compiled,
   `SIMD_ARCHITECTURE NONE`. x86/x86-64 SIMD is NASM (56 `.asm` under
   `src/simd/i386/`, 35 under `src/simd/x86_64/`) and Zig 0.16.0 has no NASM;
   the ARM, PowerPC, MIPS/LSX and RISC-V families are C with intrinsics and are
   excluded because CMake **generates** `simd/arm/neon-compat.h` from probes it
   runs itself (`src/simd/CMakeLists.txt:349`, `:289-333`), so porting the
   selection would mean inventing configuration. This is the configuration
   upstream itself falls back to (`src/simd/CMakeLists.txt:1-10`, `:53-61`).
   **No parity claim with the full-speed x86 build is made.**
   `build.zig`'s `-Dsimd` accepts `c` and nothing else, and says why.
2. **No command-line tools.** `cjpeg`, `djpeg` and `jpegtran` are gated by
   `WITH_TOOLS` and need the bundled zlib, libspng and the BMP/GIF/Targa/PNG
   readers (`src/CMakeLists.txt:884-927`). The library is the deliverable.
3. **No arithmetic coding and no profiling.** `jcarith.c`, `jdarith.c` and
   `tjutil.c` excluded; `WITH_ARITH_ENC`, `WITH_ARITH_DEC` and `WITH_PROFILE`
   off.
4. **Three headers generated**, from upstream's own `.in` templates by
   `tools/jconfig.zig`, per target, into the build cache and placed before
   `src/src/` on every include line: `jconfig.h`, `jconfigint.h` and
   `jversion.h`. `@SIZE_T@` comes from the target being built, never from the
   generator host.
5. **`.fingerprint` deliberately absent** from `build.zig.zon`. The toolchain
   derives it, no gate has run, and an invented identifier is not permitted. The
   first observed `zig build` supplies it.
6. **No lock files.** `flake.lock` and `devenv.lock` are absent; the driver
   owns them and neither is invented here.

**Fixtures.** Four JPEG files written by `tools/make-fixtures.py` from ITU-T
T.81, using **no image library** — the JFIF `APP0`, all-ones quantisation
tables, a baseline `SOF0`, the four Annex K `DHT` tables, `SOS`,
entropy-coded data with `0xFF 0x00` stuffing, and `EOI` are assembled by hand.
The expected decoded samples are therefore hand-computed rather than recorded:
`grey8x8-200.jpg` decodes to exactly 200 everywhere; `grey16x16-halves.jpg` to
exactly 0 in rows 0–7 and 255 in rows 8–15; `rgb8x8-grey64.jpg` to exactly
(64, 64, 64) and `rgb8x8-grey200.jpg` to exactly (200, 200, 200). The arithmetic
is in `UPSTREAM.md`.

| File | sha256 | Bytes |
|---|---|---:|
| `fixtures/grey16x16-halves.jpg` | `b2e2490ff88768780f7e48f1739d1a608dfc7b5c17a54c2665db29db8b51f4bf` | 555 |
| `fixtures/grey8x8-200.jpg` | `f7f10aee901395fe1a12f424cd8d91f9bf2e181642cf0ab069b406d938cb9e2d` | 549 |
| `fixtures/rgb8x8-grey200.jpg` | `e31f0659abba47da10e4600fde1a3da25afdcacee2f1dde5029aeddade972b98` | 629 |
| `fixtures/rgb8x8-grey64.jpg` | `0704223b42ce860b9a28892da837fa160de3603ebd6cc8cd385dbb8a71f18684` | 629 |

**Licence.** Recorded **per file**, because one label would be wrong.
libjpeg-turbo is dual: the **IJG License** (`src/README.ijg:126-157`,
`src/LICENSE.md:6-11`) for the libjpeg API library, the **Modified (3-clause)
BSD License** (`src/LICENSE.md:119-147`, `:13-24`) for the TurboJPEG API
library, libspng and the build/test system, the **zlib** term for the SIMD
sources subsumed by the IJG terms in the libjpeg context
(`src/LICENSE.md:37-40`), and a fourth **multi-author BSD-2-style** notice in
`src/simd/jsimd.h:1-21` and `src/simd/jsimd.c:1-31` that upstream's own roll-up
does not enumerate. `NOTICE.md` carries the inventory; `FORK-LICENSE.md` carries
the owner-authorized **MIT** grant for the fork's own files, and states that no
upstream source was copied into any of them.

**Verification scripts.** `tools/check-provenance.sh` checks the 613 digests,
the exact file set against `find src -type f`, agreement of the release digest
between `UPSTREAM.md` and `UPSTREAM.sha256`, `README.upstream.md` against
`src/README.md`, all four licence notices where `NOTICE.md` says they are, and
the fixture digests via `tools/check-fixtures.py`. Neither script compiles
anything. **Neither has been run.**

**Status.** `PENDING-VERIFICATION`, in full. Gates still owed: `zig build`,
`zig build test` in Debug and ReleaseSafe, `zig build smoke`, `zig build check`
over the six targets, `tools/check-provenance.sh`, and `zig build run` in
`consumer/`. `wasm32-wasi` is recorded as **unknown** rather than as either
working or refused, because nothing has been attempted.

---

## 2. 2026-10-05 — 53-platform `cross-test` matrix run

**`OBSERVED`. Red. Not `VERIFIED`.**

**Command.** `cross-test --jobs 8 --build-jobs 8 --output
"$HOST_SCRATCH_ROOT/scratch/foundation-libs/cross/libjpeg-turbo"`, run from the
package root, against this package's own `cross-test.profile.sh` (read, **not**
edited), build step `test`, Zig **0.16.0** at
`$ZIG_GLOBAL_CACHE_DIR/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/zig`.

**Result.** Run id `20261005-191619-21172-4913`, **exit code 1**, 1610 s,
**53 targets**, `bookkeeping_failure false`, no per-phase timeout. Cells:
**20 `pass`** (built and executed, 15 tests each, 300 executed in total),
**19 `build_only`** (built, never executed, no runner on this host),
**14 `build_fail`**, **0 `refused`**, **0 `runtime_fail`**.

**`wasm32-wasi` builds.** It is not refused and does not fail. The matrix
compiled the full 98-unit C archive, translated the facade, and linked the test
binary; the run step was skipped for want of a wasmtime. That is a `build_only`
cell, so entry 1's "recorded as **unknown**" and FORK-NOTES.md entry 5's open
question are both superseded **for the `test` step**. `zig build check` for
`wasm32-wasi` remains unobserved, and the package's refusal machinery
(`build.zig:415`, `build.zig:1506-1513`) refuses nothing — no log contains
`refusing to build`.

**14 failures, all BSD, all in `translate-c`.** `compile lib jpeg` **succeeded**
on all 14, so the 98-unit C closure compiles for every one; it is Zig's aro
translator over the toolchain's own headers that fails. Every one reproduces
from a translation unit holding no libjpeg-turbo source, and the same source
translates cleanly under `zig cc` (clang). Causes, named with file and line, are
in FORK-NOTES.md entry 10: NetBSD `_Pragma` (9 cells), OpenBSD `size_t` (3),
OpenBSD mips64 endianness (2).

**No source changed.** This entry is a record, not a patch. `zig/translate.h`,
`build.zig` and the profile are untouched, and the workaround that would hide a
toolchain defect behind a fork-local shim was deliberately not taken.

**Receipts.** Summary
`$HOST_SCRATCH_ROOT/scratch/foundation-libs/cross/libjpeg-turbo/cross-test-summary.json`;
53 per-target logs in
`$HOST_SCRATCH_ROOT/scratch/foundation-libs/cross/libjpeg-turbo/runs/20261005-191619-21172-4913/`;
written summary with the full per-cell table at
`$HOST_SCRATCH_ROOT/scratch/foundation-libs/cross/libjpeg-turbo/CROSS-TEST-SUMMARY.md`.

**Still owed.** `zig build`, `zig build test` in Debug and ReleaseSafe,
`zig build smoke`, `zig build check` over the six targets,
`tools/check-provenance.sh`, and `zig build run` in `consumer/`.

## 3. 2026-10-05 — `UPSTREAM.md` names the IJG (Independent JPEG Group) License

`UPSTREAM.md:66` now says which licence `src/README.ijg` carries instead of
listing it only as "upstream's build system and its own records", and
`UPSTREAM.md:76-101` adds a subsection quoting `src/LICENSE.md:1-11` verbatim.

**Why.** `tools/check-provenance.sh:196-198` asserts `Independent JPEG Group`
in `NOTICE.md`, `README.md`, `UPSTREAM.md` and `FORK-LICENSE.md`. Three carried
the term; `UPSTREAM.md` did not, so the record that names what was imported was
the one that could not say which of upstream's two licences `README.ijg` holds.
A reader of the tarball table had no way to tell that the libjpeg API library
this package compiles is under the IJG terms rather than the Modified BSD ones.

The quoted lines are `src/LICENSE.md:1-11` copied out, including
`- The IJG (Independent JPEG Group) License, which is listed in
[README.ijg](README.ijg)` and "This license applies to the libjpeg API library
and associated programs, including any code inherited from libjpeg and any
modifications to that code." No licence name was paraphrased, and no text under
`src/` was edited.

**What this does not prove.** Only the provenance record. It does not touch the
53-platform matrix in entry 2, and the still-owed list there — `zig build`, the
two `test` runs, `smoke`, `check`, `tools/check-provenance.sh` and the consumer
run — is unchanged by this entry.
