# The Zig interface

How the libjpeg-turbo 3.2.0 SDK is consumed from Zig and from C: the module
route, the raw translated route, the runtime route, the installed layout, and
what the tests actually prove.

**No gate has been run for this package.** Nothing described here has been
built, executed or cross-compiled. Every route below is documented as it is
specified, not as it is observed, and no example in this file has been run.

## The module

```zig
// build.zig.zon, in the dependent:
.dependencies = .{ .libjpeg_turbo = .{ .path = "../libjpeg-turbo" } },
```

```zig
// build.zig, in the dependent:
const jpeg_turbo = b.dependency("libjpeg-turbo", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("libjpeg_turbo", jpeg_turbo.module("libjpeg_turbo"));
```

Two names, and they are not interchangeable:

* **`libjpeg_turbo`** is the Zig *module* name — `dep.module("libjpeg_turbo")`,
  then `@import("libjpeg_turbo")` in source. The underscore is a Zig identifier
  spelling; the directory is `libjpeg-turbo` and the dependency-map key is
  `"libjpeg-turbo"`.
* **`jpeg`** is the *C artifact* name — `dep.artifact("jpeg")`. It is upstream's
  own name (`src/CMakeLists.txt:770` `OUTPUT_NAME jpeg`), and it is what Zig
  emits as `libjpeg.a` / `libjpeg.so.62.4.0`.

### `pub const c` — the raw escape hatch

`zig/root.zig` exposes the translated C declarations as `pub const c`. This is
the *raw* route: every declaration `translate-c` produced from
`zig/translate.h`, with upstream's own signatures and its own error-manager
conventions. Nothing is renamed, nothing is wrapped, and nothing is defaulted.

```zig
const jpeg_turbo = @import("libjpeg_turbo");
const c = jpeg_turbo.c;
```

What `c` carries is exactly what `zig/translate.h` names:
`<stddef.h>`, `<stdio.h>`, the generated `<jconfig.h>`, and upstream's three
public headers `jmorecfg.h`, `jpeglib.h`, `jerror.h`. The `<stdio.h>` is not
decoration — `src/jpeglib.h:21-29` states that the header deliberately does not
include it while using `FILE` and `size_t`, so a consumer must. An installed C
consumer has the same obligation:

```c
#include <stdio.h>    /* jpeglib.h uses FILE and does not include stdio.h */
#include <jpeglib.h>
#include <jerror.h>
```

The typed facade sits on top of `c` rather than beside it, so anything the
facade does not cover is still reachable.

### The typed facade

`pub const` and `pub fn` in `zig/root.zig` cover the lifecycle
(`Compress`, `Decompress`), the error manager (`StdError`), the destination and
source managers (`MemDest`, `MemSrc`), the parameter setters and the
coefficient accessors. Every one of them is a thin call into `c` — the facade
owns names and types, not behaviour.

The lifecycle declaration is in `zig/root.zig`:

```zig
pub const c = @import("c");
pub const runtime_loaded: bool = ...;   // comptime
pub const load = ...;
pub const loadedSource = ...;
pub const unload = ...;
pub const LoadSource = ...;
pub const LoadError = ...;
```

`LoadSource` and `LoadError` are re-exported from the `rt` module.

### One worked example

Decode `fixtures/grey8x8-200.jpg` and check the result against the
hand-computed answer in [`UPSTREAM.md`](UPSTREAM.md) — every sample exactly 200.
This is the shape of the route, not a claim that it has been run.

```zig
const jpeg_turbo = @import("libjpeg_turbo");

pub fn main() !void {
    // The fixture's bytes, embedded rather than read from a path: a test that
    // needs a working directory is a test that can pass for the wrong reason.
    const bytes = @embedFile("grey8x8-200.jpg");

    var err = jpeg_turbo.jpeg_std_error();
    var cinfo: jpeg_decompress_struct = undefined;
    err.create_decompress(&cinfo);
    defer err.destroy_decompress(&cinfo);

    var src = jpeg_turbo.MemSrc.init(&cinfo, bytes);
    cinfo.src = &src.pub;
    err.read_header(&cinfo);
    err.start_decompress(&cinfo);

    // 8x8, one component, so cinfo.output_scanline runs 0..7 and each call
    // returns one row of eight samples.
    var row: [8]u8 = undefined;
    var scanline: usize = 0;
    while (cinfo.output_scanline < cinfo.output_height) {
        const got = err.read_scanlines(&cinfo, &row, 1);
        if (got != 1) return error.ShortScanline;
        // The known answer, from arithmetic and not from this decoder.
        for (row) |sample| {
            if (sample != 200) return error.UnexpectedSample;
        }
        scanline += 1;
    }
    if (scanline != 8) return error.UnexpectedHeight;

    err.finish_decompress(&cinfo);
}
```

### The C route

```zig
const jpeg_turbo = b.dependency("libjpeg-turbo", .{
    .target = target,
    .optimize = optimize,
});
exe.addCSourceFile(.{
    .file = b.path("main.c"),
    .flags = &.{ "-std=c11" },
});
exe.linkLibrary(jpeg_turbo.artifact("jpeg"));
// The public headers, translated or not:
exe.addIncludePath(b.path("src/src"));
```

The generated `jconfig.h` lives in a build-cache directory, so a C source file
that includes `<jpeglib.h>` needs that directory on its include line too —
`jpeglib.h:41-42` includes `"jconfig.h"` by bare name. The installed tree
already has it in `include/`, which is why `zig build install` needs no flag
to make a C consumer work.

For an already-installed copy, `libjpeg.pc` carries what a build system needs:

```
Name: libjpeg
Description: A SIMD-accelerated JPEG codec that provides the libjpeg API
Version: 3.2.0
Libs: -L${libdir} -ljpeg
Cflags: -I${includedir}
```

The fields are upstream's own, from `src/release/libjpeg.pc.in:6-10`. The
description string is upstream's wording and says "SIMD-accelerated"; this SDK
builds the non-SIMD configuration, and the field is preserved rather than
rewritten because it identifies the *library*, whose upstream README makes the
same claim for every configuration upstream ships.

## The installed layout

```
include/jconfig.h       generated
include/jerror.h
include/jmorecfg.h
include/jpeglib.h
lib/libjpeg.a                            (default, static)
lib/libjpeg.so.62.4.0                    (-Dlinkage=dynamic)
lib/libjpeg.so.62 -> libjpeg.so.62.4.0   soname symlink
lib/pkgconfig/libjpeg.pc
share/licenses/libjpeg-turbo/
```

Four public headers, exactly as upstream installs them
(`src/CMakeLists.txt:2065-2069`). `jconfig.h` is the generated one; the other
three are upstream's files, unaltered.

`share/licenses/libjpeg-turbo/` carries `README.ijg` and `src/LICENSE.md` —
upstream's own texts, unaltered — so a consumer of the installed tree can
discharge the IJG clause (1) obligation without a separate download.

The soname is `libjpeg.so.62`: upstream computes `SOVERSION 62` and
`VERSION 62.4.0` at `src/sharedlib/CMakeLists.txt:58-59` from `SO_MAJOR_VERSION`
62, `SO_AGE` 4 and `SO_MINOR_VERSION` 0
(`src/CMakeLists.txt:373-397`, `:408-413`), with `WITH_JPEG7`/`WITH_JPEG8` both
at their default `FALSE`.

## The runtime route

`-Druntime=true` builds the same library and routes the native calls through
one process-lifetime dispatch table instead of linking against it.

```sh
zig build -Druntime=true
```

```zig
const jpeg_turbo = @import("libjpeg_turbo");

pub fn main() !void {
    if (jpeg_turbo.runtime_loaded) {
        // Explicit selection: no fallback, no probe order, no guessing.
        try jpeg_turbo.load(.{ .path = "/usr/lib/x86_64-linux-gnu/libjpeg.so.62" });
        defer jpeg_turbo.unload();
    }
    // Every call below is identical in both linkages.
}
```

The rules, which hold in every optimization mode:

* **one table per process**, not one per call site;
* **explicit selection** — `.path` or `.system`, never a search order the
  consumer did not ask for;
* **no fallback** — a failed load returns an error, it does not quietly bind the
  linked library instead;
* **atomic publication** — a partially filled table is never observable;
* **explicit retry** after a failed load, because a failed load is not a
  permanent condition;
* an **ordinary panic** before initialization in every optimize mode —
  `std.debug.assert` is compiled out in ReleaseFast and would leave the failure
  silent, so it is not used for this.

### What a loaded provider must match

Resolving the symbols proves the shared object has those names. It says nothing
about whether the provider and this build agree about anything else:

* the **struct layouts** of `jpeg_compress_struct` and
  `jpeg_decompress_struct` must match, which means the same `sizeof(JSAMPLE)`,
  the same `J_COLOR_SPACE` and `J_DCT_METHOD` enumerations and the same
  `JDIMENSION`/`JSAMPLE` widths;
* the **error-manager contract**: `cinfo->err->error_exit` is a
  `void (*)(jpeg_common_ptr)` that must not return
  (`src/jpeglib.h`, the `error_exit` declaration);
* **libjpeg-turbo exports no version symbol.** `JPEG_LIB_VERSION`,
  `LIBJPEG_TURBO_VERSION` and `LIBJPEG_TURBO_VERSION_NUMBER` are compile-time
  constants in the generated `jconfig.h`, so no loader can ask the provider
  which release it is. **This SDK therefore has no load-time version check, and
  none is invented.** What it does instead is a behavioural self-check through
  the resolved table, below.

### The ABI self-check, which is behavioural rather than a version string

Because there is no version symbol, the honest thing to check after a load is
that the provider actually works:

1. `jpeg_std_error()` returns non-NULL through the table;
2. `jpeg_CreateCompress` → `jpeg_mem_dest` → `jpeg_start_compress` →
   `jpeg_finish_compress` → `jpeg_destroy_compress` on a 1×1 greyscale image
   completes;
3. `jpeg_CreateDecompress` → `jpeg_read_header` → `jpeg_start_decompress` reads
   that image back through the same table and yields the original sample.

That is a real check and it is not a version-string comparison: a provider
whose structs disagree fails at step 2 or 3 rather than passing a `strcmp`.

## What the tests prove

`tests.zig` holds **independent known answers** and **behavioural boundaries**.
There is no upstream suite to run — upstream's test material ships inside
`src/` uncompiled, recorded in `UPSTREAM.sha256` and not deleted.

Per AGENTS.md §7, the primary expectation is an independent known answer or
recorded fixture interoperability. Four independent known answers, each
hand-computed:

| Fixture | Expectation | Where the arithmetic is |
|---|---|---|
| `grey8x8-200.jpg` | every sample exactly 200 | UPSTREAM.md, "The expected decoded samples" |
| `grey16x16-halves.jpg` | rows 0–7 exactly 0, rows 8–15 exactly 255 | same |
| `rgb8x8-grey64.jpg` | every pixel exactly (64, 64, 64) | same |
| `rgb8x8-grey200.jpg` | every pixel exactly (200, 200, 200) | same |

What is **not** in the tests, by policy:

* no test that pins a version string or a default constant — version pinning
  belongs to the provenance gate;
* no `@hasDecl` or export-presence test;
* no comparison of a forwarding accessor with its raw member;
* no copy, length or non-zero-length check;
* no "asserts it does not throw" test;
* no source-text test and no mock echo;
* a same-code round trip may **supplement** the four expectations above but
  never stands alone.

### Ownership transitions, and the allocator

`std.testing.allocator` **cannot be a leak oracle here.** libjpeg-turbo's
memory manager allocates through the C library's own allocator
(`jmemmgr.c`), and `jpeg_mem_dest`/`jpeg_mem_src` hand a buffer to the library
rather than receiving one from Zig's allocator. A test that allocated through
`std.testing.allocator` and reported "0 leaked" would be measuring the wrong
allocator and would stay silent if the library leaked its own.

So ownership is proved as a **transition**, not as a balance:

* a `jpeg_create_decompress_struct` is destroyed exactly once through
  `jpeg_destroy_decompress`, and calling it again is not what the test does —
  the test observes that the struct's own fields are back in their
  post-`destroy` state through the API that reports it;
* a compress object is destroyed exactly once after
  `jpeg_finish_compress`, and the destination buffer's length is what the
  library says it wrote;
* where a **custom allocator is installed** via
  `jpeg_mem_`-style manager overrides, the test counts that installer's own
  allocations and frees, and asserts that a completed compress-then-decompress
  cycle returns every block it was given. That path *is* a leak oracle — for
  the allocator under test, not for the C library's default one.

Stating it plainly in the test file, because a reader who did not know would
otherwise read a green allocator report as more than it is.

## Commands

See README.md, "Commands". The two that matter here:

```sh
zig build test          # the four known answers and the ownership transitions
zig build smoke         # the deterministic example
```

## Licence

`MIT` for this fork's own files ([`FORK-LICENSE.md`](FORK-LICENSE.md)); the IJG
License, the Modified (3-clause) BSD License and the subsumed component terms
for everything under `src/` ([`NOTICE.md`](NOTICE.md)).
