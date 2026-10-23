// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

//! Deterministic command-line demonstration of the libjpeg-turbo facade.
//! Checks fixture pixels, color conversion, buffer limits, and compression.

const std = @import("std");
const jpeg = @import("libjpeg_turbo");

const grey8x8 = @embedFile("fixtures/grey8x8-200.jpg");
const grey16x16 = @embedFile("fixtures/grey16x16-halves.jpg");
const rgb8x8_200 = @embedFile("fixtures/rgb8x8-grey200.jpg");

const ConfigurationError = error{NoProviderConfigured};

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
    // This is the compile-time header version, not a value read from the provider.
    try w.print("headers were compiled against libjpeg v6b, JPEG_LIB_VERSION {d}\n", .{
        jpeg.libjpeg_api_version,
    });

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

    // Decode the split-tone fixture.
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

    // Check RGB and greyscale conversion on the same fixture.
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

    // Reject a short row buffer before reading with a correctly sized one.
    {
        var image: jpeg.Decompress = .{};
        defer image.deinit();
        try image.init(grey8x8);
        try image.startDecompress();
        var short: [7]u8 = undefined;
        try checkError(w, "a 7-byte buffer for an 8-byte row is refused", image.readScanlines(&short) == error.RowBufferTooSmall);

        // Drain the remaining rows before finishing.
        var row: [8]u8 = undefined;
        while (image.outputScanline() < image.outputHeight()) {
            _ = try image.readScanlines(&row);
        }
        try checkInt(w, "an 8-byte row drains the rest after the refusal", image.outputScanline(), image.outputHeight());
        image.finishDecompress();
    }

    // Encode, finish, and verify compressed output.
    {
        var out: jpeg.Compress = .{};
        defer out.deinit();
        out.init(8, 8, 1);
        out.setInputColorSpace(.grayscale);
        out.setDefaults();
        out.setQuality(100, true);
        out.startCompress();
        try checkInt(w, "encode: bytes before finishCompress", out.bytes().len, 0);

        const block: [64]u8 = @splat(200);
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
