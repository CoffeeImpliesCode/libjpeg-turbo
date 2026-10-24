// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

//! Behavioural tests for the libjpeg-turbo facade.
//! Checks fixture pixels, JPEG markers, buffer limits, and ownership.
const std = @import("std");
const testing = std.testing;
const jpeg = @import("libjpeg_turbo");

const jcs_grayscale = 1;

const jcs_rgb = 2;

// Fixture table

const Fixture = struct {
    name: []const u8,
    bytes: []const u8,
    sha256: []const u8,
    length: usize,
    width: u32,
    height: u32,
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

// Independent known answers

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

// Color-space conversions

test "the two colour fixtures decode to the same value in greyscale" {
    const table = [_]struct { fixture: Fixture, sample: u8 }{
        .{ .fixture = rgb8x8_64, .sample = 64 },
        .{ .fixture = rgb8x8_200, .sample = 200 },
    };
    for (table) |entry| {
        var image: jpeg.Decompress = .{};
        defer image.deinit();
        try image.init(entry.fixture.bytes);
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

// Marker parsing

/// Walk JPEG markers into caller-provided segment storage.
const container = struct {
    const Segment = struct { marker: u16, payload: []const u8 };

    /// Parse the marker stream from SOI to EOI.
    fn segments(bytes: []const u8, out: []Segment) ![]Segment {
        if (bytes.len < 4) return error.Truncated;
        try expect(std.mem.readInt(u16, bytes[0..2], .big) == 0xFFD8, "file does not start with SOI");
        var at: usize = 2;
        var count: usize = 0;

        // SOI has no length field, so record its marker separately.
        try append(out, &count, 0xFFD8, bytes[2..2]);

        while (at < bytes.len) {
            if (bytes[at] != 0xFF) return error.NotAMarker;
            // Repeated FF fill bytes can precede a marker.
            while (at + 1 < bytes.len and bytes[at + 1] == 0xFF) at += 1;
            if (at + 1 >= bytes.len) return error.Truncated;
            const marker = std.mem.readInt(u16, bytes[at..][0..2], .big);
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

            // Skip stuffed FF bytes and restart markers inside entropy data.
            // Continue scanning until the next marker.
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

        // The fixture must contain SOI, JFIF APP0, DQT, SOF, SOS, and EOI.
        try expect(segments[0].marker == 0xFFD8, fixture.name);
        try expect(segments[segments.len - 1].marker == 0xFFD9, fixture.name);
        try expect(segments[1].marker == 0xFFE0, fixture.name);
        try testing.expectEqualStrings("JFIF\x00", segments[1].payload[0..5]);
        try expect(segments[1].payload.len == 14, fixture.name);
        try testing.expectEqualStrings("\x01\x01", segments[1].payload[5..7]);
        // JFIF density is big-endian; these fixtures use unitless density 1 and no thumbnail.
        try testing.expectEqualStrings("\x00\x00\x01\x00\x01\x00", segments[1].payload[7..13]);

        var saw_dqt = false;
        var saw_sof = false;
        var saw_sos = false;
        for (segments[1 .. segments.len - 1]) |segment| {
            if (segment.marker == 0xFFDB) {
                saw_dqt = true;
                // Fixture quantization tables are 8-bit and filled with ones.
                try expect(segment.payload[0] & 0xF0 == 0, fixture.name);
                const table_id = segment.payload[0] & 0x0F;
                try expect(table_id <= 1, fixture.name);
                for (segment.payload[1..]) |value| {
                    try testing.expectEqual(@as(u8, 1), value);
                }
            }
            if (segment.marker == 0xFFC0 or segment.marker == 0xFFC2) {
                saw_sof = true;
                // SOF0 and SOF2 identify baseline and progressive frames.
                try testing.expectEqual(@as(u8, 8), segment.payload[0]);
                // Frame dimensions are 16-bit big-endian values.
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

// Encoder round trip

test "an 8x8 block of 200 compresses and reads back as 200" {
    var out: jpeg.Compress = .{};
    defer out.deinit();
    out.init(8, 8, 1);
    out.setInputColorSpace(.grayscale);
    out.setDefaults();
    out.setQuality(100, true);
    out.startCompress();

    try testing.expectEqual(@as(usize, 0), out.bytes().len);

    const block: [64]u8 = @splat(200);
    const written = try out.writeScanlines(&block);
    try testing.expectEqual(@as(usize, 8), written);
    out.finishCompress();

    const compressed = out.bytes();
    try testing.expect(compressed.len > 0);
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

// Buffer-size checks

test "a row buffer too small for one row is refused, not written through" {
    var image: jpeg.Decompress = .{};
    defer image.deinit();
    try image.init(grey8x8.bytes);
    try image.startDecompress();

    var short: [7]u8 = undefined;
    try testing.expectError(error.RowBufferTooSmall, image.readScanlines(&short));

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

    // Nine bytes is not a whole number of eight-byte rows.
    const ragged: [9]u8 = @splat(200);
    try testing.expectError(error.RowBufferTooSmall, out.writeScanlines(&ragged));
}

test "a datastream whose SOF geometry disagrees with the decoded output is a different image" {
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

        // A row of exactly the reported size is accepted.
        var row: [64 * 3]u8 = undefined;
        const written = try image.readScanlines(row[0..image.rowBytes()]);
        try testing.expectEqual(@as(usize, 1), written);

        // Drain the remaining rows before finishing.
        var drain: [64 * 3]u8 = undefined;
        while (image.outputScanline() < image.outputHeight()) {
            _ = try image.readScanlines(drain[0..image.rowBytes()]);
        }
        image.finishDecompress();
    }
}

// Ownership transitions

test "deinit closes a Decompress and a second deinit is a no-op" {
    var image: jpeg.Decompress = .{};
    try testing.expect(!image.isOpen());
    try testing.expectEqual(@as(c_long, 0), image.warningCount());

    try image.init(grey8x8.bytes);
    try image.startDecompress();
    var pixels: [64]u8 = undefined;
    try image.readAll(&pixels);
    image.finishDecompress();

    image.deinit();
    try testing.expect(!image.isOpen());
    image.deinit();
    try testing.expect(!image.isOpen());
}

test "deinit closes a Compress and releases the destination buffer once" {
    var out: jpeg.Compress = .{};
    try testing.expect(!out.isOpen());
    try testing.expectEqual(@as(c_long, 0), out.warningCount());

    out.init(1, 1, 1);
    out.setInputColorSpace(.grayscale);
    out.setDefaults();
    out.setQuality(100, true);
    out.startCompress();
    const pixel = [_]u8{200};
    _ = try out.writeScanlines(&pixel);
    out.finishCompress();
    try testing.expect(out.bytes().len > 0);
    try testing.expectEqual(@as(c_long, 0), out.warningCount());

    out.deinit();
    try testing.expect(!out.isOpen());
    try testing.expectEqual(@as(usize, 0), out.bytes().len);
    try testing.expectEqual(@as(c_long, 0), out.warningCount());

    out.deinit();
    try testing.expect(!out.isOpen());
}

// Raw C ABI

test "the raw header constants are the libjpeg v6b values, not this build's" {
    try testing.expectEqual(@as(c_int, 62), jpeg.libjpeg_api_version);
    try testing.expectEqual(jcs_grayscale, @as(c_int, jpeg.c.JCS_GRAYSCALE));
    try testing.expectEqual(jcs_rgb, @as(c_int, jpeg.c.JCS_RGB));
}
