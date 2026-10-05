# cross-test settings profile for the libjpeg-turbo SDK.
#
# `cross-test` looks for this file at the root of the project it is run from
# (or names it with --profile; --no-profile ignores it). It is trusted Bash that
# the harness `source`s, so this file is *settings only*: ordinary variable
# assignments and nothing else. No command runs, no compiler is probed, and no
# path in here names a host.
#
# There is deliberately no CROSS_MATRIX. The published 53-platform Zig 0.16
# Tier 1/2 table is the matrix this package is checked against, and a matrix
# named here would replace it. There is no TARGETS array either, for the same
# reason: a subset selected here would narrow the run rather than add to it.
# Both belong on the command line, where --targets selects from the active
# matrix and never adds to it.
#
# CROSS_BUILD_STEP stays the standard `test` step, which is what this profile
# states explicitly. There are no `cross_build_command` / `cross_artifact`
# hooks here, so the harness keeps its standard Zig-build mode and runs
# `zig build test -Dtarget=TARGET` per target with a fresh cache. What that
# means for a given target is the harness's decision, not this package's: a
# host target runs, a foreign target runs under whatever executor the harness
# detects (QEMU user mode, Wine, wasmtime), and a foreign target with no
# executor is reported as build-only coverage -- compiled, never executed, and
# never counted as a pass. `build.zig` gives the test binary a Run step for
# every target, which is what leaves that choice open.
#
# A target graph compiles the whole 98-unit closure of `JPEG_SOURCES`
# (`src/CMakeLists.txt:653-690`), runs `tools/jconfig.zig` to produce
# `jconfig.h`, `jconfigint.h` and `jversion.h` *for that target*, translates
# `zig/translate.h`, and links the facade and the test root. Keep a few build
# jobs available: libjpeg-turbo's precision wrappers each include a parent
# translation unit, so every matrix cell compiles effectively the whole of
# `src/src/` again at 8, 12 and 16 bits, and this is the largest compile in the
# tree per cell.
#
# Nothing here narrows the gate to what is expected to work. Every cell
# compiles the portable C configuration on every target, and a cell that fails
# is a fact to record and diagnose; it is not a reason to drop the cell, sample
# the tests or remap Debug to an optimized mode to make it pass.
#
# One thing this profile deliberately does NOT do: it does not narrow the
# matrix on account of the non-SIMD configuration. No SIMD target is excluded
# and no SIMD target is added -- `WITH_SIMD` is undefined everywhere, so there
# is no architecture whose cell means something different from the others. See
# FORK-NOTES.md entry 1 for that boundary, and note that a cell with no runner
# stays `build_only` rather than becoming a pass.

CROSS_BUILD_STEP=test
CROSS_BUILD_JOBS=4
CROSS_BUILD_TIMEOUT=3600
CROSS_TIMEOUT=1800
