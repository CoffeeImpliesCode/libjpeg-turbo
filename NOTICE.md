# Notice

Two separate things are recorded here: what the canonical native source is and
which grant covers each of its files, and what this fork wrote on top of it.
[`FORK-LICENSE.md`](FORK-LICENSE.md) carries the grant for the second group.

**libjpeg-turbo is dual-licensed, and one label for the tree would be wrong.**
`src/LICENSE.md:4` states it plainly: *"libjpeg-turbo is covered by two
compatible BSD-style open source licenses"*. The IJG terms govern the libjpeg
API library; the Modified (3-clause) BSD terms govern the TurboJPEG API
library, libspng and the build/test system; and several components carry less
restrictive terms that upstream subsumes. The inventory below is per file for
that reason.

## The upstream terms, as upstream states them

`src/LICENSE.md` is a roll-up and upstream says so itself
(`src/LICENSE.md:53-58`: *"This section provides a roll-up of the
libjpeg-turbo licensing terms… This is not a license in and of itself"*). The
authoritative texts are `src/README.ijg` and `src/LICENSE.md:119-147`.

### Term 1 — the IJG (Independent JPEG Group) License

`src/LICENSE.md:6-11`:

> - The IJG (Independent JPEG Group) License, which is listed in
>   [README.ijg](README.ijg)
>
>   This license applies to the libjpeg API library and associated programs,
>   including any code inherited from libjpeg and any modifications to that
>   code.

Full text at `src/README.ijg:126-157`, with the plain-English summary at
`:117-124`:

> 1. We don't promise that this software works. (But if you find any bugs,
>    please let us know!)
> 2. You can use this software for whatever you want. You don't have to pay us.
> 3. You may not pretend that you wrote this software. If you use it in a
>    program, you must acknowledge somewhere in your documentation that
>    you've used the IJG code.

and the legal form at `:128-157`:

> The authors make NO WARRANTY or representation, either express or implied,
> with respect to this software, its quality, accuracy, merchantability, or
> fitness for a particular purpose. This software is provided "AS IS", and you,
> its user, assume the entire risk as to its quality and accuracy.
>
> This software is copyright (C) 1991-2020, Thomas G. Lane, Guido Vollbeding.
> All Rights Reserved except as specified below.
>
> Permission is hereby granted to use, copy, modify, and distribute this
> software (or portions thereof) for any purpose, without fee, subject to these
> conditions:
> (1) If any part of the source code for this software is distributed, then this
> README file must be included, with this copyright and no-warranty notice
> unaltered; and any additions, deletions, or changes to the original files
> must be clearly indicated in accompanying documentation.
> (2) If only executable code is distributed, then the accompanying
> documentation must state that "this software is based in part on the work of
> the Independent JPEG Group".
> (3) Permission for use of this software is granted only if the user accepts
> full responsibility for any undesirable consequences; the authors accept
> NO LIABILITY for damages of any kind.

`src/README.ijg:1-5` carries a libjpeg-turbo modification note: the file has
been edited to remove material irrelevant to libjpeg-turbo, and *"It is included
only for reference."* The licence conditions are unchanged by that edit, and
clause (1) is what requires this fork to ship the file unaltered — which it
does.

**The three conditions are obligations, not decoration.** This fork ships
`README.ijg` byte-identical, which discharges (1) for the source distribution;
the installed tree ships it too, and any consumer of this SDK still owes (2)
in its own documentation if it ships only executable code.

### Term 2 — the Modified (3-clause) BSD License

`src/LICENSE.md:13-24`:

> - The Modified (3-clause) BSD License, which is listed below
>
>   This license applies to the TurboJPEG API library and associated programs,
>   [libspng](https://libspng.org) (which is used by cjpeg and djpeg), and the
>   build/test system.

Full text with the two copyright lines at `src/LICENSE.md:119-147`:

> Copyright (C) 2009-2026 D. R. Commander
> Copyright (C) 2018-2023 Randy <randy408@protonmail.com>
>
> Redistribution and use in source and binary forms, with or without
> modification, are permitted provided that the following conditions are met:
>
> - Redistributions of source code must retain the above copyright notice,
>   this list of conditions and the following disclaimer.
> - Redistributions in binary form must reproduce the above copyright notice,
>   this list of conditions and the following disclaimer in the documentation
>   and/or other materials provided with the distribution.
> - Neither the name of the libjpeg-turbo Project nor the names of its
>   contributors may be used to endorse or promote products derived from this
>   software without specific prior written permission.

`src/LICENSE.md:19-24` records the two overlap rules, which matter for anyone
reading only one of the two terms: in the context of the overall TurboJPEG API
library **both** sets of terms apply, and in the context of `cjpeg` and `djpeg`
**both** apply again.

### Term 3 — the component licences, and how upstream subsumes them

`src/LICENSE.md:27-35` states the general rule: components are covered by less
restrictive licences, and *"in the context of libjpeg-turbo as a whole, the
terms of the less restrictive licenses are subsumed by either the IJG License or
the Modified BSD License"*.

| Component licence | Upstream's statement | Citation |
|---|---|---|
| **zlib** — the SIMD sources and the bundled zlib | "covered by the zlib License, which is subsumed by the IJG License in the context of the cjpeg and djpeg programs and the libjpeg API library" | `src/LICENSE.md:37-40` |
| **PNG Reference Library License v2** — some libspng source | "subsumed by the IJG License in the context of the cjpeg and djpeg programs and the TurboJPEG API library" | `src/LICENSE.md:42-45` |
| **Simplified (2-clause) BSD** — most libspng source | "subsumed by the Modified BSD License in the context of the cjpeg and djpeg programs and the TurboJPEG API library" | `src/LICENSE.md:47-50` |

Note the guard word in the first row: the zlib term is subsumed **in the
libjpeg/cjpeg/djpeg context**. This SDK compiles the libjpeg API library, so
that is the context in which it applies, and the practical effect is that
complying with the IJG terms discharges the SIMD sources' zlib term. The
per-file notices are preserved regardless; see the inventory.

### What the roll-up adds (`src/LICENSE.md:60-117`)

Upstream states the compliance rules as a numbered roll-up that is not itself a
licence. Three of them bind this fork directly:

* `src/LICENSE.md:63-64` — *"You cannot alter or remove any existing copyright
  or license notices from the source."* This is why nothing under `src/` was
  touched, and why `tools/check-provenance.sh` re-reads the notices.
* `src/LICENSE.md:78-79` — *"You must include the IJG README file, and you must
  not alter any of the copyright or license text in that file."*
* `src/LICENSE.md:88-89` — for a binary-only distribution, product documentation
  must state: *"This software is based in part on the work of the Independent
  JPEG Group."*
* `src/LICENSE.md:102-104` — *"You cannot use the name of the IJG or The
  libjpeg-turbo Project or the contributors thereof in advertising, publicity,
  etc."* Nothing in this fork's documentation advertises with either name.

### One line of `src/README.md` that differs

Upstream's own `src/README.md:47-48` says *"three compatible BSD-style open
source licenses"*, counting the IJG licence, the Modified BSD licence and the
component terms separately. `src/LICENSE.md:4` says *"two"*. The two statements
differ in whether the subsumed component terms are counted; they do not
disagree about which terms govern which file, and this inventory follows
`src/LICENSE.md`, which is the roll-up upstream points at.

## Inventory of the upstream files

613 files, 9246273 bytes, digests in [`UPSTREAM.sha256`](UPSTREAM.sha256).

**Term column legend:** *IJG* = the IJG License (`src/README.ijg`); *BSD-3* = the
Modified BSD License (`src/LICENSE.md:119-147`); *subsumed* = a component term
upstream subsumes per Term 3, with its own notice preserved in the tree.

### The 98 compiled units

| Path | Count | Term | Notice in the file |
|---|---:|---|---|
| `src/src/*.c` in `JPEG_SOURCES` | 27 | *IJG* | the "This file was part of the Independent JPEG Group's software" block, or a libjpeg-turbo copyright block ending in *"For conditions of distribution and use, see the accompanying README.ijg file"* |
| `src/src/wrapper/*.c` in `JPEG_SOURCES` | 71 | *IJG* | the D. R. Commander block, ending in the same README.ijg pointer (e.g. `src/src/wrapper/jccolor-8.c:1-10`) |
| `src/src/jinclude.h`, `jpeglib.h`, `jmorecfg.h`, `jerror.h`, `jmemmgr.c`, the internal headers | — | *IJG* | the IJG block, each ending in the README.ijg pointer |

The wrappers carry a **shorter** notice than their parents: they are new
libjpeg-turbo files, so they name only the libjpeg-turbo author and point at
`README.ijg`, and they do **not** claim IJG authorship. That is upstream's own
wording and it is preserved verbatim. All 200 files under `src/src/` that
mention `README.ijg` in any way do so inside a preserved notice.

Two compiled units carry no IJG phrasing but do point at `README.ijg` under the
IJG terms: `src/src/jcicc.c:3-7`, `src/src/jdicc.c:3-7`,
`src/src/jpeg_nbits.c:3-5`, `src/src/jpeg_nbits.h:5-7`,
`src/src/jpegapicomp.h:4`, `src/src/jsamplecomp.h:4` and `src/src/cmyk.h:4`
all name a copyright and then *"For conditions of distribution and use, see the
accompanying README.ijg file"*. Counting by the exact phrase "Independent JPEG
Group" would find 102 of the 122 non-wrapper `src/src` files; the pointer is
the reliable test, and it is present in all of them.

### The uncompiled upstream files, and their terms

| Path | Count | Term | Notice in the file |
|---|---:|---|---|
| `src/src/turbojpeg*.c`, `turbojpeg.h`, `tjutil.*`, `tj*.c`, `turbojpeg-mapfile` | — | *BSD-3* | libjpeg-turbo copyright, plus *"both the terms of the IJG License and the terms of the Modified BSD License apply"* in the library context (`src/LICENSE.md:19-21`) |
| `src/src/cjpeg.c`, `djpeg.c`, `jpegtran.c`, `cdjpeg.*`, `transupp.*`, `rdswitch.c` | — | *IJG* + *BSD-3* | both, because `cjpeg`/`djpeg` use libspng (`src/LICENSE.md:22-24`) |
| `src/src/rdbmp.c`, `wrbmp.c`, `rdgif.c`, `wrgif.c`, `rdtarga.c`, `wrtarga.c`, `rdppm.c`, `wrppm.c`, `rdcolmap.c`, `rdpng.c`, `wrpng.c` | — | *IJG* | the IJG block; these are the bundled BMP/GIF/Targa/PNG/PPM readers `cjpeg`/`djpeg` use |
| `src/src/wrapper/rd*-*.c`, `wr*-*.c` | 17 | *IJG* | the same short libjpeg-turbo block as the library wrappers |
| `src/src/spng/` (`spng.c`, `spng.h`, `CMakeLists.txt`) | 3 | *BSD-3*, with some files *PNG Reference Library License v2* | upstream's own `src/src/spng/LICENSE` (BSD 2-Clause, Copyright (c) 2018-2023 Randy) and `src/src/spng/libpng-LICENSE.txt` |
| `src/src/spng/zlib/` | 19 | *zlib*, subsumed by *IJG* in the libjpeg context | upstream's own `src/src/spng/zlib/LICENSE` |
| `src/simd/*.c`, `src/simd/*/*.c`, `src/simd/*.h` | 11 carry their own | *zlib*, subsumed by *IJG* | the multi-author BSD-2-style notice in `src/simd/jsimd.h:1-21` and `src/simd/jsimd.c:1-31` — see below |
| `src/simd/i386/*.asm`, `src/simd/x86_64/*.asm` | 56 + 35 | *zlib*, subsumed by *IJG* | the notice in `src/simd/nasm/jsimdcfg.inc.h` and the per-file `%%` comments; not compiled here |
| `src/simd/riscv64/jsimdcpu.S` | 1 | *zlib*, subsumed by *IJG* | GNU-as source; not compiled here |
| `src/doc/**`, `src/testimages/**`, `src/test/**`, `src/fuzz/**`, `src/release/**`, `src/BUILDING.md`, `src/ChangeLog.md` | — | mixed | upstream material carried by `src/LICENSE.md`; the manuals and man pages are IJG documentation |
| `src/LICENSE.md`, `src/README.ijg` | 2 | the terms themselves | `LICENSE.md` is the roll-up; `README.ijg:1-5` carries the modification note and `:126-157` the IJG grant |
| `src/CMakeLists.txt`, `src/cmakescripts/**`, `src/win/**`, `src/jna/**`, `src/sharedlib/**` | — | *BSD-3* | *"the build/test system"* is named at `src/LICENSE.md:16-17` |
| `src/README.md` | 1 | *IJG* + *BSD-3* + *subsumed* | upstream's own project README; preserved as `README.upstream.md` |

### The SIMD files carry their own multi-author notice

`src/LICENSE.md:37-40` puts the SIMD sources under the zlib term. Independently
of that, eleven files under `src/simd/` carry a **BSD-2-style** notice of their
own that is neither the IJG text nor the Modified BSD text — a third grant,
multiply attributed, with "altered source versions must be plainly marked"
rather than "Redistributions of source code must retain":

`src/simd/jsimd.h:1-21`:

> ```
> /*
>  * Copyright 2009 Pierre Ossman <ossman@cendio.se> for Cendio AB
>  * Copyright (C) 2011, 2014, 2022, 2025, D. R. Commander.
>  * Copyright (C) 2015-2016, 2018, 2022, Matthieu Darbois.
>  * Copyright (C) 2020, Arm Limited.
>  *
>  * This software is provided 'as-is', without any express or implied
>  * warranty.  In no event will the authors be held liable for any damages
>  * arising from the use of this software.
>  *
>  * Permission is granted to anyone to use this software for any purpose,
>  * including commercial applications, and to alter it and redistribute it
>  * freely, subject to the following restrictions:
>  *
>  * 1. The origin of this software must not be misrepresented; you must not
>  *    claim that you wrote the original software. If you use this software
>  *    in a product, an acknowledgment in the product documentation would be
>  *    appreciated but is not required.
>  * 2. Altered source versions must be plainly marked as such, and must not
>  *    misrepresented as being the original software.
>  * 3. This notice may not be removed or altered from any source distribution.
>  */
> ```

`src/simd/jsimd.c:1-31` carries the same three conditions with a longer
copyright list (nine holders, `src/simd/jsimd.c:2-11`). This fork altered
neither file, so condition 2 is not engaged, and condition 3 is discharged by
shipping them unaltered.

**None of `src/simd/` is compiled by this SDK.** See UPSTREAM.md, "The SIMD
decision". The notices are recorded because the audit surface is the whole
vendored tree, not only the compiled part.

### What `README.upstream.md` is, and is not

`README.upstream.md` is a fork-side copy of `src/README.md`, kept under this
repository's naming convention. It carries the same terms and is deliberately
**not** a 614th digested file: `UPSTREAM.sha256` records `src/README.md` alone,
and `tools/check-provenance.sh` is what proves the copy has not drifted. The
613 digested files are therefore the whole of the upstream material.

## Per-file exceptions

**The exceptions here are per-directory and upstream-stated, not fork-invented.**
Unlike a tree with a hand-scavenged notice in every third file, this one has its
exceptions enumerated by its own author in `src/LICENSE.md:27-50`, and the
inventory above follows that enumeration rather than guessing. Three things a
single label would have lost:

1. **The TurboJPEG API library is dual-licensed by design** — IJG *and*
   Modified BSD, simultaneously (`src/LICENSE.md:19-21`). Calling it
   "BSD-3" would be as wrong as calling the libjpeg library "BSD-3".
2. **The zlib term is subsumed only in a named context** — "in the context of
   the cjpeg and djpeg programs and the libjpeg API library"
   (`src/LICENSE.md:37-40`). The subsumption is context-bound and this SDK is
   inside that context; a fork building only the TurboJPEG library would not be.
3. **The SIMD sources carry a fourth, distinct notice** (`jsimd.h:1-21`,
   `jsimd.c:1-31`) that upstream's own roll-up does not enumerate — it names
   only zlib for those files. Reading `src/LICENSE.md` alone would miss it.

## What this fork changed in upstream files

**Nothing.** No file under `src/` has been edited, added or removed, and
`README.upstream.md` is byte-identical to `src/README.md`. `UPSTREAM.sha256`
plus the exact-file-set check in `tools/check-provenance.sh` are what make that
claim checkable rather than asserted, and any future native edit has to move
those digests in the same change, with a numbered entry in
[`CHANGELOG.md`](CHANGELOG.md).

`STATUS`: `SOURCE-CONFIRMED` from the recorded digests and from the notice text
quoted above. That is a claim about bytes and about what this file asserts about
them, not about a build, and no build result is recorded here. Every gate is
`PENDING-VERIFICATION`; see [`README.md`](README.md).

## Fork-specific notice

**The fork adds no upstream code to its own files.** Every file listed in this
section was written from scratch for this fork. No function, no constant, no
table, no comment and no line of upstream C, assembly, CMake, documentation or
data was copied into any of them; where a fork file quotes upstream, it does so
in a quotation or a Markdown code block that is attributed to a `file:line`
citation. The upstream material remains upstream's, under upstream's terms, in
`src/`.

**Every upstream notice is preserved verbatim.** No copyright line, no licence
text, no attribution block and no `README.ijg` pointer has been altered,
shortened, moved or removed anywhere in `src/`, and `README.upstream.md` is a
byte copy rather than an edit. The files below, all released under the MIT terms
recorded in [`FORK-LICENSE.md`](FORK-LICENSE.md):

* `build.zig`, `build.zig.zon`, `.gitignore`, `cross-test.profile.sh`,
  `.github/workflows/verify.yml`
* `zig/root.zig`, the typed facade, and `zig/translate.h`, the aggregate
  translation header this build runs `translate-c` over
* `tools/jconfig.zig`, the generator for `jconfig.h`, `jconfigint.h` and
  `jversion.h`
* `tests.zig`, `smoke.zig`, `consumer/build.zig`, `consumer/build.zig.zon`,
  `consumer/src/main.zig`
* `runtime/` — the load-at-runtime route: `loader.zig` (the reusable state
  machine and platform layer, holding no per-SDK name), `library.zig` (this
  SDK's descriptor, the namespaced synchronization binding and the one
  load-time check), `graph.zig` (the build half that wires them together and
  substitutes `createModule` for the translation's own), `generate.zig` (the
  build-time generator that writes the dispatch from the real translation output
  for the target being built, through `Run.addOutputFileArg`, so the generated
  file lands in the build cache and this directory holds no generated source),
  and `sync.h` / `sync.c` (the two C files that give the loader its
  process-global mutex, condition variable and thread identity).
* `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`
* `tools/check-provenance.sh`, `tools/check-fixtures.py`,
  `tools/make-fixtures.py`
* this file, `README.md`, `README.zig.md`, `UPSTREAM.md`, `UPSTREAM.sha256`,
  `FORK-LICENSE.md`, `CHANGELOG.md`, `FORK-NOTES.md`

`tools/make-fixtures.py` writes JPEG bytes **from the ITU-T T.81
specification**, using no image library and no upstream code. That is worth
saying plainly because "a JPEG file exists in the tree" would otherwise suggest
it came from a decoder: it did not. See UPSTREAM.md, "Fixture provenance".

### Which of those files carry the SPDX tag, and which do not

Fork-authored **source, build, packaging and script** files carry
`SPDX-License-Identifier: MIT` on their own first comment line: `build.zig`,
`build.zig.zon`, `zig/root.zig`, `tests.zig`, `smoke.zig`,
`consumer/build.zig`, `consumer/src/main.zig`, the six files of `runtime/`,
`tools/jconfig.zig`, `tools/check-provenance.sh`, `tools/make-fixtures.py`,
`tools/check-fixtures.py`, `package.nix`, `flake.nix`, `devenv.nix`,
`devenv.yaml` and `.envrc`. That set was read out of the files.

The rest carry the same grant without a tag, and are named here rather than
left for a scanner to read as unlicensed: `zig/translate.h`,
`cross-test.profile.sh`, `.github/workflows/verify.yml`, `.gitignore` and
`consumer/build.zig.zon` are comment-capable text whose grant is this
inventory and `FORK-LICENSE.md`. The eight documentation and digest records —
this file, `README.md`, `README.zig.md`, `UPSTREAM.md`, `UPSTREAM.sha256`,
`FORK-LICENSE.md`, `CHANGELOG.md` and `FORK-NOTES.md` — are prose and data
with no comment position a tag is expected in, and their grant is the same MIT
text.

**Lock files.** `flake.lock` is **absent from this tree** and `devenv.lock` is
**absent from this tree**. Both belong to the driver, and neither is written by
this fork's tooling: `devenv.yaml` pins its nixpkgs revision in source, and
`flake.nix` pins its own. `build.zig.zon`'s `.paths` is the package's file
filter, and the one rule that governs it is that every path it names must
exist — `zig fetch` hashes the named paths, so naming an absent lock file would
fail the fetch rather than record an absence. No lock file is invented here.

Upstream's attribution obligations are unaffected by any of this: a consumer who
ships a libjpeg-turbo binary or a static-linked product still owes the IJG
acknowledgement, and the installed tree carries the upstream texts so the
obligation can be discharged.
