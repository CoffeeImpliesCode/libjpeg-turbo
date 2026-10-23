// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 4) return error.MissingBuildArguments;

    try init.environ_map.put("ZIG_GLOBAL_CACHE_DIR", args[1]);
    try init.environ_map.put("ZIG_LIB_DIR", args[2]);
    var child = try std.process.spawn(init.io, .{
        .argv = args[3..],
        .environ_map = init.environ_map,
    });
    defer child.kill(init.io);
    switch (try child.wait(init.io)) {
        .exited => |code| std.process.exit(code),
        else => return error.ConsumerTerminated,
    }
}
