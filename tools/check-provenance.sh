#!/usr/bin/env bash
# Source-integrity check for the libjpeg-turbo SDK.
#
# Five questions, all answerable without a compiler:
#
#   1. Do the 613 upstream files still hash to the digests UPSTREAM.sha256
#      records?
#   2. Is the native file set exactly that set -- no missing, extra or renamed
#      file under src/?  A plain checksum run cannot see an addition.
#   3. Do UPSTREAM.md and UPSTREAM.sha256 name the same release digest?
#   4. Is the preserved upstream README still byte-identical to src/README.md?
#   5. Are the per-file licence notices still where NOTICE.md says they are --
#      including the four distinct grants this tree carries, of which only two
#      appear in src/LICENSE.md's roll-up?
#
# and it then runs tools/check-fixtures.py, so a changed fixture fails here too.
#
# This is a provenance gate, not a build gate. Nothing here compiles, links or
# runs a target binary; it is the check that an edit to the canonical native
# source cannot pass as a routine change, and that a dropped attribution would
# be caught before anything ships.
#
# Usage: tools/check-provenance.sh   (run from anywhere in the repository)
#
# SPDX-License-Identifier: MIT
# See ../FORK-LICENSE.md for what that identifier covers, and ../NOTICE.md for
# the per-file inventory of the upstream material this package ships.

set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "$1" >&2
    exit 1
}

expect_grep() {
    # $1 = file, $2 = extended regex, $3 = what is being checked
    grep -qE "$2" "$1" || fail "$3"
}

# 1. Bytes.
sha256sum -c --quiet UPSTREAM.sha256 || fail "an upstream file no longer matches UPSTREAM.sha256"
echo "all 613 upstream files match UPSTREAM.sha256"

# 2. File set. An added file under src/ would pass a checksum run untouched, so
#    the recorded names are compared against what is actually on disk.
expected_tree=$(awk '/^[0-9a-f]{64}  / { print $2 }' UPSTREAM.sha256 | LC_ALL=C sort)
actual_tree=$(find src -type f | LC_ALL=C sort)
if [ "$expected_tree" != "$actual_tree" ]; then
    echo "the native file set differs from the recorded one:" >&2
    diff -u <(echo "$expected_tree") <(echo "$actual_tree") >&2 || true
    echo >&2
    echo "An intentional change to the native source needs an observed failure, a" >&2
    echo "small causal patch, an explicit per-file deviation record in NOTICE.md," >&2
    echo "updated digests here, and a CHANGELOG.md entry in the same change." >&2
    exit 1
fi
echo "the native file set is exactly the recorded 613 files"

# 2b. The record itself. A truncated or half-rewritten manifest would make every
#     check above vacuous, so the header comment is checked too.
expect_grep UPSTREAM.sha256 \
    '^# 613 records, ' "UPSTREAM.sha256 does not record a 613-file manifest"
manifest_count=$(grep -cE '^[0-9a-f]{64}  ' UPSTREAM.sha256)
[ "$manifest_count" -eq 613 ] ||
    fail "UPSTREAM.sha256 holds $manifest_count records, not the 613 it declares"
echo "the manifest holds the 613 records it declares"

# 3. The release digest must be recorded identically in both records, so the
#    two files cannot disagree about which upstream release this is.
# `-m1` rather than a pipe into `head -1`: with `pipefail` a `head` that closes
#    the pipe early sends SIGPIPE to grep and turns a successful match into a
#    failed pipeline.
digest_md=$(grep -m1 -oE '[0-9a-f]{64}' UPSTREAM.md)
digest_list=$(grep -m1 -oE '[0-9a-f]{64}' UPSTREAM.sha256)
[ -n "$digest_md" ] || fail "UPSTREAM.md records no sha256 digest"
[ "$digest_md" = "$digest_list" ] ||
    fail "UPSTREAM.md and UPSTREAM.sha256 name different release digests"
echo "the release digest is recorded consistently: $digest_md"

# The tarball size and the URL must also agree, so a re-pointed download cannot
# pass while the digest happens to match.
expect_grep UPSTREAM.md '2537858 bytes' "UPSTREAM.md does not record the tarball size"
expect_grep UPSTREAM.md '2026-06-30' "UPSTREAM.md does not record the release date"
expect_grep UPSTREAM.sha256 'released 2026-06-30, 2537858 bytes' \
    "UPSTREAM.sha256 does not record the release date and size"
expect_grep UPSTREAM.sha256 \
    'https://github\.com/libjpeg-turbo/libjpeg-turbo/releases/download/3\.2\.0/libjpeg-turbo-3\.2\.0\.tar\.gz' \
    "UPSTREAM.sha256 does not record the download URL"
echo "the tarball URL, size and release date agree across both records"

# 4. The preserved upstream README. README.upstream.md is the exact bytes of
#    src/README.md; a fork README must never sit where upstream's does.
cmp -s src/README.md README.upstream.md ||
    fail "src/README.md and README.upstream.md are no longer byte-identical"
echo "README.upstream.md is byte-identical to src/README.md"

# ---------------------------------------------------------------------------
# 5. Licence notices, where NOTICE.md says they are.
#
# libjpeg-turbo is dual-licensed, so "one label for the tree" would be wrong.
# Four distinct grants have to still be present:
#
#   (a) the IJG License, full text in src/README.ijg;
#   (b) the Modified (3-clause) BSD License, text in src/LICENSE.md;
#   (c) the component subsumption statements in src/LICENSE.md;
#   (d) the SIMD files' own multi-author BSD-2-style notice, which upstream's
#       roll-up does not enumerate and which only a per-file reading finds.
#
# Upstream's IJG clause 1 forbids altering or removing any existing copyright
# or licence notice, and clause 1 of the README requirement is that the file
# travels unaltered. These greps are the check that neither happened.
# ---------------------------------------------------------------------------

expect_grep src/README.ijg 'This file has been modified by The libjpeg-turbo Project' \
    "the libjpeg-turbo modification note is missing from src/README.ijg"
expect_grep src/README.ijg \
    'Permission is hereby granted to use, copy, modify, and distribute this' \
    "the IJG grant is missing from src/README.ijg"
expect_grep src/README.ijg \
    'must state that "this software is based in part on the work of$' \
    "the IJG clause 2 obligation text is missing from src/README.ijg"
expect_grep src/README.ijg \
    '^This software is copyright \(C\) 1991-2020, Thomas G\. Lane, Guido Vollbeding\.' \
    "the IJG copyright line is missing from src/README.ijg"

expect_grep src/LICENSE.md \
    '^- The Modified \(3-clause\) BSD License, which is listed below' \
    "the Modified BSD heading is missing from src/LICENSE.md"
expect_grep src/LICENSE.md 'Copyright \(C\) 2009-2026 D\. R\. Commander<br>' \
    "the Modified BSD copyright line is missing from src/LICENSE.md"
expect_grep src/LICENSE.md 'Copyright \(C\) 2018-2023 Randy <randy408@protonmail\.com>' \
    "the second Modified BSD copyright line is missing from src/LICENSE.md"
expect_grep src/LICENSE.md \
    '^- Neither the name of the libjpeg-turbo Project nor the names of its' \
    "the Modified BSD endorsement clause is missing from src/LICENSE.md"

# The component subsumption statements: the zlib term for the SIMD sources is
# context-bound ("in the context of the cjpeg and djpeg programs and the libjpeg
# API library"), and dropping the context would misstate what it covers.
expect_grep src/LICENSE.md 'SIMD source code and zlib are covered by the' \
    "the zlib component statement is missing from src/LICENSE.md"
expect_grep src/LICENSE.md 'subsumed by the IJG License in the context of the cjpeg' \
    "the zlib subsumption context is missing from src/LICENSE.md"
expect_grep src/LICENSE.md 'Simplified \(2-clause\) BSD License' \
    "the libspng BSD-2-Clause statement is missing from src/LICENSE.md"

# (d) The SIMD files' own notice. jsimd.h and jsimd.c are the two files that
# carry it verbatim, and it is a fourth grant: "altered source versions must be
# plainly marked", not the IJG or Modified BSD wording.
for simd_notice in src/simd/jsimd.h src/simd/jsimd.c; do
    expect_grep "$simd_notice" 'Copyright 2009 Pierre Ossman <ossman@cendio\.se> for Cendio AB' \
        "the SIMD multi-author notice is missing from $simd_notice"
    expect_grep "$simd_notice" '2\. Altered source versions must be plainly marked as such' \
        "the SIMD 'altered versions' clause is missing from $simd_notice"
    expect_grep "$simd_notice" '3\. This notice may not be removed or altered from any source distribution' \
        "the SIMD 'notice may not be removed' clause is missing from $simd_notice"
done
# One representative of the nine further holders named only in jsimd.c, so a
# dropped copyright line there is caught as well.
expect_grep src/simd/jsimd.c 'Copyright \(C\) 2016-2018, Loongson Technology Corporation Limited, BeiJing' \
    "a named SIMD copyright holder is missing from src/simd/jsimd.c"

# The convention that covers the 200 compiled units: each one points at
# README.ijg. A dropped pointer in a library unit is the failure mode this
# catches, so the count is checked against the number NOTICE.md records.
readme_ijg_units=$(grep -l 'README\.ijg' src/src/*.c src/src/*.h src/src/wrapper/*.c | wc -l)
[ "$readme_ijg_units" -eq 200 ] ||
    fail "only $readme_ijg_units of the 200 src/src units point at README.ijg"

# The bundled third-party trees keep their own licences.
expect_grep src/src/spng/LICENSE 'BSD 2-Clause License' \
    "the libspng BSD-2-Clause text is missing from src/src/spng/LICENSE"
expect_grep src/src/spng/LICENSE 'Copyright \(c\) 2018-2023, Randy <randy408@protonmail\.com>' \
    "the libspng copyright line is missing from src/src/spng/LICENSE"
expect_grep src/src/spng/zlib/LICENSE '\(C\) 1995-2026 Jean-loup Gailly and Mark Adler' \
    "the bundled zlib copyright line is missing from src/src/spng/zlib/LICENSE"
expect_grep src/src/spng/zlib/LICENSE "This software is provided 'as-is'" \
    "the bundled zlib grant text is missing from src/src/spng/zlib/LICENSE"

# Upstream's own compliance roll-up, which is what forbids altering a notice in
# the first place.
expect_grep src/LICENSE.md 'You cannot alter or remove any existing copyright or license notices' \
    "upstream's no-altered-notice rule is missing from src/LICENSE.md"
expect_grep src/LICENSE.md 'You must include the IJG README file' \
    "upstream's IJG-README requirement is missing from src/LICENSE.md"
expect_grep src/LICENSE.md 'This software is based in part on the work of the' \
    "upstream's binary-distribution acknowledgement text is missing from src/LICENSE.md"
echo "the IJG, Modified BSD, component and SIMD notices are all present"

# The fork records have to keep naming the upstream terms, or the inventory is
# a claim with nothing behind it.
for record in NOTICE.md README.md UPSTREAM.md FORK-LICENSE.md; do
    expect_grep "$record" 'Independent JPEG Group' \
        "the IJG notice is missing from $record"
done
expect_grep NOTICE.md 'IJG \(Independent JPEG Group\) License' \
    "NOTICE.md does not name the IJG term"
expect_grep NOTICE.md 'Modified \(3-clause\) BSD License' \
    "NOTICE.md does not name the Modified BSD term"
expect_grep FORK-LICENSE.md 'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND' \
    "FORK-LICENSE.md does not reproduce the MIT permission and warranty text"
expect_grep FORK-LICENSE.md 'No upstream source was copied into any fork-authored file' \
    "FORK-LICENSE.md does not carry the no-copy statement"
expect_grep NOTICE.md 'fork adds no upstream code to its own files' \
    "NOTICE.md does not carry the no-copy statement"

# ---------------------------------------------------------------------------
# 6. The fixtures. The four digests are re-checked here so a changed fixture
#    fails this gate rather than silently updating the test's expectation.
# ---------------------------------------------------------------------------
python3 tools/check-fixtures.py

echo "provenance checks passed"
