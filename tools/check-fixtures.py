#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# See ../FORK-LICENSE.md for what that identifier covers.

"""Check the four JPEG fixtures against their recorded SHA-256 digests.

The fixtures are written by tools/make-fixtures.py, which uses no image library:
the baseline stream is assembled by hand from ITU-T T.81. They are the
independent known answers this SDK's tests compare against, so a fixture that
silently changes would turn a hand-computed expectation into a recorded
one — the exact failure this check exists to prevent.

This program compiles nothing, links nothing and decodes nothing. It reads four
files and compares their bytes.

Usage:
    python3 tools/check-fixtures.py
"""

import hashlib
import os
import sys

# (relative path, sha256, byte count), recorded from the files tools/make-fixtures.py
# writes. Each digest is stated in UPSTREAM.md as well, so the three records --
# this one, that document and the bytes themselves -- cannot disagree silently.
FIXTURES = [
    (
        "grey16x16-halves.jpg",
        "b2e2490ff88768780f7e48f1739d1a608dfc7b5c17a54c2665db29db8b51f4bf",
        555,
    ),
    (
        "grey8x8-200.jpg",
        "f7f10aee901395fe1a12f424cd8d91f9bf2e181642cf0ab069b406d938cb9e2d",
        549,
    ),
    (
        "rgb8x8-grey200.jpg",
        "e31f0659abba47da10e4600fde1a3da25afdcacee2f1dde5029aeddade972b98",
        629,
    ),
    (
        "rgb8x8-grey64.jpg",
        "0704223b42ce860b9a28892da837fa160de3603ebd6cc8cd385dbb8a71f18684",
        629,
    ),
]

# The decoded answer each fixture encodes. Recorded here so the digest check and
# the expectation are one record rather than two: a fixture whose bytes are
# unchanged also keeps its known answer, and the arithmetic behind it is spelled
# out in UPSTREAM.md, "The expected decoded samples, spelled out".
EXPECTED = {
    "grey16x16-halves.jpg": "16x16, 1 component; rows 0-7 exactly 0, rows 8-15 exactly 255",
    "grey8x8-200.jpg": "8x8, 1 component; every sample exactly 200",
    "rgb8x8-grey200.jpg": "8x8, 3 components; every pixel exactly (200, 200, 200)",
    "rgb8x8-grey64.jpg": "8x8, 3 components; every pixel exactly (64, 64, 64)",
}


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    fixtures_dir = os.path.join(root, "fixtures")

    if not os.path.isdir(fixtures_dir):
        sys.stderr.write("check-fixtures: no fixtures/ directory at %s\n" % fixtures_dir)
        return 1

    failures = []
    for name, expected_digest, expected_size in FIXTURES:
        path = os.path.join(fixtures_dir, name)
        if not os.path.isfile(path):
            failures.append("%s: missing" % name)
            continue
        before = len(failures)
        actual_size = os.path.getsize(path)
        if actual_size != expected_size:
            failures.append(
                "%s: %d bytes, recorded %d" % (name, actual_size, expected_size)
            )
        actual_digest = sha256_of(path)
        if actual_digest != expected_digest:
            failures.append(
                "%s: sha256 %s, recorded %s" % (name, actual_digest, expected_digest)
            )
        # Only a file that added nothing above is reported as ok, so a mismatch
        # never also prints a reassuring line.
        if len(failures) == before:
            print("ok  %-24s %6d bytes  %s" % (name, actual_size, actual_digest))
            print("      decodes to: %s" % EXPECTED[name])

    # An unexpected extra fixture would not fail a digest check, so the count is
    # compared too: the set is these four files, not "these four at least".
    on_disk = sorted(
        entry
        for entry in os.listdir(fixtures_dir)
        if os.path.isfile(os.path.join(fixtures_dir, entry))
    )
    if on_disk != sorted(name for name, _, _ in FIXTURES):
        failures.append(
            "fixtures/ holds %s, expected exactly %s"
            % (on_disk, sorted(name for name, _, _ in FIXTURES))
        )

    if failures:
        for line in failures:
            sys.stderr.write("check-fixtures: %s\n" % line)
        sys.stderr.write(
            "\nA fixture's bytes are the independent known answer the tests compare\n"
            "against. Changing one silently turns a hand-computed expectation into\n"
            "a recorded one. If the change is intended, regenerate with\n"
            "tools/make-fixtures.py, update the digest and byte count here and in\n"
            "UPSTREAM.md, and add a numbered CHANGELOG.md entry in the same change.\n"
        )
        return 1

    print("all %d fixtures match their recorded digests and sizes" % len(FIXTURES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
