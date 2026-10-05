// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

//! Behavioural tests for the libjpeg-turbo facade.
//!
//! Nothing here pins a version string, an export list or a default constant.
//! Every expectation is a decoded sample or a marker field that ITU-T T.81 and
//! JFIF state, and those values were computed from arithmetic rather than read
//! out of any decoder - the arguments are below, so a reader can check them
//! without running anything.
//!
//! ## The four fixtures, and where their answers come from
//!
//! `tools/make-fixtures.py` writes all four JPEG streams from first principles
//! using no image library. Three facts produce every expected sample, and
//! `UPSTREAM.md` spells the arithmetic out in full:
//!
//!   1. **Both quantisation tables are all ones**, so quantisation is exact:
//!      the stored coefficient divided by one, with nothing rounded away.
//!   2. **Every 8x8 block is flat**, so its only non-zero DCT coefficient is the
//!      DC one, `F(0,0) = 8 * (sample - 128)` by the orthonormal scaling
//!      T.81 A.3.3 gives. The inverse DCT returns that divided by eight, which
//!      is `sample - 128`, and the level shift adds 128 back. The image
//!      therefore comes back *exactly*, with no tolerance anywhere.
//!   3. **The JFIF luma constants sum to a power of two**:
//!      `19595 + 38470 + 7471 = 65536 = 2^16`. So `R = G = B = v` gives
//!      `Y = v` exactly, and `Cb = Cr = 128` whose inverse is the identity - so
//!      an all-grey colour image decodes to `(v, v, v)` by that transform, not
//!      by a coincidence of rounding.
//!
//! | fixture | geometry | expectation |
//! |---|---|---|
//! | `fixtures/grey8x8-200.jpg` | 8x8, 1 component | every sample exactly **200** |
//! | `fixtures/grey16x16-halves.jpg` | 16x16, 1 component | scanlines 0-7 exactly **0**, 8-15 exactly **255** |
//! | `fixtures/rgb8x8-grey64.jpg` | 8x8, 3 components | every pixel exactly **(64, 64, 64)** |
//! | `fixtures/rgb8x8-grey200.jpg` | 8x8, 3 components | every pixel exactly **(200, 200, 200)** |
//!
//! 200 and 64 are neither 0 nor 255, so a decoder that saturated or truncated a
//! coefficient could not produce them, and 0/255 on either half of
//! `grey16x16-halves` pins the top and the bottom of the sample range in one
//! image.
//!
//! The two RGB fixtures are additionally decoded **to greyscale**, which is a
//! second independent answer from the same bytes: by fact 3 above the greyscale
//! decode of `R=G=B=v` is `v`. Decoding to RGB as well checks the colour
//! transform's other direction, and for `R=G=B` it is the identity.
//!
//! ## Digests, and why they are in a behavioural test file
//!
//! Each fixture's SHA-256 and byte length are recomputed here and compared with
//! what `tools/check-fixtures.py`, `UPSTREAM.md` and `CHANGELOG.md` record. The
//! expected pixels above were computed by hand and written into the generator,
//! so a fixture is an **independent known answer** rather than a round trip -
//! and that property only survives while the file is the same file. A silently
//! edited fixture would turn the strongest kind of check in this package into
//! the weakest, and this is what stops that.
//!
//! ## Ownership, and why there is no leak oracle here
//!
//! **`std.testing.allocator` cannot be a leak oracle for this library.**
//! libjpeg-turbo allocates through the C library's own allocator inside
//! `src/src/jmemmgr.c`, and `jpeg_mem_dest`/`jpeg_mem_src` transfer a buffer to
//! the library rather than taking one from a Zig allocator
//! (`src/src/jdatadst.c:143`, `:195`). The pool manager hands out chunks from a
//! linked list and frees whole pools rather than individual objects
//! (`src/src/jmemmgr.c:96-99`, `:1177-1183`), and it sets `cinfo->mem = NULL` on
//! the way out (`:1183`) so a destroy can only happen once. A test that
//! allocated through `std.testing.allocator` and reported "0 leaked" would be
//! measuring the wrong allocator and would stay silent if the library leaked its
//! own.
//!
//! **No custom `jpeg_memory_mgr` is installed in this file.** `README.zig.md`
//! requires a leak oracle *where a custom allocator is installed*; nothing
//! installs one here, so that conditional obligation does not apply, and the
//! reason is the paragraph above. What this file proves about ownership is a
//! **transition**, which is checkable without a balance:
//!
//!   * `deinit` closes the object, `isOpen` reports it, and a second `deinit`
//!     is a no-op rather than a second destroy or a second free.
//!   * `Compress.bytes` is empty before `finishCompress` and has exactly the
//!     length the library's own destination manager wrote afterwards - the
//!     compressed length, never the buffer's capacity.
//!
//! ## What is deliberately absent
//!
//! No version-string pin, no `@hasDecl` or export-presence test, no comparison
//! of a forwarding accessor with a raw member, no copy or non-zero-length check,
//! no "asserts it does not throw" test, no source-text test, no mock echo. A
//! round trip appears twice below and is a **supplement** in both: it compares
//! this build's encoder against this build's decoder, which the four known
//! answers above are what make meaningful.
const std = @import("std");
const testing = std.testing;
const jpeg = @import("libjpeg_turbo");

/// `JCS_GRAYSCALE`, from the libjpeg v6b `J_COLOR_SPACE`
/// (`src/src/jpeglib.h:264-290`: `JCS_UNKNOWN` 0, `JCS_GRAYSCALE` 1, `JCS_RGB`
/// 2, `JCS_YCbCr` 3). Named as a literal because the test states the ABI rather
/// than asking the library which value it uses.
const jcs_grayscale = 1;

/// `JCS_RGB`, same table.
const jcs_rgb = 2;

// ---------------------------------------------------------------------------
// The fixtures and the digests this repository records
// ---------------------------------------------------------------------------

const Fixture = struct {
    name: []const u8,
    bytes: []const u8,
    /// From `tools/check-fixtures.py`; the same table `UPSTREAM.md` prints.
    sha256: []const u8,
    length: usize,
    width: u32,
    height: u32,
    /// `cinfo.num_components`, which is what the SOF marker says.
    components: i32,
};

const grey8x8 = Fixture{
    .name = "grey8x8-200.jpg",
    .bytes = @embedFile("fixtures/grey8x8-200.jpg"),
    .sha256 = "f7f10aee901395fe1a12f424cd8d91f9bf2e181642cf0ab069b406d938cb9e2d",
    .length = 549,
    .width = 8,
    .height = 8,
    .components = 1,
};

const grey16x16 = Fixture{
    .name = "grey16x16-halves.jpg",
    .bytes = @embedFile("fixtures/grey16x16-halves.jpg"),
    .sha256 = "b2e2490ff88768780f7e48f1739d1a608dfc7b5c17a54c2665db29db8b51f4bf",
    .length = 555,
    .width = 16,
    .height = 16,
    .components = 1,
};

const rgb8x8_64 = Fixture{
    .name = "rgb8x8-grey64.jpg",
    .bytes = @embedFile("fixtures/rgb8x8-grey64.jpg"),
    .sha256 = "0704223b42ce860b9a28892da837fa160de3603ebd6cc8cd385dbb8a71f18684",
    .length = 629,
    .width = 8,
    .height = 8,
    .components = 3,
};

const rgb8x8_200 = Fixture{
    .name = "rgb8x8-grey200.jpg",
    .bytes = @embedFile("fixtures/rgb8x8-grey200.jpg"),
    .sha256 = "e31f0659abba47da10e4600fde1a3da25afdcacee2f1dde5029aeddade972b98",
    .length = 629,
    .width = 8,
    .height = 8,
    .components = 3,
};

// ---------------------------------------------------------------------------
// 1. Independent known answers
// ---------------------------------------------------------------------------

test "every fixture is the byte stream this repository records" {
    const table = [_]Fixture{ grey8x8, grey16x16, rgb8x8_64, rgb8x8_200 };
    for (table) |fixture| {
        var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(fixture.bytes, &digest, .{});
        try testing.expectEqualStrings(
            fixture.sha256,
            &std.fmt.bytesToHex(digest, .lower),
        );
        try testing.expectEqual(fixture.length, fixture.bytes.len);
    }
}

test "grey8x8-200.jpg decodes to exactly 200 in every sample" {
    var image: jpeg.Decompress = .{};
    defer image.deinit();
    try image.init(grey8x8.bytes);

    // The SOF marker, before `startDecompress`, is the only place the nominal
    // geometry and the component count come from.
    try testing.expectEqual(grey8x8.width, image.width());
    try testing.expectEqual(grey8x8.height, image.height());
    try testing.expectEqual(grey8x8.components, image.numComponents());
    try testing.expectEqual(jpeg.ColorSpace.grayscale, image.jpegColorSpace());

    try image.startDecompress();
    try testing.expectEqual(grey8x8.width, image.outputWidth());
    try testing.expectEqual(grey8x8.height, image.outputHeight());
    try testing.expectEqual(1, image.outColorComponents());
    try testing.expectEqual(8, image.rowBytes());

    var pixels: [8 * 8]u8 = undefined;
    try image.readAll(&pixels);
    for (pixels) |sample| {
        try testing.expectEqual(@as(u8, 200), sample);
    }
    image.finishDecompress();

    // A clean decode produced no recoverable warnings. `WARNMS` goes to
    // `emit_message` rather than to `error_exit`, so a damaged stream would be
    // observable here rather than fatal.
    try testing.expectEqual(@as(c_long, 0), image.warningCount());
    try testing.expect(image.lastWarning() == null);
}

test "grey16x16-halves.jpg decodes rows 0-7 to 0 and rows 8-15 to 255" {
    var image: jpeg.Decompress = .{};
    defer image.deinit();
    try image.init(grey16x16.bytes);

    try testing.expectEqual(grey16x16.width, image.width());
    try testing.expectEqual(grey16x16.height, image.height());
    try testing.expectEqual(grey16x16.components, image.numComponents());

    try image.startDecompress();
    try testing.expectEqual(16, image.rowBytes());

    var pixels: [16 * 16]u8 = undefined;
    try image.readAll(&pixels);

    // The split row is stated, not derived: this is one image with two halves,
    // so the expected sample depends on the row.
    for (0..16) |y| {
        const want: u8 = if (y < 8) 0 else 255;
        for (pixels[y * 16 ..][0..16]) |sample| {
            try testing.expectEqual(want, sample);
        }
    }
    image.finishDecompress();
    try testing.expectEqual(@as(c_long, 0), image.warningCount());
}

test "rgb8x8-grey64.jpg decodes to exactly (64,64,64) per pixel" {
    var image: jpeg.Decompress = .{};
    defer image.deinit();
    try image.init(rgb8x8_64.bytes);

    try testing.expectEqual(rgb8x8_64.components, image.numComponents());
    // Three components in the file, so `jpegColorSpace` is the JFIF three-
    // component space and not greyscale.
    try testing.expectEqual(jpeg.ColorSpace.ycbcr, image.jpegColorSpace());

    try image.startDecompress();
    try testing.expectEqual(3, image.outColorComponents());
    try testing.expectEqual(8 * 3, image.rowBytes());

    var pixels: [8 * 8 * 3]u8 = undefined;
    try image.readAll(&pixels);
    for (0..pixels.len / 3) |i| {
        try testing.expectEqual(@as(u8, 64), pixels[i * 3 + 0]);
        try testing.expectEqual(@as(u8, 64), pixels[i * 3 + 1]);
        try testing.expectEqual(@as(u8, 64), pixels[i * 3 + 2]);
    }
    image.finishDecompress();
    try testing.expectEqual(@as(c_long, 0), image.warningCount());
}

test "rgb8x8-grey200.jpg decodes to exactly (200,200,200) per pixel" {
    var image: jpeg.Decompress = .{};
    defer image.deinit();
    try image.init(rgb8x8_200.bytes);

    try testing.expectEqual(rgb8x8_200.width, image.width());
    try testing.expectEqual(rgb8x8_200.height, image.height());
    try testing.expectEqual(rgb8x8_200.components, image.numComponents());

    try image.startDecompress();
    var pixels: [8 * 8 * 3]u8 = undefined;
    try image.readAll(&pixels);
    for (0..pixels.len / 3) |i| {
        try testing.expectEqual(@as(u8, 200), pixels[i * 3 + 0]);
        try testing.expectEqual(@as(u8, 200), pixels[i * 3 + 1]);
        try testing.expectEqual(@as(u8, 200), pixels[i * 3 + 2]);
    }
    image.finishDecompress();
}

// ---------------------------------------------------------------------------
// 2. The same bytes, asked a different question
// ---------------------------------------------------------------------------

test "the two colour fixtures decode to the same value in greyscale" {
    // By fact 3 in the module comment - `19595 + 38470 + 7471 = 2^16` - the
    // greyscale decode of `R=G=B=v` is exactly `v`. So this is the colour
    // transform checked as arithmetic rather than as a round trip, and it is a
    // *different* answer from the RGB decode above on the same bytes.
    const table = [_]struct { fixture: Fixture, sample: u8 }{
        .{ .fixture = rgb8x8_64, .sample = 64 },
        .{ .fixture = rgb8x8_200, .sample = 200 },
    };
    for (table) |entry| {
        var image: jpeg.Decompress = .{};
        defer image.deinit();
        try image.init(entry.fixture.bytes);
        // Asked for greyscale explicitly. `jpeg_read_header` has already run
        // inside `init`, and on reaching SOS it called
        // `default_decompress_parms` (`src/src/jdapimin.c:337`), which sets
        // `out_color_space` from the datastream's own component count
        // (`src/src/jdapimin.c:145`, `:190`). For these two three-component
        // fixtures that is `JCS_RGB`, so without this line the count below
        // would be three and the test would be checking the colour decode it
        // already has above.
        image.requestOutColorSpace(.grayscale);
        try image.startDecompress();

        try testing.expectEqual(1, image.outColorComponents());
        try testing.expectEqual(8, image.rowBytes());

        var pixels: [8 * 8]u8 = undefined;
        try image.readAll(&pixels);
        for (pixels) |sample| {
            try testing.expectEqual(entry.sample, sample);
        }
        image.finishDecompress();
    }
}

test "a greyscale JPEG asked for RGB repeats the sample into three channels" {
    // The reverse direction of the same transform, and a place where a decoder
    // that guessed `out_color_space` would answer differently: `grey8x8-200` has
    // one component and is asked for three.
    var image: jpeg.Decompress = .{};
    defer image.deinit();
    try image.init(grey8x8.bytes);
    image.requestOutColorSpace(.rgb);
    try image.startDecompress();

    try testing.expectEqual(3, image.outColorComponents());
    try testing.expectEqual(8 * 3, image.rowBytes());

    var pixels: [8 * 8 * 3]u8 = undefined;
    try image.readAll(&pixels);
    for (0..pixels.len / 3) |i| {
        try testing.expectEqual(@as(u8, 200), pixels[i * 3 + 0]);
        try testing.expectEqual(@as(u8, 200), pixels[i * 3 + 1]);
        try testing.expectEqual(@as(u8, 200), pixels[i * 3 + 2]);
    }
    image.finishDecompress();
}

// ---------------------------------------------------------------------------
// 3. The container, read from the bytes and not from libjpeg
// ---------------------------------------------------------------------------

/// Every marker the four fixtures carry, as ITU-T T.81 A.2.1 and JFIF state
/// them. Read here, with libpng-style arithmetic and none of it through the
/// decoder, so a decoder that agreed with itself about a malformed stream would
/// still fail.
const container = struct {
    const Segment = struct { marker: u16, payload: []const u8 };

    /// Walks the marker stream from SOI to EOI.
    ///
    /// Standalone markers - SOI (`FFD8`), EOI (`FFD9`), RSTn (`FFD0`-`FFD7`) and
    /// TEM (`FF01`) - carry no length. Every other marker is followed by a
    /// two-byte big-endian length that counts itself but not the marker.
    fn segments(bytes: []const u8, out: []Segment) ![]Segment {
        if (bytes.len < 4) return error.Truncated;
        try expect(std.mem.readInt(u16, bytes[0..2], .big) == 0xFFD8, "file does not start with SOI");
        var at: usize = 2;
        var count: usize = 0;

        // SOI is recorded like any other segment, and it is the only marker
        // that is legal before anything else. Its two bytes carry no length,
        // so treating it as a length-bearing segment reads the next marker's
        // first two bytes as a 65504-byte length and walks off the file.
        try append(out, &count, 0xFFD8, bytes[2..2]);

        while (at < bytes.len) {
            if (bytes[at] != 0xFF) return error.NotAMarker;
            // Fill bytes: a marker may be preceded by any number of `FF`.
            while (at + 1 < bytes.len and bytes[at + 1] == 0xFF) at += 1;
            if (at + 1 >= bytes.len) return error.Truncated;
            const marker = std.mem.readInt(u16, bytes[at ..][0..2], .big);
            const code: u8 = @truncate(marker);

            if (code == 0xD9) {
                try append(out, &count, marker, bytes[at + 2 ..]);
                return out[0..count];
            }
            if (code == 0x01 or (code >= 0xD0 and code <= 0xD7)) {
                at += 2;
                continue;
            }
            if (at + 4 > bytes.len) return error.Truncated;
            const length = std.mem.readInt(u16, bytes[at + 2 ..][0..2], .big);
            if (length < 2) return error.ImpossibleLength;
            if (at + 2 + length > bytes.len) return error.Truncated;
            try append(out, &count, marker, bytes[at + 4 ..][0 .. length - 2]);
            at += 2 + length;

            if (code != 0xDA) continue;

            // Entropy-coded data follows SOS and is not part of the marker
            // stream. T.81 B.1.1.2 byte-stuffs a literal `FF` in the entropy
            // data as `FF 00`, and restart markers may appear between
            // entropy-coded units, so the scan runs to the first `FF` that is
            // followed by anything else. Reading the entropy data as markers
            // is what desynchronises a walker that does not do this.
            while (at + 1 < bytes.len) {
                if (bytes[at] != 0xFF) {
                    at += 1;
                    continue;
                }
                const next = bytes[at + 1];
                if (next == 0x00 or next == 0xFF or (next >= 0xD0 and next <= 0xD7)) {
                    at += 2;
                    continue;
                }
                break;
            }
        }
        return error.NoEoi;
    }

    fn append(out: []Segment, count: *usize, marker: u16, payload: []const u8) !void {
        if (count.* == out.len) return error.TooManySegments;
        out[count.*] = .{ .marker = marker, .payload = payload };
        count.* += 1;
    }
};

fn expect(ok: bool, why: []const u8) !void {
    if (!ok) {
        std.debug.print("libjpeg-turbo tests: {s}\n", .{why});
        return error.ExpectationFailed;
    }
}

test "the four fixtures carry the markers JFIF and T.81 specify" {
    var storage: [16]container.Segment = undefined;
    for ([_]Fixture{ grey8x8, grey16x16, rgb8x8_64, rgb8x8_200 }) |fixture| {
        const segments = try container.segments(fixture.bytes, &storage);
        try expect(segments.len >= 5, fixture.name);

        // SOI, EOI, APP0 with the JFIF identifier, at least one DQT, an SOF and
        // an SOS, in that order.
        try expect(segments[0].marker == 0xFFD8, fixture.name);
        try expect(segments[segments.len - 1].marker == 0xFFD9, fixture.name);
        try expect(segments[1].marker == 0xFFE0, fixture.name);
        // APP0's payload is "JFIF\0" then version, units, density, thumbnail.
        try testing.expectEqualStrings("JFIF\x00", segments[1].payload[0..5]);
        try expect(segments[1].payload.len == 14, fixture.name);
        // JFIF version 1.01, then units.
        try testing.expectEqualStrings("\x01\x01", segments[1].payload[5..7]);
        // Units, then the two densities as **big-endian** 16-bit values, then
        // the thumbnail width: units 0 (no units, aspect ratio only), X and Y
        // density 1 each, no thumbnail. JFIF spells the densities big-endian,
        // so a density of 1 is `00 01` and not `01 00` - `tools/make-fixtures.py`
        // writes them with `struct.pack(">HH", 1, 1)`.
        try testing.expectEqualStrings("\x00\x00\x01\x00\x01\x00", segments[1].payload[7..13]);

        var saw_dqt = false;
        var saw_sof = false;
        var saw_sos = false;
        for (segments[1 .. segments.len - 1]) |segment| {
            if (segment.marker == 0xFFDB) {
                saw_dqt = true;
                // Every quantisation table in these fixtures is all ones, which is
                // fact 1 of the module comment: quantisation is exact. The payload
                // is a run of (Pq<<4 | Tq) bytes followed by 64 values.
                try expect(segment.payload[0] & 0xF0 == 0, fixture.name);
                const table_id = segment.payload[0] & 0x0F;
                try expect(table_id <= 1, fixture.name);
                for (segment.payload[1..]) |value| {
                    try testing.expectEqual(@as(u8, 1), value);
                }
            }
            if (segment.marker == 0xFFC0 or segment.marker == 0xFFC2) {
                saw_sof = true;
                // SOF0 is baseline sequential DCT, SOF2 progressive; both are
                // legal and both are T.81 A.3. SOF payload: precision, height,
                // width, components, then per component id/sampling/table.
                try testing.expectEqual(@as(u8, 8), segment.payload[0]);
                // The SOF payload carries height and width as 16-bit values, so
                // each is widened before it is compared with the u32 the
                // decoded geometry is reported in.
                try testing.expectEqual(fixture.height, @as(u32, std.mem.readInt(u16, segment.payload[1..3], .big)));
                try testing.expectEqual(fixture.width, @as(u32, std.mem.readInt(u16, segment.payload[3..5], .big)));
                try testing.expectEqual(@as(u8, @intCast(fixture.components)), segment.payload[5]);
            }
            if (segment.marker == 0xFFDA) saw_sos = true;
        }
        try expect(saw_dqt, fixture.name);
        try expect(saw_sof, fixture.name);
        try expect(saw_sos, fixture.name);
    }
}


// ---------------------------------------------------------------------------
// 4. The encoder, as a supplement
// ---------------------------------------------------------------------------

test "an 8x8 block of 200 compresses and reads back as 200" {
    // A supplement and not a substitute: it compares this build's encoder with
    // this build's decoder. What it adds is that the compression side, the
    // memory destination and the memory source all work at all, and the answer
    // it checks - 200 comes back as 200 - is the same fact the grey8x8-200
    // fixture answers from arithmetic.
    var out: jpeg.Compress = .{};
    defer out.deinit();
    out.init(8, 8, 1);
    out.setInputColorSpace(.grayscale);
    out.setDefaults();
    out.setQuality(100, true);
    out.startCompress();

    // Nothing has been finished, so the destination has been terminated no
    // times and there is nothing to hand back. This is the ownership statement:
    // `bytes` is empty *because* `finishCompress` has not run, not because the
    // buffer is small.
    try testing.expectEqual(@as(usize, 0), out.bytes().len);

    const block = [_]u8{200} ** 64;
    const written = try out.writeScanlines(&block);
    try testing.expectEqual(@as(usize, 8), written);
    out.finishCompress();

    const compressed = out.bytes();
    try testing.expect(compressed.len > 0);
    // A JPEG datastream has no terminator, so the first two bytes are SOI by
    // definition rather than by anything this library reported.
    try testing.expectEqual(@as(u16, 0xFFD8), std.mem.readInt(u16, compressed[0..2], .big));
    try testing.expectEqual(
        @as(u16, 0xFFD9),
        std.mem.readInt(u16, compressed[compressed.len - 2 ..][0..2], .big),
    );

    var image: jpeg.Decompress = .{};
    defer image.deinit();
    try image.init(compressed);
    try testing.expectEqual(@as(u32, 8), image.width());
    try testing.expectEqual(@as(u32, 8), image.height());
    try image.startDecompress();

    var back: [64]u8 = undefined;
    try image.readAll(&back);
    for (back) |sample| {
        try testing.expectEqual(@as(u8, 200), sample);
    }
    image.finishDecompress();
    try testing.expectEqual(@as(c_long, 0), image.warningCount());
}

// ---------------------------------------------------------------------------
// 5. The boundaries the facade documents
// ---------------------------------------------------------------------------

test "a row buffer too small for one row is refused, not written through" {
    // `rowBytes` is `output_width * output_components` and libjpeg takes no
    // length, so a short buffer would be a write past the end of this test's
    // own stack. `readScanlines` checks it instead.
    var image: jpeg.Decompress = .{};
    defer image.deinit();
    try image.init(grey8x8.bytes);
    try image.startDecompress();

    var short: [7]u8 = undefined;
    try testing.expectError(error.RowBufferTooSmall, image.readScanlines(&short));

    // `readAll` computes the whole-image length and refuses the same way.
    var whole_but_short: [63]u8 = undefined;
    try testing.expectError(error.RowBufferTooSmall, image.readAll(&whole_but_short));
}

test "a scanline buffer that is not a whole number of rows is refused" {
    var out: jpeg.Compress = .{};
    defer out.deinit();
    out.init(8, 8, 1);
    out.setInputColorSpace(.grayscale);
    out.setDefaults();
    out.startCompress();

    // One row is 8 bytes at 8x1 component, so 9 bytes is not a whole number of
    // rows and libjpeg would read one past the slice.
    const ragged = [_]u8{200} ** 9;
    try testing.expectError(error.RowBufferTooSmall, out.writeScanlines(&ragged));
}

test "a datastream whose SOF geometry disagrees with the decoded output is a different image" {
    // The boundary this exercises is `rowBytes`, which is the length contract
    // `readScanlines` enforces and which nothing in a C header can express:
    // `JSAMPLE` is `unsigned char` (`src/src/jmorecfg.h:49`) and one pixel is
    // `output_components` of them, so a row is `output_width *
    // output_components` bytes and libjpeg writes through the caller's pointer
    // with no length of its own.
    //
    // The check is that the count comes from `jpeg_start_decompress`'s own
    // `output_width` and `output_components` and matches the geometry the SOF
    // marker carried, on both a one-component and a three-component image -
    // because a facade that computed the stride from the wrong field would be
    // right for one of them and wrong for the other.
    const table = [_]struct { fixture: Fixture, components: i32 }{
        .{ .fixture = grey8x8, .components = 1 },
        .{ .fixture = rgb8x8_64, .components = 3 },
    };
    for (table) |entry| {
        var image: jpeg.Decompress = .{};
        defer image.deinit();
        try image.init(entry.fixture.bytes);
        const nominal_width = image.width();
        try image.startDecompress();

        try testing.expectEqual(nominal_width, image.outputWidth());
        try testing.expectEqual(entry.components, image.outColorComponents());
        try testing.expectEqual(
            @as(usize, nominal_width) * @as(usize, @intCast(entry.components)),
            image.rowBytes(),
        );

        // And the buffer of exactly that size is accepted, which is the other
        // half of the boundary: a check that only refused would pass with a
        // stride that was too large.
        var row: [64 * 3]u8 = undefined;
        const written = try image.readScanlines(row[0..image.rowBytes()]);
        try testing.expectEqual(@as(usize, 1), written);

        // `finishDecompress` is only legal once every row has arrived:
        // upstream raises `JERR_TOO_LITTLE_DATA` for a partial image
        // (`src/src/jdapimin.c:407-408`) and this facade's `error_exit` stops
        // the process rather than returning an error. So the rest of the image
        // is drained first, through the same one-row buffer.
        var drain: [64 * 3]u8 = undefined;
        while (image.outputScanline() < image.outputHeight()) {
            _ = try image.readScanlines(drain[0..image.rowBytes()]);
        }
        image.finishDecompress();
    }
}

// ---------------------------------------------------------------------------
// 6. Ownership transitions
// ---------------------------------------------------------------------------

test "deinit closes a Decompress and a second deinit is a no-op" {
    var image: jpeg.Decompress = .{};
    // Before `init`: not open, and `warningCount` is 0 rather than a read
    // through a null master record.
    try testing.expect(!image.isOpen());
    try testing.expectEqual(@as(c_long, 0), image.warningCount());

    try image.init(grey8x8.bytes);
    try image.startDecompress();
    var pixels: [64]u8 = undefined;
    try image.readAll(&pixels);
    image.finishDecompress();

    image.deinit();
    try testing.expect(!image.isOpen());
    // The transition is the check: the same call again destroys nothing and
    // frees nothing, because the handle was cleared.
    image.deinit();
    try testing.expect(!image.isOpen());
}

test "deinit closes a Compress and releases the destination buffer once" {
    var out: jpeg.Compress = .{};
    try testing.expect(!out.isOpen());

    out.init(1, 1, 1);
    out.setInputColorSpace(.grayscale);
    out.setDefaults();
    out.setQuality(100, true);
    out.startCompress();
    const pixel = [_]u8{200};
    _ = try out.writeScanlines(&pixel);
    out.finishCompress();
    try testing.expect(out.bytes().len > 0);

    out.deinit();
    try testing.expect(!out.isOpen());
    // The compressed bytes are gone with the buffer, so `bytes` is empty rather
    // than dangling. That is the ownership statement: the slice never outlived
    // its object anywhere in this file.
    try testing.expectEqual(@as(usize, 0), out.bytes().len);

    out.deinit();
    try testing.expect(!out.isOpen());
}

// ---------------------------------------------------------------------------
// 7. The raw translated route
// ---------------------------------------------------------------------------

test "the raw header constants are the libjpeg v6b values, not this build's" {
    // `JPEG_LIB_VERSION` is this header's compile-time constant and is what
    // `jpeg_CreateDecompress` is handed. It is read here to show the number the
    // provider will be asked to accept - not as a version check of a provider,
    // which this SDK does not do and cannot do, because libjpeg-turbo exports no
    // version symbol (see `runtime/library.zig`).
    try testing.expectEqual(@as(c_int, 62), jpeg.libjpeg_api_version);
    try testing.expectEqual(jcs_grayscale, @as(c_int, jpeg.c.JCS_GRAYSCALE));
    try testing.expectEqual(jcs_rgb, @as(c_int, jpeg.c.JCS_RGB));
}