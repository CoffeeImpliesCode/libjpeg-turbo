# Fork notes

## Upstream source deviations

No files under `src/` are modified. Fork-authored files add the Zig-facing build and API:

- `tools/jconfig.zig` generates the three configuration headers from upstream templates per target, replacing CMake's `configure_file` step.
- `zig/root.zig` exposes the translated C API as a Zig module.
- `zig/translate.h` aggregates public headers for C-to-Zig translation.
- `tests.zig` and `smoke.zig` exercise the facade without building upstream's test applications.

## Build graph

- `build.zig` compiles the 98-unit portable C library as artifact `jpeg`; it generates `jconfig.h`, `jconfigint.h`, `jversion.h`, and `libjpeg.pc` in the build graph.
- The build compiles 71 shipped precision wrappers directly; it does not run upstream's wrapper generator or write into `src/`.
- `-Dlinkage` selects static (default) or shared output. `-Druntime=true` selects the runtime-dispatch facade. System-library mode is refused.
- `-Dsimd` accepts only `c`. The graph disables arithmetic coding, profiling, TurboJPEG, command-line tools, upstream tests, and JPEG 7/8 extensions; the public API remains libjpeg v6.
- `cjpeg`, `djpeg`, and `jpegtran` are omitted because their reader paths require bundled zlib and libspng. The package has no external package dependencies.
- The nested consumer build keeps its own install prefix; Zig 0.17 exposes the outer prefix only at make time.
- `tools/consumer.zig` forwards the global cache and Zig library directory through environment variables; Zig 0.17's build command rejects the old directory flags.
- The nested consumer requires `-Dconsumer-libc-runtimes=<path>` for cross-libc execution; Zig 0.17 exposes `--libc-runtimes` only at make time.
- The declared `check` targets are x86_64 Linux, aarch64 Linux, aarch64 macOS, x86_64 Windows GNU, riscv64 Linux, and wasm32-wasi.

## Platform boundaries

- SIMD is disabled on every target. x86 SIMD requires NASM; the other intrinsic implementations need CMake-generated capability probes that this graph does not reproduce.
- Zig 0.16 `translate-c` fails on 14 BSD targets: nine NetBSD targets (`aarch64`, `aarch64_be`, `arm`, `armeb`, `mips`, `mipsel`, `powerpc`, `x86`, `x86_64`) due to `_Pragma`; OpenBSD `arm`, `powerpc`, and `x86` due to `size_t` redefinition; and OpenBSD `mips64`/`mips64el` due to missing endianness macros. These are translator/header-boundary failures, not C-library source failures (observed with Zig 0.16; not rechecked on 0.17).
- `wasm32-wasi` compiles and links the test binary; executing it requires `wasmtime`.
