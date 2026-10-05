// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

//! A runnable, deterministic demonstration of the libjpeg-turbo facade.
//!
//! `zig build smoke` runs this. There is no input to supply and no output that
//! depends on the host, the clock or a random seed, so the same lines come out
//! every time.
//!
//! Every answer below is an expected value computed from ITU-T T.81 and JFIF,
//! not a value this program printed for comparison. Three facts produce all of
//! them, and `tests.zig`'s module comment gives the arithmetic:
//!
//!   1. both quantisation tables are all ones, so quantisation is exact;
//!   2. every 8x8 block is flat, so its only coefficient is `8 * (sample - 128)`
//!      and the inverse DCT returns `sample - 128` before the level shift adds
//!      128 back - so the image comes back *exactly*, with no tolerance;
//!   3. the JFIF luma constants satisfy `19595 + 38470 + 7471 = 2^16`, so
//!      `R = G = B = v` decodes to `(v, v, v)` by that transform rather than by
//!      a coincidence of rounding.
//!
//! A mismatch prints both sides and exits non-zero, so this is a check and not a
//! demo.
//!
//! In a runtime-loading build the provider is named on the command line
//! (`--provider <path>`) or in `LIBJPEG_TURBO_TEST_PROVIDER`, and the program
//! says which configuration it is in the first two lines. In a linked build
//! neither is needed and neither is read.
//!
//! What it exercises, in order: the three fixtures decoded to their stated
//! samples, a colour transform in both directions, a row buffer one byte short
//! of a row refused, a compress/decompress cycle, and the ownership transition
//! of destroying both objects.

const std = @import("std");
const jpeg = @import("libjpeg_turbo");

/// The fixtures, embedded so the run needs no file system.
const grey8x8 = @embedFile("fixtures/grey8x8-200.jpg");
const grey16x16 = @embedFile("fixtures/grey16x16-halves.jpg");
const rgb8x8_200 = @embedFile("fixtures/rgb8x8-grey200.jpg");

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// The provider this run should load, from `--provider <path>` or from
/// `LIBJPEG_TURBO_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location or falls back to
/// a linked copy: a runtime-loading build that was not told which file to load
/// reports that it was not told, rather than loading something else.
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
        "smoke: this is a runtime-loading build. Pass --provider <path>, or export " ++
            "LIBJPEG_TURBO_TEST_PROVIDER with a shared object exporting the 66 jpeg_* " ++
            "names of zig/translate.h. Nothing is loaded by default and no other file " ++
            "is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    if (comptime jpeg.runtime_loaded) {
        try jpeg.load(.{ .path = try providerRequest(init) });
    }

    try w.print("libjpeg-turbo consumer of the published module\n", .{});
    try w.print("{s} provider, SIMD configuration: portable C (WITH_SIMD off, " ++
        "SIMD_ARCHITECTURE NONE, no src/simd/ unit compiled)\n", .{
        if (jpeg.runtime_loaded) "loaded" else "linked",
    });
    // Printed, not compared: `JPEG_LIB_VERSION` is a compile-time constant of
    // the translated headers, not a value read back from a provider, and
    // libjpeg-turbo exports no version symbol to compare anything with
    // (`runtime/library.zig`). Version provenance belongs to the provenance
    // gate; the samples below are what this program decides on.
    try w.print("headers were compiled against libjpeg v6b, JPEG_LIB_VERSION {d}\n", .{
        jpeg.libjpeg_api_version,
    });

    // 1. A flat 8x8 block of 200, which is what `fixtures/grey8x8-200.jpg`
    //    contains.
    {
        var image: jpeg.Decompress = .{};
        defer image.deinit();
        try image.init(grey8x8);
        try checkInt(w, "grey8x8-200: image width", image.width(), 8);
        try checkInt(w, "grey8x8-200: image height", image.height(), 8);
        try checkInt(w, "grey8x8-200: components", image.numComponents(), 1);
        try image.startDecompress();
        try checkInt(w, "grey8x8-200: output components", image.outColorComponents(), 1);
        try checkInt(w, "grey8x8-200: row bytes", image.rowBytes(), 8);

        var pixels: [64]u8 = undefined;
        try image.readAll(&pixels);
        for (pixels, 0..) |sample, i| {
            if (sample != 200) {
                std.debug.print("smoke: grey8x8-200: sample {d} is {d}, expected 200\n", .{ i, sample });
                return error.SmokeCheckFailed;
            }
        }
        try w.print("{s: <44}all 64 samples are 200\n", .{"grey8x8-200: decoded"});
        image.finishDecompress();
        try checkInt(w, "grey8x8-200: warnings", image.warningCount(), 0);
    }

    // 2. One image with two halves, so the expected sample depends on the row.
    {
        var image: jpeg.Decompress = .{};
        defer image.deinit();
        try image.init(grey16x16);
        try image.startDecompress();
        try checkInt(w, "grey16x16-halves: row bytes", image.rowBytes(), 16);

        var pixels: [16 * 16]u8 = undefined;
        try image.readAll(&pixels);
        for (0..16) |y| {
            const want: u8 = if (y < 8) 0 else 255;
            for (pixels[y * 16 ..][0..16], 0..) |sample, x| {
                if (sample != want) {
                    std.debug.print(
                        "smoke: grey16x16-halves: sample {d} of row {d} is {d}, expected {d}\n",
                        .{ x, y, sample, want },
                    );
                    return error.SmokeCheckFailed;
                }
            }
        }
        try w.print("{s: <44}rows 0-7 are 0, rows 8-15 are 255\n", .{"grey16x16-halves: decoded"});
        image.finishDecompress();
    }

    // 3. The colour transform in both directions on the same bytes. The RGB
    //    decode is the identity for R=G=B; the greyscale decode is `v` because
    //    the JFIF luma constants sum to 2^16.
    {
        var rgb: jpeg.Decompress = .{};
        defer rgb.deinit();
        try rgb.init(rgb8x8_200);
        try rgb.startDecompress();
        try checkInt(w, "rgb8x8-grey200: output components", rgb.outColorComponents(), 3);
        var pixels: [8 * 8 * 3]u8 = undefined;
        try rgb.readAll(&pixels);
        for (0..pixels.len / 3) |i| {
            for (0..3) |channel| {
                if (pixels[i * 3 + channel] != 200) {
                    std.debug.print(
                        "smoke: rgb8x8-grey200: channel {d} of pixel {d} is {d}, expected 200\n",
                        .{ channel, i, pixels[i * 3 + channel] },
                    );
                    return error.SmokeCheckFailed;
                }
            }
        }
        try w.print("{s: <44}every pixel is (200,200,200)\n", .{"rgb8x8-grey200: decoded to RGB"});
        rgb.finishDecompress();
    }
    {
        var grey: jpeg.Decompress = .{};
        defer grey.deinit();
        try grey.init(rgb8x8_200);
        // `jpeg_read_header` has already run inside `init` and set
        // `out_color_space` from the datastream's own component count
        // (`src/src/jdapimin.c:337`, `:145`, `:190`), which for a
        // three-component JFIF is `JCS_RGB`. Ask for greyscale explicitly, or
        // this would be the RGB decode above again.
        grey.requestOutColorSpace(.grayscale);
        try grey.startDecompress();
        try checkInt(w, "rgb8x8-grey200: greyscale components", grey.outColorComponents(), 1);
        var pixels: [64]u8 = undefined;
        try grey.readAll(&pixels);
        for (pixels, 0..) |sample, i| {
            if (sample != 200) {
                std.debug.print("smoke: rgb8x8-grey200: grey sample {d} is {d}, expected 200\n", .{ i, sample });
                return error.SmokeCheckFailed;
            }
        }
        try w.print("{s: <44}every sample is 200\n", .{"rgb8x8-grey200: decoded to greyscale"});
        grey.finishDecompress();
    }

    // 4. A row buffer one byte short of a row. `jpeg_read_scanlines` takes no
    //    length, so this is the boundary a C header cannot state.
    {
        var image: jpeg.Decompress = .{};
        defer image.deinit();
        try image.init(grey8x8);
        try image.startDecompress();
        var short: [7]u8 = undefined;
        try checkError(w, "a 7-byte buffer for an 8-byte row is refused", image.readScanlines(&short) == error.RowBufferTooSmall);

        // The refusal left the image unread, and `jpeg_finish_decompress`
        // raises `JERR_TOO_LITTLE_DATA` for a partial image
        // (`src/src/jdapimin.c:407-408`), which reaches `error_exit` and stops
        // the process. So the rest is drained through a correctly sized buffer
        // first, which also checks that a right-sized one is accepted after the
        // refusal.
        var row: [8]u8 = undefined;
        while (image.outputScanline() < image.outputHeight()) {
            _ = try image.readScanlines(&row);
        }
        try checkInt(w, "an 8-byte row drains the rest after the refusal", image.outputScanline(), image.outputHeight());
        image.finishDecompress();
    }

    // 5. The compression side, the memory destination and the memory source,
    //    and the ownership transition of destroying both objects.
    {
        var out: jpeg.Compress = .{};
        defer out.deinit();
        out.init(8, 8, 1);
        out.setInputColorSpace(.grayscale);
        out.setDefaults();
        out.setQuality(100, true);
        out.startCompress();
        try checkInt(w, "encode: bytes before finishCompress", out.bytes().len, 0);

        const block = [_]u8{200} ** 64;
        try checkInt(w, "encode: scanlines accepted", try out.writeScanlines(&block), 8);
        out.finishCompress();
        const compressed = out.bytes();
        try checkInt(w, "encode: SOI", std.mem.readInt(u16, compressed[0..2], .big), 0xFFD8);
        try checkInt(w, "encode: EOI", std.mem.readInt(u16, compressed[compressed.len - 2 ..][0..2], .big), 0xFFD9);

        var image: jpeg.Decompress = .{};
        defer image.deinit();
        try image.init(compressed);
        try image.startDecompress();
        var back: [64]u8 = undefined;
        try image.readAll(&back);
        for (back, 0..) |sample, i| {
            if (sample != 200) {
                std.debug.print("smoke: encode: sample {d} read back as {d}, expected 200\n", .{ i, sample });
                return error.SmokeCheckFailed;
            }
        }
        try w.print("{s: <44}all 64 samples are 200\n", .{"encode: decoded back"});
        image.finishDecompress();

        out.deinit();
        try checkInt(w, "ownership: the compressor is closed", @intFromBool(out.isOpen()), 0);
        out.deinit();
        try checkInt(w, "ownership: a second deinit changes nothing", @intFromBool(out.isOpen()), 0);
        try checkInt(w, "ownership: the bytes are gone with it", out.bytes().len, 0);
    }

    try w.print("every answer matched the value T.81 and JFIF imply\n", .{});
    try w.flush();
}

fn checkInt(w: *std.Io.Writer, what: []const u8, got: anytype, expected: anytype) !void {
    try w.print("{s: <44}{d}\n", .{ what, got });
    if (got != expected) {
        std.debug.print("smoke: {s}: expected {d}, computed {d}\n", .{ what, expected, got });
        return error.SmokeCheckFailed;
    }
}

fn checkError(w: *std.Io.Writer, what: []const u8, got: bool) !void {
    try w.print("{s: <44}{s}\n", .{ what, if (got) "yes" else "no" });
    if (!got) {
        std.debug.print("smoke: {s}: the documented error was not reported\n", .{what});
        return error.SmokeCheckFailed;
    }
}