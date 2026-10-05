// SPDX-License-Identifier: MIT
// See ../FORK-LICENSE.md for what that identifier covers.

//! Consumes the `libjpeg-turbo` package the way an outside project would.
//!
//! Everything here goes through the published surface only:
//! `b.dependency("libjpeg-turbo", ...)` and `dep.module("libjpeg_turbo")` in
//! `build.zig`, and `@import("libjpeg_turbo")` here. No path reaches into the
//! library's own tree and no file is read at run time, so if this builds and
//! produces the answers below, the module contract is real: the typed facade,
//! the translated headers it re-exports as `c`, the three headers that were
//! generated for this target, and the native library behind all of it arrived
//! through one dependency line.
//!
//! ## The answers are not this code talking to itself
//!
//! A round trip proves only that the two halves agree. Every check below is
//! stated against a value from outside the library:
//!
//!   * **The container.** ITU-T T.81 and JFIF are parsed *by this program*, from
//!     the fixture bytes alone: the `SOI`/`EOI` markers of A.2.1, the `APP0`
//!     JFIF identifier and version of JFIF 1.02, and the `DQT` payload of B.2.4.
//!     None of that goes through libjpeg, so a decoder that agreed with itself
//!     about a malformed stream would still fail here.
//!   * **The pixels.** The expected samples are the ones
//!     `../tools/make-fixtures.py` writes out of arithmetic. Three facts produce
//!     all of them and `../UPSTREAM.md` gives the derivation: both quantisation
//!     tables are all ones, so quantisation is exact; every block is flat, so
//!     its only coefficient is `8 * (sample - 128)` and the inverse DCT returns
//!     `sample - 128` before the level shift adds 128 back; and the JFIF luma
//!     constants satisfy `19595 + 38470 + 7471 = 2^16`, so `R = G = B = v`
//!     decodes to `(v, v, v)` by that transform rather than by a rounding
//!     coincidence.
//!   * **The bytes.** Each fixture's SHA-256 and byte length, as
//!     `../tools/check-fixtures.py`, `../UPSTREAM.md`, `../CHANGELOG.md` and
//!     `.github/workflows/verify.yml` all record them. This program recomputes
//!     both from the bytes it was given, so a fixture edited underneath the
//!     tests becomes a failure instead of a weakened check.
//!
//! The same source builds against a linked package and against a runtime-loaded
//! one. `libjpeg_turbo.runtime_loaded` is a comptime constant, so the difference
//! is one branch and no duplicated program: in the runtime-loaded build the
//! provider is named on the command line (`--provider <path>`) or in
//! `LIBJPEG_TURBO_TEST_PROVIDER`, loaded once, and the same answers follow.
//!
//! **A runtime-loading run needs a provider.** Nothing is loaded by default and
//! no other file is tried, so `zig build run -Druntime=true` with no
//! `--provider` and no `LIBJPEG_TURBO_TEST_PROVIDER` exits non-zero with that
//! sentence rather than quietly running against the linked copy. That is the
//! policy `README.zig.md` states, and it means a CI step that wants the
//! runtime-loaded route has to name a provider.

const std = @import("std");
const jpeg = @import("libjpeg_turbo");

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// The provider this run should load, from `--provider <path>` or from
/// `LIBJPEG_TURBO_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location, and a build
/// that was not told which file to load says so rather than loading something
/// else.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get("LIBJPEG_TURBO_TEST_PROVIDER") orelse
        return noProvider();
}

/// Say which variable is missing. An error name on its own would send the next
/// person into the loader instead of to the command line.
fn noProvider() ConfigurationError {
    std.debug.print(
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export LIBJPEG_TURBO_TEST_PROVIDER with a shared object exporting the " ++
            "66 jpeg_* names of zig/translate.h. Nothing is loaded by default and " ++
            "no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

/// A line label built for one diagnostic. Nothing freed: `main` allocates this
/// from the process arena, and a check that is about to fail does not need its
/// own bookkeeping.
fn label(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, fmt, args) catch @panic("OOM");
}

// ---------------------------------------------------------------------------
// The fixtures, and the digests this repository records for them
// ---------------------------------------------------------------------------

/// `fixtures/grey8x8-200.jpg`: 8x8, one component, every sample exactly 200.
///
/// The same 549 bytes the fixture file holds, embedded rather than read from a
/// path: a gate that depends on a working directory can pass for the wrong
/// reason.
const grey8x8_200_jpg =
    "\xFF\xD8\xFF\xE0\x00\x10\x4A\x46\x49\x46\x00\x01\x01\x00\x00\x01" ++
    "\x00\x01\x00\x00\xFF\xDB\x00\x43\x00\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\xFF\xC0\x00\x0B\x08\x00\x08" ++
    "\x00\x08\x01\x01\x11\x00\xFF\xC4\x00\x1F\x00\x00\x01\x05\x01\x01" ++
    "\x01\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x01\x02\x03\x04" ++
    "\x05\x06\x07\x08\x09\x0A\x0B\xFF\xC4\x00\xB5\x10\x00\x02\x01\x03" ++
    "\x03\x02\x04\x03\x05\x05\x04\x04\x00\x00\x01\x7D\x01\x02\x03\x00" ++
    "\x04\x11\x05\x12\x21\x31\x41\x06\x13\x51\x61\x07\x22\x71\x14\x32" ++
    "\x81\x91\xA1\x08\x23\x42\xB1\xC1\x15\x52\xD1\xF0\x24\x33\x62\x72" ++
    "\x82\x09\x0A\x16\x17\x18\x19\x1A\x25\x26\x27\x28\x29\x2A\x34\x35" ++
    "\x36\x37\x38\x39\x3A\x43\x44\x45\x46\x47\x48\x49\x4A\x53\x54\x55" ++
    "\x56\x57\x58\x59\x5A\x63\x64\x65\x66\x67\x68\x69\x6A\x73\x74\x75" ++
    "\x76\x77\x78\x79\x7A\x83\x84\x85\x86\x87\x88\x89\x8A\x92\x93\x94" ++
    "\x95\x96\x97\x98\x99\x9A\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xB2" ++
    "\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9" ++
    "\xCA\xD2\xD3\xD4\xD5\xD6\xD7\xD8\xD9\xDA\xE1\xE2\xE3\xE4\xE5\xE6" ++
    "\xE7\xE8\xE9\xEA\xF1\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFF\xC4" ++
    "\x00\x1F\x01\x00\x03\x01\x01\x01\x01\x01\x01\x01\x01\x01\x00\x00" ++
    "\x00\x00\x00\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\xFF" ++
    "\xC4\x00\xB5\x11\x00\x02\x01\x02\x04\x04\x03\x04\x07\x05\x04\x04" ++
    "\x00\x01\x02\x77\x00\x01\x02\x03\x11\x04\x05\x21\x31\x06\x12\x41" ++
    "\x51\x07\x61\x71\x13\x22\x32\x81\x08\x14\x42\x91\xA1\xB1\xC1\x09" ++
    "\x23\x33\x52\xF0\x15\x62\x72\xD1\x0A\x16\x24\x34\xE1\x25\xF1\x17" ++
    "\x18\x19\x1A\x26\x27\x28\x29\x2A\x35\x36\x37\x38\x39\x3A\x43\x44" ++
    "\x45\x46\x47\x48\x49\x4A\x53\x54\x55\x56\x57\x58\x59\x5A\x63\x64" ++
    "\x65\x66\x67\x68\x69\x6A\x73\x74\x75\x76\x77\x78\x79\x7A\x82\x83" ++
    "\x84\x85\x86\x87\x88\x89\x8A\x92\x93\x94\x95\x96\x97\x98\x99\x9A" ++
    "\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xB2\xB3\xB4\xB5\xB6\xB7\xB8" ++
    "\xB9\xBA\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xD2\xD3\xD4\xD5\xD6" ++
    "\xD7\xD8\xD9\xDA\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xF2\xF3\xF4" ++
    "\xF5\xF6\xF7\xF8\xF9\xFA\xFF\xDA\x00\x08\x01\x01\x00\x00\x3F\x00" ++
    "\xFE\x90\x2B\xFF\xD9";

/// `fixtures/grey16x16-halves.jpg`: 16x16, one component, scanlines 0-7 exactly
/// 0 and 8-15 exactly 255.
const grey16x16_halves_jpg =
    "\xFF\xD8\xFF\xE0\x00\x10\x4A\x46\x49\x46\x00\x01\x01\x00\x00\x01" ++
    "\x00\x01\x00\x00\xFF\xDB\x00\x43\x00\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\xFF\xC0\x00\x0B\x08\x00\x10" ++
    "\x00\x10\x01\x01\x11\x00\xFF\xC4\x00\x1F\x00\x00\x01\x05\x01\x01" ++
    "\x01\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x01\x02\x03\x04" ++
    "\x05\x06\x07\x08\x09\x0A\x0B\xFF\xC4\x00\xB5\x10\x00\x02\x01\x03" ++
    "\x03\x02\x04\x03\x05\x05\x04\x04\x00\x00\x01\x7D\x01\x02\x03\x00" ++
    "\x04\x11\x05\x12\x21\x31\x41\x06\x13\x51\x61\x07\x22\x71\x14\x32" ++
    "\x81\x91\xA1\x08\x23\x42\xB1\xC1\x15\x52\xD1\xF0\x24\x33\x62\x72" ++
    "\x82\x09\x0A\x16\x17\x18\x19\x1A\x25\x26\x27\x28\x29\x2A\x34\x35" ++
    "\x36\x37\x38\x39\x3A\x43\x44\x45\x46\x47\x48\x49\x4A\x53\x54\x55" ++
    "\x56\x57\x58\x59\x5A\x63\x64\x65\x66\x67\x68\x69\x6A\x73\x74\x75" ++
    "\x76\x77\x78\x79\x7A\x83\x84\x85\x86\x87\x88\x89\x8A\x92\x93\x94" ++
    "\x95\x96\x97\x98\x99\x9A\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xB2" ++
    "\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9" ++
    "\xCA\xD2\xD3\xD4\xD5\xD6\xD7\xD8\xD9\xDA\xE1\xE2\xE3\xE4\xE5\xE6" ++
    "\xE7\xE8\xE9\xEA\xF1\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFF\xC4" ++
    "\x00\x1F\x01\x00\x03\x01\x01\x01\x01\x01\x01\x01\x01\x01\x00\x00" ++
    "\x00\x00\x00\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\xFF" ++
    "\xC4\x00\xB5\x11\x00\x02\x01\x02\x04\x04\x03\x04\x07\x05\x04\x04" ++
    "\x00\x01\x02\x77\x00\x01\x02\x03\x11\x04\x05\x21\x31\x06\x12\x41" ++
    "\x51\x07\x61\x71\x13\x22\x32\x81\x08\x14\x42\x91\xA1\xB1\xC1\x09" ++
    "\x23\x33\x52\xF0\x15\x62\x72\xD1\x0A\x16\x24\x34\xE1\x25\xF1\x17" ++
    "\x18\x19\x1A\x26\x27\x28\x29\x2A\x35\x36\x37\x38\x39\x3A\x43\x44" ++
    "\x45\x46\x47\x48\x49\x4A\x53\x54\x55\x56\x57\x58\x59\x5A\x63\x64" ++
    "\x65\x66\x67\x68\x69\x6A\x73\x74\x75\x76\x77\x78\x79\x7A\x82\x83" ++
    "\x84\x85\x86\x87\x88\x89\x8A\x92\x93\x94\x95\x96\x97\x98\x99\x9A" ++
    "\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xB2\xB3\xB4\xB5\xB6\xB7\xB8" ++
    "\xB9\xBA\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xD2\xD3\xD4\xD5\xD6" ++
    "\xD7\xD8\xD9\xDA\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xF2\xF3\xF4" ++
    "\xF5\xF6\xF7\xF8\xF9\xFA\xFF\xDA\x00\x08\x01\x01\x00\x00\x3F\x00" ++
    "\xFF\x00\x3F\xFA\x2B\xFD\xFE\x28\xAF\xFF\xD9";

/// `fixtures/rgb8x8-grey64.jpg`: 8x8, three components, every pixel exactly
/// (64, 64, 64).
const rgb8x8_grey64_jpg =
    "\xFF\xD8\xFF\xE0\x00\x10\x4A\x46\x49\x46\x00\x01\x01\x00\x00\x01" ++
    "\x00\x01\x00\x00\xFF\xDB\x00\x43\x00\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\xFF\xDB\x00\x43\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\xFF\xC0" ++
    "\x00\x11\x08\x00\x08\x00\x08\x03\x01\x11\x00\x02\x11\x01\x03\x11" ++
    "\x01\xFF\xC4\x00\x1F\x00\x00\x01\x05\x01\x01\x01\x01\x01\x01\x00" ++
    "\x00\x00\x00\x00\x00\x00\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09" ++
    "\x0A\x0B\xFF\xC4\x00\xB5\x10\x00\x02\x01\x03\x03\x02\x04\x03\x05" ++
    "\x05\x04\x04\x00\x00\x01\x7D\x01\x02\x03\x00\x04\x11\x05\x12\x21" ++
    "\x31\x41\x06\x13\x51\x61\x07\x22\x71\x14\x32\x81\x91\xA1\x08\x23" ++
    "\x42\xB1\xC1\x15\x52\xD1\xF0\x24\x33\x62\x72\x82\x09\x0A\x16\x17" ++
    "\x18\x19\x1A\x25\x26\x27\x28\x29\x2A\x34\x35\x36\x37\x38\x39\x3A" ++
    "\x43\x44\x45\x46\x47\x48\x49\x4A\x53\x54\x55\x56\x57\x58\x59\x5A" ++
    "\x63\x64\x65\x66\x67\x68\x69\x6A\x73\x74\x75\x76\x77\x78\x79\x7A" ++
    "\x83\x84\x85\x86\x87\x88\x89\x8A\x92\x93\x94\x95\x96\x97\x98\x99" ++
    "\x9A\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xB2\xB3\xB4\xB5\xB6\xB7" ++
    "\xB8\xB9\xBA\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xD2\xD3\xD4\xD5" ++
    "\xD6\xD7\xD8\xD9\xDA\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xF1" ++
    "\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFF\xC4\x00\x1F\x01\x00\x03" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x00\x00\x00\x00\x00\x00\x01" ++
    "\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\xFF\xC4\x00\xB5\x11\x00" ++
    "\x02\x01\x02\x04\x04\x03\x04\x07\x05\x04\x04\x00\x01\x02\x77\x00" ++
    "\x01\x02\x03\x11\x04\x05\x21\x31\x06\x12\x41\x51\x07\x61\x71\x13" ++
    "\x22\x32\x81\x08\x14\x42\x91\xA1\xB1\xC1\x09\x23\x33\x52\xF0\x15" ++
    "\x62\x72\xD1\x0A\x16\x24\x34\xE1\x25\xF1\x17\x18\x19\x1A\x26\x27" ++
    "\x28\x29\x2A\x35\x36\x37\x38\x39\x3A\x43\x44\x45\x46\x47\x48\x49" ++
    "\x4A\x53\x54\x55\x56\x57\x58\x59\x5A\x63\x64\x65\x66\x67\x68\x69" ++
    "\x6A\x73\x74\x75\x76\x77\x78\x79\x7A\x82\x83\x84\x85\x86\x87\x88" ++
    "\x89\x8A\x92\x93\x94\x95\x96\x97\x98\x99\x9A\xA2\xA3\xA4\xA5\xA6" ++
    "\xA7\xA8\xA9\xAA\xB2\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xC2\xC3\xC4" ++
    "\xC5\xC6\xC7\xC8\xC9\xCA\xD2\xD3\xD4\xD5\xD6\xD7\xD8\xD9\xDA\xE2" ++
    "\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9" ++
    "\xFA\xFF\xDA\x00\x0C\x03\x01\x00\x02\x01\x03\x01\x00\x3F\x00\xFE" ++
    "\x7F\xE8\x03\xFF\xD9";

/// `fixtures/rgb8x8-grey200.jpg`: 8x8, three components, every pixel exactly
/// (200, 200, 200).
const rgb8x8_grey200_jpg =
    "\xFF\xD8\xFF\xE0\x00\x10\x4A\x46\x49\x46\x00\x01\x01\x00\x00\x01" ++
    "\x00\x01\x00\x00\xFF\xDB\x00\x43\x00\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\xFF\xDB\x00\x43\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\xFF\xC0" ++
    "\x00\x11\x08\x00\x08\x00\x08\x03\x01\x11\x00\x02\x11\x01\x03\x11" ++
    "\x01\xFF\xC4\x00\x1F\x00\x00\x01\x05\x01\x01\x01\x01\x01\x01\x00" ++
    "\x00\x00\x00\x00\x00\x00\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09" ++
    "\x0A\x0B\xFF\xC4\x00\xB5\x10\x00\x02\x01\x03\x03\x02\x04\x03\x05" ++
    "\x05\x04\x04\x00\x00\x01\x7D\x01\x02\x03\x00\x04\x11\x05\x12\x21" ++
    "\x31\x41\x06\x13\x51\x61\x07\x22\x71\x14\x32\x81\x91\xA1\x08\x23" ++
    "\x42\xB1\xC1\x15\x52\xD1\xF0\x24\x33\x62\x72\x82\x09\x0A\x16\x17" ++
    "\x18\x19\x1A\x25\x26\x27\x28\x29\x2A\x34\x35\x36\x37\x38\x39\x3A" ++
    "\x43\x44\x45\x46\x47\x48\x49\x4A\x53\x54\x55\x56\x57\x58\x59\x5A" ++
    "\x63\x64\x65\x66\x67\x68\x69\x6A\x73\x74\x75\x76\x77\x78\x79\x7A" ++
    "\x83\x84\x85\x86\x87\x88\x89\x8A\x92\x93\x94\x95\x96\x97\x98\x99" ++
    "\x9A\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xB2\xB3\xB4\xB5\xB6\xB7" ++
    "\xB8\xB9\xBA\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xD2\xD3\xD4\xD5" ++
    "\xD6\xD7\xD8\xD9\xDA\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xF1" ++
    "\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFF\xC4\x00\x1F\x01\x00\x03" ++
    "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x00\x00\x00\x00\x00\x00\x01" ++
    "\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\xFF\xC4\x00\xB5\x11\x00" ++
    "\x02\x01\x02\x04\x04\x03\x04\x07\x05\x04\x04\x00\x01\x02\x77\x00" ++
    "\x01\x02\x03\x11\x04\x05\x21\x31\x06\x12\x41\x51\x07\x61\x71\x13" ++
    "\x22\x32\x81\x08\x14\x42\x91\xA1\xB1\xC1\x09\x23\x33\x52\xF0\x15" ++
    "\x62\x72\xD1\x0A\x16\x24\x34\xE1\x25\xF1\x17\x18\x19\x1A\x26\x27" ++
    "\x28\x29\x2A\x35\x36\x37\x38\x39\x3A\x43\x44\x45\x46\x47\x48\x49" ++
    "\x4A\x53\x54\x55\x56\x57\x58\x59\x5A\x63\x64\x65\x66\x67\x68\x69" ++
    "\x6A\x73\x74\x75\x76\x77\x78\x79\x7A\x82\x83\x84\x85\x86\x87\x88" ++
    "\x89\x8A\x92\x93\x94\x95\x96\x97\x98\x99\x9A\xA2\xA3\xA4\xA5\xA6" ++
    "\xA7\xA8\xA9\xAA\xB2\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xC2\xC3\xC4" ++
    "\xC5\xC6\xC7\xC8\xC9\xCA\xD2\xD3\xD4\xD5\xD6\xD7\xD8\xD9\xDA\xE2" ++
    "\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9" ++
    "\xFA\xFF\xDA\x00\x0C\x03\x01\x00\x02\x01\x03\x01\x00\x3F\x00\xFE" ++
    "\x90\x28\x03\xFF\xD9";

/// One fixture's declared shape, as ITU-T T.81 and JFIF state it.
///
/// These are the numbers a consumer writes down from the specification before
/// running anything. None of them is read back out of a decode.
const Declared = struct {
    name: []const u8,
    /// The file, byte for byte.
    bytes: []const u8,
    /// Its SHA-256, as `tools/check-fixtures.py` records it.
    sha256: []const u8,
    /// Its byte length, from the same table.
    length: usize,
    width: u32,
    height: u32,
    /// `cinfo.num_components`, which is what the SOF marker says.
    components: i32,
    /// The colourspace the decode below asks for.
    out: jpeg.ColorSpace,
    /// `out_color_components` after that request.
    out_components: i32,
    /// How many DQT markers the file carries.
    ///
    /// Stated, not derived: a one-component image needs one quantisation table
    /// and a three-component image needs a luma table and a chroma one, but the
    /// count is a property of the bytes, so it is read out of the fixture and
    /// compared rather than computed from `components`.
    dqt_tables: usize,
    /// The decoded value, one entry per sample of the greyscale decode.
    ///
    /// For a one-component image this is the whole image. For a three-component
    /// image the greyscale decode of `R=G=B=v` is `v` by the JFIF luma identity,
    /// so the same flat value applies to every row.
    sample: u8,
};

const declared = [_]Declared{
    .{
        .name = "grey8x8-200.jpg",
        .bytes = grey8x8_200_jpg,
        .sha256 = "f7f10aee901395fe1a12f424cd8d91f9bf2e181642cf0ab069b406d938cb9e2d",
        .length = 549,
        .width = 8,
        .height = 8,
        .components = 1,
        .out = .grayscale,
        .out_components = 1,
        .dqt_tables = 1,
        .sample = 200,
    },
    .{
        .name = "grey16x16-halves.jpg",
        .bytes = grey16x16_halves_jpg,
        .sha256 = "b2e2490ff88768780f7e48f1739d1a608dfc7b5c17a54c2665db29db8b51f4bf",
        .length = 555,
        .width = 16,
        .height = 16,
        .components = 1,
        .out = .grayscale,
        .out_components = 1,
        .dqt_tables = 1,
        // The split is stated, not derived: this is one image with two halves,
        // so the expected sample depends on the row. Zero here names the top
        // half; the bottom half is 255 and is checked separately.
        .sample = 0,
    },
    .{
        .name = "rgb8x8-grey64.jpg",
        .bytes = rgb8x8_grey64_jpg,
        .sha256 = "0704223b42ce860b9a28892da837fa160de3603ebd6cc8cd385dbb8a71f18684",
        .length = 629,
        .width = 8,
        .height = 8,
        .components = 3,
        .out = .grayscale,
        .out_components = 1,
        .dqt_tables = 2,
        .sample = 64,
    },
    .{
        .name = "rgb8x8-grey200.jpg",
        .bytes = rgb8x8_grey200_jpg,
        .sha256 = "e31f0659abba47da10e4600fde1a3da25afdcacee2f1dde5029aeddade972b98",
        .length = 629,
        .width = 8,
        .height = 8,
        .components = 3,
        .out = .grayscale,
        .out_components = 1,
        .dqt_tables = 2,
        .sample = 200,
    },
};

/// The marker codes ITU-T T.81 B.2.1 assigns, as literals rather than as
/// anything read back out of a decoder.
const soi: u16 = 0xFFD8;
const eoi: u16 = 0xFFD9;
const app0: u16 = 0xFFE0;
const dqt: u16 = 0xFFDB;
const sof0: u16 = 0xFFC0;
const sof2: u16 = 0xFFC2;
const sos: u16 = 0xFFDA;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // In a runtime-loading build every call below goes through a table that this
    // one call fills. In a linked build the branch is not analyzed at all.
    if (comptime jpeg.runtime_loaded) {
        try jpeg.load(.{ .path = try providerRequest(init) });
    }

    try w.print("libjpeg-turbo consumer\n", .{});
    try w.print("{s} provider, portable C configuration (WITH_SIMD off, " ++
        "SIMD_ARCHITECTURE NONE, no src/simd/ unit compiled)\n", .{
        if (jpeg.runtime_loaded) "loaded" else "linked",
    });
    // Printed, not compared: `JPEG_LIB_VERSION` is a compile-time constant of the
    // translated headers, not a value read back from a provider, and
    // libjpeg-turbo exports no version symbol to compare anything with. Version
    // provenance belongs to the provenance gate; the samples below are what this
    // program decides on.
    try w.print("headers were compiled against libjpeg v6b, JPEG_LIB_VERSION {d}\n", .{
        jpeg.libjpeg_api_version,
    });

    // The bytes, the container, and the pixels - in that order, so a fixture
    // that moved fails on the digest before anything is decoded.
    for (declared) |fixture| {
        try checkDigest(w, allocator, fixture);
        try checkContainer(w, allocator, fixture);
        try checkPixels(w, allocator, fixture);
    }

    // The colour transform's other direction on the two RGB fixtures: for
    // `R = G = B = v` the RGB decode is the identity, so `(v, v, v)` comes out.
    for (declared[2..]) |fixture| {
        try checkRgbDecode(w, allocator, fixture);
    }

    try checkEncode(w, allocator);
    try checkErrorPaths(w, allocator);

    try w.print("every answer matched T.81 and JFIF\n", .{});
    try w.flush();
}

// ---------------------------------------------------------------------------
// 1. The bytes are the bytes this repository records
// ---------------------------------------------------------------------------

fn checkDigest(w: *std.Io.Writer, allocator: std.mem.Allocator, fixture: Declared) !void {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(fixture.bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    // `++` is comptime-only on slices, so the two labels that name a fixture are
    // built the way every other runtime label in this program is.
    try checkString(w, label(allocator, "{s} sha256", .{fixture.name}), &hex, fixture.sha256);
    try checkInt(w, label(allocator, "{s} byte length", .{fixture.name}), fixture.bytes.len, fixture.length);
}

// ---------------------------------------------------------------------------
// 2. The container, from ITU-T T.81 and from nothing else
// ---------------------------------------------------------------------------

/// One marker segment as this program parsed it, with nothing from libjpeg in it.
const Segment = struct {
    marker: u16,
    payload: []const u8,
};

/// Walks the marker stream of `bytes` from SOI to EOI.
///
/// T.81 A.2.1: a JPEG datastream is a sequence of markers. Standalone markers -
/// SOI, EOI, RSTn (`FFD0`-`FFD7`) and TEM (`FF01`) - carry no length. Every
/// other marker is followed by a two-byte big-endian length that counts itself
/// but not the marker, so the payload is `length - 2` bytes.
///
/// The `FF` fill rule is honoured: a marker may be preceded by any number of
/// `FF` bytes, and it is the first byte that is not `FF` that completes it.
fn parseSegments(bytes: []const u8, out: []Segment) ![]Segment {
    if (bytes.len < 4) return error.Truncated;
    if (std.mem.readInt(u16, bytes[0..2], .big) != soi) return error.NoSoi;
    var at: usize = 2;
    // SOI carries no length and no payload, but it is a segment the caller
    // reads as `segments[0]`, so it is recorded here rather than only checked.
    out[0] = .{ .marker = soi, .payload = bytes[2..2] };
    var count: usize = 1;
    while (at < bytes.len) {
        if (bytes[at] != 0xFF) return error.NotAMarker;
        while (at + 1 < bytes.len and bytes[at + 1] == 0xFF) at += 1;
        if (at + 1 >= bytes.len) return error.Truncated;
        const marker = std.mem.readInt(u16, bytes[at ..][0..2], .big);
        if (marker == eoi) {
            if (count == out.len) return error.TooManySegments;
            out[count] = .{ .marker = marker, .payload = bytes[at + 2 ..] };
            return out[0 .. count + 1];
        }
        const standalone = (marker >= 0xFFD0 and marker <= 0xFFD7) or marker == 0xFF01;
        if (standalone) {
            at += 2;
            continue;
        }
        if (at + 4 > bytes.len) return error.TruncatedHeader;
        const length = std.mem.readInt(u16, bytes[at + 2 ..][0..2], .big);
        if (length < 2) return error.ImpossibleLength;
        const payload_start = at + 4;
        const payload_end = payload_start + length - 2;
        if (payload_end > bytes.len) return error.TruncatedPayload;
        if (count == out.len) return error.TooManySegments;
        out[count] = .{ .marker = marker, .payload = bytes[payload_start..payload_end] };
        count += 1;
        // Everything after SOS is entropy-coded data, not more segments. T.81
        // B.2.3: the coded data ends at the next marker that is neither a
        // stuffed `FF 00` -- `FF 00` decodes to a data `FF` -- nor an RSTn
        // restart marker, both of which belong to the data rather than to what
        // follows it. Scanning past it as if it were segments is what made the
        // first scan byte of these fixtures fail as `NotAMarker`.
        if (marker == sos) {
            var scan = payload_end;
            while (scan + 1 < bytes.len) {
                if (bytes[scan] != 0xFF) {
                    scan += 1;
                    continue;
                }
                const next = bytes[scan + 1];
                if (next != 0x00 and !(next >= 0xD0 and next <= 0xD7)) break;
                scan += 1;
            }
            if (scan + 1 >= bytes.len) return error.Truncated;
            at = scan;
            continue;
        }
        at = payload_end;
    }
    return error.NoEoi;
}

fn checkContainer(w: *std.Io.Writer, allocator: std.mem.Allocator, fixture: Declared) !void {
    var storage: [16]Segment = undefined;
    const segments = try parseSegments(fixture.bytes, &storage);

    try checkInt(w, label(allocator, "{s}: SOI", .{fixture.name}), segments[0].marker, soi);
    try checkInt(w, label(allocator, "{s}: EOI", .{fixture.name}), segments[segments.len - 1].marker, eoi);
    try checkInt(w, label(allocator, "{s}: first marker after SOI", .{fixture.name}), segments[1].marker, app0);

    // JFIF 1.02 section 3: APP0's payload is the identifier "JFIF\0", then the
    // version as two bytes, the density unit, the X and Y densities, and a
    // thumbnail width and height. This is read here, not through libjpeg.
    try checkString(w, label(allocator, "{s}: APP0 identifier", .{fixture.name}), segments[1].payload[0..5], "JFIF\x00");
    try checkInt(w, label(allocator, "{s}: APP0 payload length", .{fixture.name}), segments[1].payload.len, 14);
    try checkString(w, label(allocator, "{s}: JFIF version", .{fixture.name}), segments[1].payload[5..7], "\x01\x01");
    // JFIF 1.02 section 3 after the version: the density unit, then X and Y
    // density as two bytes each, then the two thumbnail bytes. "density unit
    // and 1:1 density" is the five bytes before the thumbnail, not six.
    try checkString(w, label(allocator, "{s}: density unit and 1:1 density", .{fixture.name}), segments[1].payload[7..12], "\x00\x00\x01\x00\x01");

    var dqt_tables: usize = 0;
    var sof: ?Segment = null;
    var saw_sos = false;
    for (segments[1 .. segments.len - 1]) |segment| {
        if (segment.marker == dqt) {
            dqt_tables += 1;
            // T.81 B.2.4: the payload is one or more tables, each a
            // precision-and-identifier byte followed by 64 values in zig-zag
            // order. Every value in these fixtures is 1, which is fact 1 of the
            // module comment: quantisation is exact.
            try checkInt(w, label(allocator, "{s}: DQT precision is 8 bits", .{fixture.name}), segment.payload[0] >> 4, 0);
            try checkInt(w, label(allocator, "{s}: DQT table identifier", .{fixture.name}), segment.payload[0] & 0x0F, dqt_tables - 1);
            for (segment.payload[1..]) |value| {
                try checkInt(w, label(allocator, "{s}: DQT element", .{fixture.name}), value, 1);
            }
        }
        if (segment.marker == sof0 or segment.marker == sof2) sof = segment;
        if (segment.marker == sos) saw_sos = true;
    }
    try checkInt(w, label(allocator, "{s}: quantisation table count", .{fixture.name}), dqt_tables, fixture.dqt_tables);

    // T.81 B.2.2: the SOF payload is sample precision, height, width, the number
    // of components, and then three bytes per component.
    const frame = sof orelse return error.NoSof;
    try checkInt(w, label(allocator, "{s}: SOF sample precision", .{fixture.name}), frame.payload[0], 8);
    try checkInt(w, label(allocator, "{s}: SOF height", .{fixture.name}), std.mem.readInt(u16, frame.payload[1..3], .big), fixture.height);
    try checkInt(w, label(allocator, "{s}: SOF width", .{fixture.name}), std.mem.readInt(u16, frame.payload[3..5], .big), fixture.width);
    try checkInt(w, label(allocator, "{s}: SOF component count", .{fixture.name}), frame.payload[5], fixture.components);
    try checkInt(w, label(allocator, "{s}: SOF payload length", .{fixture.name}), frame.payload.len, 6 + 3 * fixture.components);
    try checkError(w, label(allocator, "{s}: a start-of-scan marker is present", .{fixture.name}), saw_sos);
}

// ---------------------------------------------------------------------------
// 3. The pixels, through libjpeg-turbo and against the specification
// ---------------------------------------------------------------------------

fn checkPixels(w: *std.Io.Writer, allocator: std.mem.Allocator, fixture: Declared) !void {
    var image: jpeg.Decompress = .{};
    defer image.deinit();
    try image.init(fixture.bytes);

    try checkInt(w, label(allocator, "{s}: width", .{fixture.name}), image.width(), fixture.width);
    try checkInt(w, label(allocator, "{s}: height", .{fixture.name}), image.height(), fixture.height);
    try checkInt(w, label(allocator, "{s}: components", .{fixture.name}), image.numComponents(), fixture.components);

    // The colourspace this fixture is decoded into is declared, not left to
    // libjpeg's default: a three-component image otherwise comes out as RGB,
    // and the greyscale read of `R=G=B=v` that the samples below rely on is
    // the one that has to be asked for.
    image.requestOutColorSpace(fixture.out);
    try image.startDecompress();
    try checkInt(w, label(allocator, "{s}: output width", .{fixture.name}), image.outputWidth(), fixture.width);
    try checkInt(w, label(allocator, "{s}: output height", .{fixture.name}), image.outputHeight(), fixture.height);
    try checkInt(w, label(allocator, "{s}: output components", .{fixture.name}), image.outColorComponents(), fixture.out_components);
    // `width` is u32 and `out_components` is i32 upstream's own pair of types;
    // the row length and the buffer size are computed here in `usize` rather
    // than mixed, so no line has to carry a cast twice.
    const width: usize = fixture.width;
    const height: usize = fixture.height;
    const outs: usize = @intCast(fixture.out_components);
    try checkInt(w, label(allocator, "{s}: row bytes", .{fixture.name}), image.rowBytes(), width * outs);

    const pixels = try allocator.alloc(u8, width * height * outs);
    defer allocator.free(pixels);
    try image.readAll(pixels);
    image.finishDecompress();

    if (fixture.components == 1 and fixture.sample == 0) {
        // The one fixture whose expected sample is not flat: rows 0-7 are 0 and
        // rows 8-15 are 255, which is the statement `tools/make-fixtures.py`
        // makes and what pins both ends of the sample range in one image.
        for (0..height) |y| {
            const want: u8 = if (y < height / 2) 0 else 255;
            for (0..width) |x| {
                const got = pixels[y * width + x];
                try checkInt(w, label(allocator, "{s}: row {d} sample {d}", .{ fixture.name, y, x }), got, want);
            }
        }
    } else {
        for (pixels, 0..) |got, i| {
            try checkInt(w, label(allocator, "{s}: sample {d}", .{ fixture.name, i }), got, fixture.sample);
        }
    }

    // A clean decode produced no recoverable warnings. `WARNMS` goes to
    // `emit_message` rather than to `error_exit`, so a damaged stream would be
    // observable here rather than fatal.
    try checkInt(w, label(allocator, "{s}: warnings", .{fixture.name}), image.warningCount(), 0);
    try checkError(w, label(allocator, "{s}: no warning text kept", .{fixture.name}), image.lastWarning() == null);
}

fn checkRgbDecode(w: *std.Io.Writer, allocator: std.mem.Allocator, fixture: Declared) !void {
    var image: jpeg.Decompress = .{};
    defer image.deinit();
    try image.init(fixture.bytes);
    image.requestOutColorSpace(.rgb);
    try image.startDecompress();
    try checkInt(w, label(allocator, "{s}: RGB output components", .{fixture.name}), image.outColorComponents(), 3);

    const pixels = try allocator.alloc(u8, @as(usize, fixture.width) * @as(usize, fixture.height) * 3);
    defer allocator.free(pixels);
    try image.readAll(pixels);
    image.finishDecompress();

    // For `R = G = B = v` the RGB decode is the identity, so all three channels
    // carry `v`. This is the colour transform checked in its own direction
    // rather than a round trip.
    for (0..@as(usize, fixture.width) * @as(usize, fixture.height)) |i| {
        for (0..3) |channel| {
            try checkInt(
                w,
                label(allocator, "{s}: pixel {d} channel {d}", .{ fixture.name, i, channel }),
                pixels[i * 3 + channel],
                fixture.sample,
            );
        }
    }
}

// ---------------------------------------------------------------------------
// 4. The writing side
// ---------------------------------------------------------------------------

fn checkEncode(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    // The same 8x8 flat block of 200 that `grey8x8-200.jpg` contains, encoded
    // here through the published facade. The produced stream is then parsed
    // with the same T.81 checks the fixtures went through, so the encoder is
    // measured against the specification rather than against the decoder.
    var out: jpeg.Compress = .{};
    defer out.deinit();
    out.init(8, 8, 1);
    // The documented order: `in_color_space` has to be right before
    // `jpeg_set_defaults` (`src/src/jpeglib.h:351-359`).
    out.setInputColorSpace(.grayscale);
    out.setDefaults();
    out.setQuality(100, true);
    out.startCompress();
    try checkInt(w, "encoded: bytes before finishCompress", out.bytes().len, 0);

    const block = [_]u8{200} ** 64;
    try checkInt(w, "encoded: scanlines accepted", try out.writeScanlines(&block), 8);
    out.finishCompress();

    const compressed = out.bytes();
    try checkInt(w, "encoded: SOI", std.mem.readInt(u16, compressed[0..2], .big), soi);
    try checkInt(w, "encoded: EOI", std.mem.readInt(u16, compressed[compressed.len - 2 ..][0..2], .big), eoi);

    var segment_storage: [16]Segment = undefined;
    const segments = try parseSegments(compressed, &segment_storage);
    try checkInt(w, "encoded: APP0 follows SOI", segments[1].marker, app0);
    try checkString(w, "encoded: APP0 identifier", segments[1].payload[0..5], "JFIF\x00");
    var saw_dqt = false;
    var saw_sof = false;
    var saw_sos = false;
    for (segments[1 .. segments.len - 1]) |segment| {
        if (segment.marker == dqt) saw_dqt = true;
        if (segment.marker == sof0 or segment.marker == sof2) {
            saw_sof = true;
            try checkInt(w, "encoded: SOF width", std.mem.readInt(u16, segment.payload[3..5], .big), 8);
            try checkInt(w, "encoded: SOF height", std.mem.readInt(u16, segment.payload[1..3], .big), 8);
        }
        if (segment.marker == sos) saw_sos = true;
    }
    try checkError(w, "encoded: a quantisation table is present", saw_dqt);
    try checkError(w, "encoded: a frame header is present", saw_sof);
    try checkError(w, "encoded: a start-of-scan marker is present", saw_sos);

    // The round trip, and nothing more: it compares this build's encoder with
    // this build's decoder. The four fixtures above are what make that
    // comparison meaningful, because their samples came from T.81 arithmetic
    // and from neither half of this program.
    var image: jpeg.Decompress = .{};
    defer image.deinit();
    try image.init(compressed);
    try checkInt(w, "round trip: width", image.width(), 8);
    try checkInt(w, "round trip: height", image.height(), 8);
    try image.startDecompress();
    const back = try allocator.alloc(u8, 64);
    defer allocator.free(back);
    try image.readAll(back);
    image.finishDecompress();
    for (back, 0..) |got, i| {
        try checkInt(w, label(allocator, "round trip: sample {d}", .{i}), got, 200);
    }

    // The ownership transition: destroying the compressor releases the
    // destination buffer, and a second `deinit` is a no-op rather than a
    // second free.
    out.deinit();
    try checkInt(w, "ownership: the compressor is closed", @intFromBool(out.isOpen()), 0);
    try checkInt(w, "ownership: the bytes went with it", out.bytes().len, 0);
    out.deinit();
    try checkInt(w, "ownership: a second deinit changes nothing", @intFromBool(out.isOpen()), 0);
}

// ---------------------------------------------------------------------------
// 5. The boundaries the facade documents
// ---------------------------------------------------------------------------

fn checkErrorPaths(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    // A row buffer that cannot hold one row. `jpeg_read_scanlines` takes no
    // length, so this is the boundary a C header cannot state and the reason
    // `readScanlines` checks it before handing the pointer over.
    {
        var image: jpeg.Decompress = .{};
        defer image.deinit();
        try image.init(grey8x8_200_jpg);
        try image.startDecompress();
        var short: [7]u8 = undefined;
        try checkError(
            w,
            "a 7-byte buffer for an 8-byte row is refused",
            image.readScanlines(&short) == error.RowBufferTooSmall,
        );
        // The same rule one level up: `readAll` computes the whole-image length.
        const whole_but_short = try allocator.alloc(u8, 63);
        defer allocator.free(whole_but_short);
        try checkError(
            w,
            "a 63-byte buffer for a 64-sample image is refused",
            image.readAll(whole_but_short) == error.RowBufferTooSmall,
        );
        // No `finishDecompress` here, deliberately. Both refusals above left the
        // stream part-read, and finishing it raises `JERR_TOO_LITTLE_DATA`
        // ("Application transferred too few scanlines",
        // `src/src/jdapimin.c:408`), which is fatal. A fatal error leaves the
        // object unusable, and the documented way out of that is
        // `jpeg_destroy`, which the `defer` above already does. Calling
        // `finish` to tidy up is what turned these two passing refusals into an
        // abort.
    }

    // A scanline buffer that is not a whole number of rows. One row here is
    // 8 bytes at 8x1 component, so 9 bytes would have libjpeg read past the end
    // of the caller's data.
    {
        var out: jpeg.Compress = .{};
        defer out.deinit();
        out.init(8, 8, 1);
        out.setInputColorSpace(.grayscale);
        out.setDefaults();
        out.startCompress();
        const ragged = [_]u8{200} ** 9;
        try checkError(
            w,
            "a buffer that is not a whole number of rows is refused",
            out.writeScanlines(&ragged) == error.RowBufferTooSmall,
        );
    }

    // The decompressor is not open before `init`, and it is closed after
    // `deinit`: the ownership transition a dependent has to be able to rely on.
    {
        var image: jpeg.Decompress = .{};
        try checkInt(w, "ownership: not open before init", @intFromBool(image.isOpen()), 0);
        try image.init(grey8x8_200_jpg);
        try image.startDecompress();
        var pixels: [64]u8 = undefined;
        try image.readAll(&pixels);
        image.finishDecompress();
        image.deinit();
        try checkInt(w, "ownership: closed after deinit", @intFromBool(image.isOpen()), 0);
        image.deinit();
        try checkInt(w, "ownership: a second deinit changes nothing", @intFromBool(image.isOpen()), 0);
    }
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

fn checkInt(w: *std.Io.Writer, what: []const u8, got: anytype, expected: anytype) !void {
    try w.print("{s: <56}{d}\n", .{ what, got });
    if (got != expected) {
        std.debug.print("consumer: {s}: expected {d}, computed {d}\n", .{ what, expected, got });
        return error.ConsumerCheckFailed;
    }
}

fn checkString(w: *std.Io.Writer, what: []const u8, got: []const u8, expected: []const u8) !void {
    try w.print("{s: <56}{s}\n", .{ what, got });
    if (!std.mem.eql(u8, got, expected)) {
        std.debug.print("consumer: {s}: expected \"{s}\", computed \"{s}\"\n", .{
            what,
            expected,
            got,
        });
        return error.ConsumerCheckFailed;
    }
}

fn checkError(w: *std.Io.Writer, what: []const u8, got: bool) !void {
    try w.print("{s: <56}{s}\n", .{ what, if (got) "yes" else "no" });
    if (!got) {
        std.debug.print("consumer: {s}: the documented result was not reached\n", .{what});
        return error.ConsumerCheckFailed;
    }
}