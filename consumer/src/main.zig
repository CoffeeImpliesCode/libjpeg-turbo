// SPDX-License-Identifier: MIT
// See ../FORK-LICENSE.md for what that identifier covers.

//! Exercise the public module with embedded JPEG fixtures and independent expected metadata.
//! Linked and runtime-loaded builds use the same checks; runtime builds require an explicit provider.

const std = @import("std");
const jpeg = @import("libjpeg_turbo");

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// Read an explicit provider from `--provider` or `LIBJPEG_TURBO_TEST_PROVIDER`.
/// Runtime-loaded builds do not search a default location.
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

/// Print the missing-provider instruction.
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

/// Format a diagnostic label in the process arena.
fn label(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) []const u8 {
    return allocator.print(fmt, args) catch @panic("OOM");
}

/// Embedded 8x8 grayscale fixture; every sample is 200.
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

/// Embedded 16x16 grayscale fixture; its top half is 0 and bottom half is 255.
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

/// Embedded 8x8 RGB fixture; every pixel is (64, 64, 64).
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

/// Embedded 8x8 RGB fixture; every pixel is (200, 200, 200).
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

/// Expected marker metadata from T.81 and JFIF, independent of decoding.
const Declared = struct {
    name: []const u8,
    /// Fixture bytes.
    bytes: []const u8,
    /// SHA-256 recorded by `tools/check-fixtures.py`.
    sha256: []const u8,
    /// Fixture byte length.
    length: usize,
    width: u32,
    height: u32,
    /// Component count from the SOF marker.
    components: i32,
    /// Requested output colorspace.
    out: jpeg.ColorSpace,
    /// Output component count after conversion.
    out_components: i32,
    /// Number of DQT markers in the bytes, not inferred from component count.
    dqt_tables: usize,
    /// Expected decoded sample; the split fixture checks both halves separately.
    /// Equal-channel RGB fixtures decode to the same grayscale value.
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
        // Expected top-half sample; the bottom half is checked separately.
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

/// Marker codes assigned by T.81 B.2.1.
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

    // Runtime mode loads the explicit provider before any facade call.
    if (comptime jpeg.runtime_loaded) {
        try jpeg.load(.{ .path = try providerRequest(init) });
    }

    try w.print("libjpeg-turbo consumer\n", .{});
    try w.print("{s} provider, portable C configuration (WITH_SIMD off, " ++
        "SIMD_ARCHITECTURE NONE, no src/simd/ unit compiled)\n", .{
        if (jpeg.runtime_loaded) "loaded" else "linked",
    });
    // Print the translated headers' compile-time version; no provider version symbol is available to compare.
    try w.print("headers were compiled against libjpeg v6b, JPEG_LIB_VERSION {d}\n", .{
        jpeg.libjpeg_api_version,
    });

    // Check fixture bytes and metadata before decoding them.
    for (declared) |fixture| {
        try checkDigest(w, allocator, fixture);
        try checkContainer(w, allocator, fixture);
        try checkPixels(w, allocator, fixture);
    }

    // Equal RGB channels should decode to the same value in every channel.
    for (declared[2..]) |fixture| {
        try checkRgbDecode(w, allocator, fixture);
    }

    try checkEncode(w, allocator);
    try checkErrorPaths(w, allocator);

    try w.print("every answer matched T.81 and JFIF\n", .{});
    try w.flush();
}

fn checkDigest(w: *std.Io.Writer, allocator: std.mem.Allocator, fixture: Declared) !void {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(fixture.bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    // Build fixture labels dynamically because slice concatenation is comptime-only.
    try checkString(w, label(allocator, "{s} sha256", .{fixture.name}), &hex, fixture.sha256);
    try checkInt(w, label(allocator, "{s} byte length", .{fixture.name}), fixture.bytes.len, fixture.length);
}

/// One marker segment as this program parsed it, with nothing from libjpeg in it.
const Segment = struct {
    marker: u16,
    payload: []const u8,
};

/// Standalone markers have no length; others use big-endian lengths including two bytes, with FF fill allowed.
fn parseSegments(bytes: []const u8, out: []Segment) ![]Segment {
    if (bytes.len < 4) return error.Truncated;
    if (std.mem.readInt(u16, bytes[0..2], .big) != soi) return error.NoSoi;
    var at: usize = 2;
    // Record SOI as segment zero because callers inspect it.
    out[0] = .{ .marker = soi, .payload = bytes[2..2] };
    var count: usize = 1;
    while (at < bytes.len) {
        if (bytes[at] != 0xFF) return error.NotAMarker;
        while (at + 1 < bytes.len and bytes[at + 1] == 0xFF) at += 1;
        if (at + 1 >= bytes.len) return error.Truncated;
        const marker = std.mem.readInt(u16, bytes[at..][0..2], .big);
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
        // Scan data ends at the next marker; stuffed FF00 and restart markers remain in the scan.
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

    // Parse JFIF APP0 directly: identifier, version, density, and thumbnail dimensions.
    try checkString(w, label(allocator, "{s}: APP0 identifier", .{fixture.name}), segments[1].payload[0..5], "JFIF\x00");
    try checkInt(w, label(allocator, "{s}: APP0 payload length", .{fixture.name}), segments[1].payload.len, 14);
    try checkString(w, label(allocator, "{s}: JFIF version", .{fixture.name}), segments[1].payload[5..7], "\x01\x01");
    // After the version come density unit, X/Y density, then thumbnail dimensions.
    try checkString(w, label(allocator, "{s}: density unit and 1:1 density", .{fixture.name}), segments[1].payload[7..12], "\x00\x00\x01\x00\x01");

    var dqt_tables: usize = 0;
    var sof: ?Segment = null;
    var saw_sos = false;
    for (segments[1 .. segments.len - 1]) |segment| {
        if (segment.marker == dqt) {
            dqt_tables += 1;
            // Each DQT table has a precision/identifier byte and 64 zig-zag values.
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

    // SOF holds sample precision, dimensions, component count, and three bytes per component.
    const frame = sof orelse return error.NoSof;
    try checkInt(w, label(allocator, "{s}: SOF sample precision", .{fixture.name}), frame.payload[0], 8);
    try checkInt(w, label(allocator, "{s}: SOF height", .{fixture.name}), std.mem.readInt(u16, frame.payload[1..3], .big), fixture.height);
    try checkInt(w, label(allocator, "{s}: SOF width", .{fixture.name}), std.mem.readInt(u16, frame.payload[3..5], .big), fixture.width);
    try checkInt(w, label(allocator, "{s}: SOF component count", .{fixture.name}), frame.payload[5], fixture.components);
    try checkInt(w, label(allocator, "{s}: SOF payload length", .{fixture.name}), frame.payload.len, 6 + 3 * fixture.components);
    try checkError(w, label(allocator, "{s}: a start-of-scan marker is present", .{fixture.name}), saw_sos);
}

fn checkPixels(w: *std.Io.Writer, allocator: std.mem.Allocator, fixture: Declared) !void {
    var image: jpeg.Decompress = .{};
    defer image.deinit();
    try image.init(fixture.bytes);

    try checkInt(w, label(allocator, "{s}: width", .{fixture.name}), image.width(), fixture.width);
    try checkInt(w, label(allocator, "{s}: height", .{fixture.name}), image.height(), fixture.height);
    try checkInt(w, label(allocator, "{s}: components", .{fixture.name}), image.numComponents(), fixture.components);

    // Request the fixture's declared output colorspace rather than relying on libjpeg's default.
    image.requestOutColorSpace(fixture.out);
    try image.startDecompress();
    try checkInt(w, label(allocator, "{s}: output width", .{fixture.name}), image.outputWidth(), fixture.width);
    try checkInt(w, label(allocator, "{s}: output height", .{fixture.name}), image.outputHeight(), fixture.height);
    try checkInt(w, label(allocator, "{s}: output components", .{fixture.name}), image.outColorComponents(), fixture.out_components);
    const width: usize = fixture.width;
    const height: usize = fixture.height;
    const outs: usize = @intCast(fixture.out_components);
    try checkInt(w, label(allocator, "{s}: row bytes", .{fixture.name}), image.rowBytes(), width * outs);

    const pixels = try allocator.alloc(u8, width * height * outs);
    defer allocator.free(pixels);
    try image.readAll(pixels);
    image.finishDecompress();

    if (fixture.components == 1 and fixture.sample == 0) {
        // This fixture has rows 0-7 at 0 and rows 8-15 at 255.
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

    // Recoverable warnings use `emit_message`; a clean decode has none.
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

    // Equal RGB channels remain identical through the RGB decode transform.
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

fn checkEncode(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    // Encode the 8x8 fixture sample, then validate the stream against JPEG markers and expected pixels.
    var out: jpeg.Compress = .{};
    defer out.deinit();
    out.init(8, 8, 1);
    // Set input colorspace before defaults, as libjpeg requires.
    out.setInputColorSpace(.grayscale);
    out.setDefaults();
    out.setQuality(100, true);
    out.startCompress();
    try checkInt(w, "encoded: bytes before finishCompress", out.bytes().len, 0);

    const block: [64]u8 = @splat(200);
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

    // Independent fixture samples anchor this encoder/decoder round-trip.
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

    // Destroying the compressor releases its destination buffer; later deinit is harmless.
    out.deinit();
    try checkInt(w, "ownership: the compressor is closed", @intFromBool(out.isOpen()), 0);
    try checkInt(w, "ownership: the bytes went with it", out.bytes().len, 0);
    out.deinit();
    try checkInt(w, "ownership: a second deinit changes nothing", @intFromBool(out.isOpen()), 0);
}

fn checkErrorPaths(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    // Reject undersized rows before passing pointers to `jpeg_read_scanlines`, which has no length argument.
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
        // `readAll` also validates the whole-image length.
        const whole_but_short = try allocator.alloc(u8, 63);
        defer allocator.free(whole_but_short);
        try checkError(
            w,
            "a 63-byte buffer for a 64-sample image is refused",
            image.readAll(whole_but_short) == error.RowBufferTooSmall,
        );
        // Do not finish a part-read stream: libjpeg raises fatal `JERR_TOO_LITTLE_DATA`.
        // Destroy it instead; the defer above performs cleanup.
    }

    // Reject partial rows because libjpeg has no scanline-buffer length argument.
    {
        var out: jpeg.Compress = .{};
        defer out.deinit();
        out.init(8, 8, 1);
        out.setInputColorSpace(.grayscale);
        out.setDefaults();
        out.startCompress();
        const ragged: [9]u8 = @splat(200);
        try checkError(
            w,
            "a buffer that is not a whole number of rows is refused",
            out.writeScanlines(&ragged) == error.RowBufferTooSmall,
        );
    }

    // The decompressor is closed before init and after deinit.
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
