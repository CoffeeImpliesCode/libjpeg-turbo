// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.
//
//! Generate `jconfig.h`, `jconfigint.h` and `jversion.h` from upstream templates and target defines.
//! Render all three before writing; unresolved substitutions fail without partial output.
//! Configuration values come from the build target, not the generator host.

const std = @import("std");
const Io = std.Io;

/// Limit template input to avoid reading an unexpected large file.
const max_template_bytes = 8 * 1024 * 1024;

/// One `@NAME@` value, from `--define NAME=VALUE`.
const PlainValue = struct {
    name: []const u8,
    value: []const u8,
};

/// Optional value for `#cmakedefine`; null renders CMake's `/* #undef NAME */`.
const CmakeValue = struct {
    name: []const u8,
    value: ?[]const u8,
};

/// Parsed input paths and values for one invocation.
const Options = struct {
    jconfig_in: []const u8 = "",
    jconfig_out: []const u8 = "",
    jversion_in: []const u8 = "",
    jversion_out: []const u8 = "",
    jconfigint_in: []const u8 = "",
    jconfigint_out: []const u8 = "",
    plain: std.ArrayList(PlainValue) = .empty,
    cmake: std.ArrayList(CmakeValue) = .empty,
};

/// One template to render.
const Template = struct {
    /// Name used to identify this template in diagnostics.
    label: []const u8,
    input: []const u8,
    output: []const u8,
};

/// Require explicit template paths; guessing can silently generate wrong headers.
fn parse(
    arena: std.mem.Allocator,
    args: []const [:0]const u8,
) !Options {
    var options: Options = .{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--jconfig-in")) {
            options.jconfig_in = try next(arena, args, &i);
        } else if (std.mem.eql(u8, arg, "--jconfig-out")) {
            options.jconfig_out = try next(arena, args, &i);
        } else if (std.mem.eql(u8, arg, "--jversion-in")) {
            options.jversion_in = try next(arena, args, &i);
        } else if (std.mem.eql(u8, arg, "--jversion-out")) {
            options.jversion_out = try next(arena, args, &i);
        } else if (std.mem.eql(u8, arg, "--jconfigint-in")) {
            options.jconfigint_in = try next(arena, args, &i);
        } else if (std.mem.eql(u8, arg, "--jconfigint-out")) {
            options.jconfigint_out = try next(arena, args, &i);
        } else if (std.mem.eql(u8, arg, "--define")) {
            const pair = try next(arena, args, &i);
            const eq = std.mem.indexOfScalar(u8, pair, '=') orelse {
                std.debug.print(
                    "jconfig: --define wants NAME=VALUE, got '{s}'\n",
                    .{pair},
                );
                return error.BadArgument;
            };
            try options.plain.append(arena, .{
                .name = pair[0..eq],
                .value = pair[eq + 1 ..],
            });
        } else if (std.mem.eql(u8, arg, "--cmake-define")) {
            const pair = try next(arena, args, &i);
            if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
                try options.cmake.append(arena, .{
                    .name = pair[0..eq],
                    .value = pair[eq + 1 ..],
                });
            } else {
                try options.cmake.append(arena, .{ .name = pair, .value = "1" });
            }
        } else if (std.mem.eql(u8, arg, "--cmake-undef")) {
            try options.cmake.append(arena, .{
                .name = try next(arena, args, &i),
                .value = null,
            });
        } else {
            std.debug.print("jconfig: unknown argument '{s}'\n", .{arg});
            usage();
            return error.BadArgument;
        }
    }

    for ([_]struct { []const u8, []const u8 }{
        .{ "jconfig", options.jconfig_in },
        .{ "jconfig", options.jconfig_out },
        .{ "jversion", options.jversion_in },
        .{ "jversion", options.jversion_out },
        .{ "jconfigint", options.jconfigint_in },
        .{ "jconfigint", options.jconfigint_out },
    }) |pair| {
        if (pair[1].len == 0) {
            std.debug.print("jconfig: no --{s} path was given\n", .{pair[0]});
            usage();
            return error.BadArgument;
        }
    }
    return options;
}

fn next(arena: std.mem.Allocator, args: []const [:0]const u8, i: *usize) ![]const u8 {
    if (i.* + 1 >= args.len) {
        std.debug.print("jconfig: '{s}' has no value\n", .{args[i.*]});
        usage();
        return error.BadArgument;
    }
    i.* += 1;
    return arena.dupe(u8, args[i.*]);
}

fn usage() void {
    std.debug.print(
        \\usage: jconfig --jconfig-in PATH --jconfig-out PATH
        \\              --jversion-in PATH --jversion-out PATH
        \\              --jconfigint-in PATH --jconfigint-out PATH
        \\              [--define NAME=VALUE]... [--cmake-define NAME[=VALUE]]...
        \\              [--cmake-undef NAME]...
        \\
    , .{});
}

pub fn main(init: std.process.Init) !void {
    var arena_state: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try init.minimal.args.toSlice(arena);
    const options = parse(arena, args) catch |err| {
        usage();
        return err;
    };

    const plain = try plainTable(arena, options.plain.items);
    const cmake = try cmakeTable(arena, options.cmake.items);

    const templates = [_]Template{
        .{ .label = "jconfig", .input = options.jconfig_in, .output = options.jconfig_out },
        .{ .label = "jversion", .input = options.jversion_in, .output = options.jversion_out },
        .{
            .label = "jconfigint",
            .input = options.jconfigint_in,
            .output = options.jconfigint_out,
        },
    };

    // Render all templates before writing, so failures cannot leave mixed stale outputs.
    var rendered: [templates.len][]const u8 = undefined;
    for (templates, 0..) |template, index| {
        const upstream = try Io.Dir.cwd().readFileAlloc(
            init.io,
            template.input,
            arena,
            .limited(max_template_bytes),
        );
        rendered[index] = try render(arena, template.label, upstream, plain, cmake);
    }
    for (templates, rendered) |template, text| {
        try Io.Dir.cwd().writeFile(init.io, .{
            .sub_path = template.output,
            .data = text,
        });
    }
}

fn plainTable(
    arena: std.mem.Allocator,
    values: []const PlainValue,
) !std.StringHashMap([]const u8) {
    var map: std.StringHashMap([]const u8) = .init(arena);
    for (values) |value| {
        // Duplicate definitions make configuration depend on argument order.
        const result = try map.getOrPut(value.name);
        if (result.found_existing) {
            std.debug.print(
                "jconfig: --define {s}= was given twice ('{s}' and '{s}')\n",
                .{ value.name, result.value_ptr.*, value.value },
            );
            return error.DuplicateDefine;
        }
        result.value_ptr.* = value.value;
    }
    return map;
}

fn cmakeTable(
    arena: std.mem.Allocator,
    values: []const CmakeValue,
) !std.StringHashMap(?[]const u8) {
    var map: std.StringHashMap(?[]const u8) = .init(arena);
    for (values) |value| {
        const result = try map.getOrPut(value.name);
        if (result.found_existing) {
            std.debug.print(
                "jconfig: {s} was given both a --cmake-define and a --cmake-undef\n",
                .{value.name},
            );
            return error.DuplicateDefine;
        }
        result.value_ptr.* = value.value;
    }
    return map;
}

/// Substitute template values and resolve `#cmakedefine` directives.
pub fn render(
    arena: std.mem.Allocator,
    label: []const u8,
    upstream: []const u8,
    plain: std.StringHashMap([]const u8),
    cmake: std.StringHashMap(?[]const u8),
) ![]const u8 {
    const substituted = try substituteAtVars(arena, label, upstream, plain, cmake);
    return try resolveCmakedefine(arena, label, substituted, cmake);
}

/// Match CMake's bare `@NAME@` identifiers; preserve other `@` text such as email addresses.
fn isIdentifier(text: []const u8) bool {
    if (text.len == 0) return false;
    if (!std.ascii.isAlphabetic(text[0]) and text[0] != '_') return false;
    for (text[1..]) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    }
    return true;
}

/// Replaces every `@NAME@` for which a value was supplied.
fn substituteAtVars(
    arena: std.mem.Allocator,
    label: []const u8,
    upstream: []const u8,
    plain: std.StringHashMap([]const u8),
    cmake: std.StringHashMap(?[]const u8),
) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;

    var i: usize = 0;
    while (i < upstream.len) {
        const at = std.mem.indexOfScalarPos(u8, upstream, i, '@') orelse {
            try w.writeAll(upstream[i..]);
            break;
        };
        try w.writeAll(upstream[i..at]);
        const close = std.mem.indexOfScalarPos(u8, upstream, at + 1, '@') orelse {
            // An unmatched `@` is literal text, not a placeholder.
            try w.writeAll(upstream[at..]);
            break;
        };
        const name = upstream[at + 1 .. close];
        if (!isIdentifier(name)) {
            try w.writeAll(upstream[at .. close + 1]);
            i = close + 1;
            continue;
        }
        // Resolve `#cmakedefine` separately; it is not an `@NAME@` substitution.
        if (plain.get(name)) |value| {
            try w.writeAll(value);
        } else if (cmake.get(name)) |value| {
            try w.writeAll(value orelse "");
        } else {
            std.debug.print(
                "jconfig: {s}: no value was supplied for '@{s}@'\n" ++
                    "jconfig: nothing was written.\n",
                .{ label, name },
            );
            listSupplied(plain, cmake);
            return error.MissingSubstitution;
        }
        i = close + 1;
    }
    return out.written();
}

/// Apply CMake's `#cmakedefine` and `#cmakedefine01` rules.
/// Unset variables become `/* #undef NAME */`; set values emit `#define`, and `01` emits `1` or `0`.
fn resolveCmakedefine(
    arena: std.mem.Allocator,
    label: []const u8,
    text: []const u8,
    cmake: std.StringHashMap(?[]const u8),
) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        try w.writeAll(resolveCmakedefineLine(arena, label, line, cmake) catch |err| {
            std.debug.print("jconfig: {s}: bad #cmakedefine line: {s}\n", .{ label, @errorName(err) });
            return err;
        });
        try w.writeByte('\n');
    }
    return out.written();
}

/// Resolve one directive line using template and argument strings.
fn resolveCmakedefineLine(
    arena: std.mem.Allocator,
    label: []const u8,
    line: []const u8,
    cmake: std.StringHashMap(?[]const u8),
) ![]const u8 {
    const marker = "#cmakedefine";
    const hash = std.mem.indexOf(u8, line, marker) orelse return line;
    // Process directives only at line start after whitespace; preserve inline text.
    if (std.mem.trim(u8, line[0..hash], " \t").len != 0) return line;

    var rest = std.mem.trim(u8, line[hash + marker.len ..], " \t");
    const is01 = std.mem.startsWith(u8, rest, "01");
    if (is01) rest = rest[2..];

    var name_end: usize = 0;
    while (name_end < rest.len) : (name_end += 1) {
        const c = rest[name_end];
        if (!std.ascii.isAlphanumeric(c) and c != '_') break;
    }
    if (name_end == 0) {
        std.debug.print("jconfig: {s}: '#cmakedefine' with no variable name\n", .{label});
        return error.BadCmakedefine;
    }
    const name = rest[0..name_end];
    const tail = std.mem.trim(u8, rest[name_end..], " \t");
    if (tail.len != 0 and tail[0] != '1' and tail[0] != '0') {
        std.debug.print(
            "jconfig: {s}: '#cmakedefine {s}' has the unsupported value '{s}'\n",
            .{ label, name, tail },
        );
        return error.BadCmakedefine;
    }

    const value = cmake.get(name);
    if (is01) {
        const on = value != null and value.? != null;
        return std.fmt.allocPrint(arena, "#define {s} {d}", .{ name, @intFromBool(on) });
    }
    if (value) |maybe| {
        if (maybe) |v| {
            if (tail.len == 0) return std.fmt.allocPrint(arena, "#define {s}", .{name});
            return std.fmt.allocPrint(arena, "#define {s} {s}", .{ name, v });
        }
    }
    return std.fmt.allocPrint(arena, "/* #undef {s} */", .{name});
}

/// Print supplied values so failed configurations can be corrected from the diagnostic.
fn listSupplied(
    plain: std.StringHashMap([]const u8),
    cmake: std.StringHashMap(?[]const u8),
) void {
    std.debug.print("jconfig: --define values supplied: ", .{});
    var it = plain.iterator();
    var n: usize = 0;
    while (it.next()) |entry| : (n += 1) {
        std.debug.print("{s}={s}{s}", .{
            entry.key_ptr.*,
            entry.value_ptr.*,
            if (n + 1 < plain.count()) ", " else "\n",
        });
    }
    if (n == 0) std.debug.print("(none)\n", .{});

    std.debug.print("jconfig: --cmake-define/--cmake-undef values supplied: ", .{});
    var cit = cmake.iterator();
    var m: usize = 0;
    while (cit.next()) |entry| : (m += 1) {
        std.debug.print("{s}={s}{s}", .{
            entry.key_ptr.*,
            if (entry.value_ptr.*) |v| v else "UNDEF",
            if (m + 1 < cmake.count()) ", " else "\n",
        });
    }
    if (m == 0) std.debug.print("(none)\n", .{});
}
