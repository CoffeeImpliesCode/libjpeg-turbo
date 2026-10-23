# libjpeg-turbo

This package exposes the libjpeg API from libjpeg-turbo 3.2.0 as a standalone Zig SDK.
It requires Zig 0.16.0 and links libc only.

## Source deviations from upstream

The complete upstream 3.2.0 release tree is under `src/`; no upstream source file
was removed or modified. `UPSTREAM.md` records the archive identity, and
`UPSTREAM.sha256` records the per-file digests. Upstream's project README is
preserved separately as `README.upstream.md`.

## Build deviations

The Zig build graph replaces upstream's CMake build. It builds the libjpeg API
only; it does not compile TurboJPEG, the command-line tools, or upstream test
programs.

The portable C configuration is the only configuration built. `WITH_SIMD` is
undefined and `SIMD_ARCHITECTURE` is `NONE`. x86 SIMD requires NASM; the other
SIMD families need CMake-generated probe results that this build does not
reproduce. No SIMD source is compiled.

`WITH_ARITH_ENC`, `WITH_ARITH_DEC`, `WITH_TOOLS`, `WITH_TESTS`, and
`WITH_TURBOJPEG` are off. `WITH_PROFILE`, `WITH_JPEG7`, and `WITH_JPEG8` remain
at upstream's default `FALSE`.

The build generates `jconfig.h`, `jconfigint.h`, and `jversion.h` from upstream
templates for each target. Target-dependent values, including `sizeof(size_t)`,
come from the target being built.

## Support matrix

`zig build check` is configured to compile these targets; the step does not run
foreign executables.

| Target | Library linkage | Runtime loading |
|---|---|---|
| `x86_64-linux-gnu` | static or dynamic | available |
| `aarch64-linux-gnu` | static or dynamic | available |
| `aarch64-macos-none` | static or dynamic | available |
| `x86_64-windows-gnu` | static or dynamic | available |
| `riscv64-linux-gnu` | static or dynamic | available |
| `wasm32-wasi` | static only | unavailable |

On WASI, requesting dynamic linkage delivers the static archive. The runtime
loader is unavailable on WASI, Emscripten, and freestanding targets.

## Consumption

### Zig dependency

In the dependent's `build.zig.zon`:

```zig
.dependencies = .{
    .@"libjpeg-turbo" = .{ .path = "../libjpeg-turbo" },
},
```

In `build.zig`, the package key uses a hyphen; the Zig module name uses an
underscore:

```zig
const dep = b.dependency("libjpeg-turbo", .{
    .target = target,
    .optimize = optimize,
    .linkage = .static,
    .runtime = false,
    .simd = "c",
});
exe.root_module.addImport("libjpeg_turbo", dep.module("libjpeg_turbo"));
```

The module is `dep.module("libjpeg_turbo")`. The native C artifact is
`dep.artifact("jpeg")`.

### Build options

| Option | Default | Effect |
|---|---|---|
| `-Dlinkage=static` or `-Dlinkage=dynamic` | `static` | Selects the native artifact form. |
| `-Druntime=true` | `false` | Resolves native calls through an explicit process-lifetime loader. |
| `-Dsimd=c` | `c` | The only accepted SIMD configuration. |

There is no system-library mode; `-Dsystem=true` and `-fsys=jpeg` are refused.

### Installed C library

`libjpeg.a` is the static artifact. On Linux, dynamic linkage produces
`libjpeg.so.62.4.0` with SONAME `libjpeg.so.62`. The install includes
`libjpeg.pc`, the public headers `jconfig.h`, `jerror.h`, `jmorecfg.h`, and
`jpeglib.h`, and the license files under `share/licenses/libjpeg-turbo/`.

C consumers must include `<stdio.h>` before `<jpeglib.h>`; the upstream header
uses `FILE` and `size_t` without including `<stdio.h>`. See `README.zig.md` for
the Zig facade API, `NOTICE.md` for per-file licenses, and `FORK-LICENSE.md`
for this fork's files.
