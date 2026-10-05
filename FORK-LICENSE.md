# FORK-LICENSE.md — the grant for this fork's own files

[`NOTICE.md`](NOTICE.md) is the inventory: which files are upstream's, which are
this fork's, and which term covers each. This file is the grant itself, for the
second group only.

## 1. The native source is not covered by anything below

The 613 files under `src/` are libjpeg-turbo's, whole from
`libjpeg-turbo-3.2.0.tar.gz` and never edited. They are covered by **two**
terms and several subsumed component terms, not by one:

* the **IJG (Independent JPEG Group) License**, full text at
  `src/README.ijg:126-157`, applying to the libjpeg API library and associated
  programs including code inherited from libjpeg and modifications to it
  (`src/LICENSE.md:6-11`);
* the **Modified (3-clause) BSD License**, full text at
  `src/LICENSE.md:119-147`, applying to the TurboJPEG API library and
  associated programs, libspng, and the build/test system
  (`src/LICENSE.md:13-24`);
* the **zlib** term for the SIMD sources and the bundled zlib, subsumed by the
  IJG terms in the libjpeg/cjpeg/djpeg context (`src/LICENSE.md:37-40`); the
  **PNG Reference Library License v2** and **BSD-2-Clause** terms for parts of
  libspng (`src/LICENSE.md:42-50`);
* a fourth, independent **multi-author BSD-2-style** notice in
  `src/simd/jsimd.h:1-21` and `src/simd/jsimd.c:1-31`, which upstream's own
  roll-up does not enumerate.

Nothing in this file re-grants, narrows, widens or conditions any of those
terms, and nothing here asserts that the Independent JPEG Group, The
libjpeg-turbo Project, D. R. Commander, Thomas G. Lane, Pierre Ossman, Arm
Limited, Loongson Technology Corporation Limited, Google LLC, Samsung
Electronics, Nokia Corporation, Cendio AB, Matthieu Darbois, Randy or any other
named author wrote, reviewed or endorsed a line of fork code.

## 2. The fork-authored material

Everything else in this repository — the Zig build, the generated-header
generator, the typed module and its tests, the smoke example, the consumer
package, the runtime-loading route, the fixture encoder, the packaging, the
integrity scripts and the documentation — was written for this fork.

**No upstream source was copied into any fork-authored file.** Not one function,
constant, table, comment line, CMake rule or documentation paragraph from
`src/` appears in a fork file. Where a fork file quotes upstream, it does so in
an attributed quotation or a fenced block carrying a `file:line` citation, which
is fair quotation under the IJG clause (1) machinery and leaves upstream's text
in upstream's file. The only executable artefact that reads upstream data at
run time is the compiled library itself, which is upstream's code linked, never
reproduced.

### Grant

**Those files are released under the MIT License.** MIT is not one of
libjpeg-turbo's own terms, and it is chosen here as the owner-authorized term
for independently written additions rather than as an upstream term:

```
MIT License

Copyright (c) 2026 the contributors to this fork

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

### Authority for that grant

The owner of this repository authorized per-project licensing for
fork-authored additions, with the term chosen per project. libjpeg-turbo has no
single primary upstream term — it is dual-licensed by design
(`src/LICENSE.md:4`) — so the choice could not be "match the primary upstream
term" in the way it was for a single-licensed project. MIT was chosen because
the material here is independently authored build, packaging, test and
documentation work that does not derive from upstream's C, and because a
permissive term keeps the fork's own files free of upstream's three
conditions — most importantly the IJG clause (1) obligation that a
modification "must be clearly indicated in accompanying documentation", which
has nothing to say about a file that contains no upstream code and no
modification.

The authorization and the actual grant are recorded here and in
[`NOTICE.md`](NOTICE.md). The term above is the owner's, reached by that
authorization and not by any upstream grant.

The owner is not named and no individual copyright holder is invented: the
copyright line is deliberately the collective one.

### SPDX identifier

```
MIT
```

The plain registered identifier, with no `LicenseRef-` wrapper. That is a
deliberate distinction, not a shortcut. A fork whose own material carried added
conditions would need an identifier naming them, because a consumer scanning
for `MIT` would otherwise stop reading. Here MIT is accurate: no condition
beyond the MIT condition is attached to any fork-authored file. It is *not* a
claim about upstream — a consumer scanning a binary of this SDK sees the IJG
terms as well, and `NOTICE.md` records where each travels.

Every fork-authored **source, build, packaging and script** file carries
`SPDX-License-Identifier: MIT` on its own first comment line; the set is named
one by one in [`NOTICE.md`](NOTICE.md). The documentation and digest records do
not carry a tag: they are prose and data, and `NOTICE.md` names each of them
explicitly so a scanner finding no identifier in `README.md` reads a recorded
reason rather than an apparent gap.

## 3. Material carried but not authored here

There is none that this fork introduced. `src/` is upstream's own tree, complete
at 613 files, and `README.upstream.md` is a byte copy of `src/README.md` rather
than a derived work. The bundled `src/src/spng/` and `src/src/spng/zlib/` are
part of the release tarball and are upstream's, under their own licences; this
SDK does not compile either of them (the tools that would have are excluded, for
the reason in UPSTREAM.md).

Two categories are worth keeping exact rather than dropping to make a sentence
short:

* **The generated headers.** `jconfig.h`, `jconfigint.h` and `jversion.h` are
  written by `tools/jconfig.zig`, a fork-authored generator, into the build
  cache — not into this tree — from upstream's own `.in` templates with
  upstream's own CMake `@VAR@` and `#cmakedefine` substitution rules. They are
  a deterministic build step from a host-target generator, as AGENTS.md §4
  requires; they are not carried material, and they are not installed or
  shipped as fork source. Every file under `runtime/` and `tools/` in this tree
  is fork-authored.
* **The fixtures.** `fixtures/*.jpg` are written by `tools/make-fixtures.py`
  from the ITU-T T.81 specification, using no image library and no upstream
  code. They are independent data, not derived from libjpeg-turbo, and their
  digests are recorded so their independence stays checkable.

## 4. What this does not do

* It does not re-license, sublicense or add a condition to any file under
  `src/`, or to `README.upstream.md`.
* It does not assert that the Independent JPEG Group, The libjpeg-turbo Project,
  or any author named in this repository authored, reviewed, endorsed or is
  affiliated with the fork's files.
* It does not discharge upstream's obligations. A consumer who ships a
  libjpeg-turbo binary, a static-linked product, `libjpeg.pc`-based build or
  any header still owes the IJG acknowledgement — "This software is based in
  part on the work of the Independent JPEG Group"
  (`src/LICENSE.md:88-89`) — and, in a TurboJPEG context, the Modified BSD text
  (`src/LICENSE.md:94-98`). See `NOTICE.md` for where each travels.
* It does not use any of the IJG or libjpeg-turbo names in advertising. The
  prohibition at `src/LICENSE.md:102-104` is upstream's term and this fork
  observes it.

## 5. Why a separate file at all

`NOTICE.md` names which fork-authored files carry an `SPDX-License-Identifier`
line and which carry the same grant in prose without one. This file exists so
that the authority, the grant text and the limits of that grant live in one
place, next to the inventory rather than scattered across the files themselves.
