# Notice

`src/` contains 613 upstream files (9,246,273 bytes); `UPSTREAM.sha256` lists their digests. No upstream file was removed or modified. The primary licence texts are in `src/README.ijg` and `src/LICENSE.md`; component terms remain in their upstream files.

## Upstream licence scope

libjpeg-turbo uses the IJG License and the Modified BSD License. The scope is per path; component licences remain in their upstream files.

| Path | Licence and scope |
|---|---|
| libjpeg API code in `src/src/`, excluding the groups below | IJG License; covers the libjpeg API, associated programs, inherited code and modifications. |
| `src/src/turbojpeg*.c`, `turbojpeg.h`, `tj*.c`, `tj*.h`, `turbojpeg-mapfile` | Modified BSD; both IJG and Modified BSD apply to the TurboJPEG API library. |
| `src/src/cjpeg.c`, `djpeg.c`, `jpegtran.c`, `cdjpeg.*`, `transupp.*`, `rdswitch.c` | IJG and Modified BSD; both apply to `cjpeg` and `djpeg`. |
| `src/src/rdbmp.c`, `wrbmp.c`, `rdgif.c`, `wrgif.c`, `rdtarga.c`, `wrtarga.c`, `rdppm.c`, `wrppm.c`, `rdcolmap.c`, `rdpng.c`, `wrpng.c` | IJG License. |
| `src/src/spng/` | Modified BSD; some files also carry the PNG Reference Library License v2, subsumed by IJG in the `cjpeg`/`djpeg` and TurboJPEG API contexts. See `LICENSE` and `libpng-LICENSE.txt` in that directory. |
| `src/src/spng/zlib/` | zlib License; upstream subsumes it by the IJG terms in the libjpeg API and `cjpeg`/`djpeg` contexts. |
| `src/simd/**` | zlib License, subsumed by IJG in the libjpeg context. `jsimd.h` and `jsimd.c` also carry a separate multi-author BSD-2-style notice. |
| `src/doc/**`, `src/testimages/**`, `src/test/**`, `src/fuzz/**`, `src/release/**`, `src/BUILDING.md`, `src/ChangeLog.md` | Mixed upstream terms; manuals and man pages are IJG documentation. |
| `src/LICENSE.md`, `src/README.ijg` | Upstream licence texts and roll-up. |
| `src/CMakeLists.txt`, `src/cmakescripts/**`, `src/win/**`, `src/jna/**`, `src/sharedlib/**` | Modified BSD; upstream includes the build system in this scope. |
| `src/README.md` | IJG, Modified BSD and component terms; upstream project README, copied as `README.upstream.md`. |

The zlib term is subsumed only in the stated libjpeg API and `cjpeg`/`djpeg` contexts. The eleven SIMD files with their own notice retain it alongside the zlib term.

### IJG License text (`src/README.ijg`)

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

### Modified BSD text (`src/LICENSE.md`)

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

### Additional SIMD notice (`src/simd/jsimd.h`, `src/simd/jsimd.c`)

`jsimd.c` carries the same conditions with additional copyright holders.

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

## Fork files

The files below are fork-authored under the MIT grant in `FORK-LICENSE.md`; no upstream source code is copied into them. Documentation quotes from upstream are attributed to their source paths. `README.upstream.md` is a copy of upstream's `src/README.md` and remains under upstream terms, not the fork's MIT grant.

| Paths | Contents |
|---|---|
| `build.zig`, `build.zig.zon`, `.gitignore`, `cross-test.profile.sh`, `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc` | Build and package files. |
| `zig/root.zig`, `zig/translate.h`, `runtime/**` | Facade, translation header and runtime-loading support. |
| `tools/jconfig.zig`, `tools/check-provenance.sh`, `tools/check-fixtures.py`, `tools/make-fixtures.py` | Header generator and fixture/provenance tools. |
| `tests.zig`, `smoke.zig`, `consumer/**` | Tests and consumer example. |
| `README.md`, `README.zig.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `FORK-LICENSE.md`, `CHANGELOG.md`, `FORK-NOTES.md` | Fork documentation and provenance records. |
