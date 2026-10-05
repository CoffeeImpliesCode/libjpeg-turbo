// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.
//
//! Deterministic stand-in for CMake's `configure_file`, for libjpeg-turbo's
//! three configure-time headers.
//!
//! Upstream writes `jconfig.h`, `jconfigint.h` and `jversion.h` out of
//! `src/src/jconfig.h.in`, `src/src/jconfigint.h.in` and `src/src/jversion.h.in`
//! with `configure_file`:
//!
//!   * `src/CMakeLists.txt:631` - `jversion.h`;
//!   * `src/CMakeLists.txt:716` - `jconfig.h`;
//!   * `src/CMakeLists.txt:717` - `jconfigint.h`.
//!
//! `jversion.h` is not optional and not decoration. `src/src/jerror.c:27` is
//! `#include "jversion.h"`, `jerror.c` is one of the compiled library units
//! (`src/CMakeLists.txt:688`), and `JCOPYRIGHT` - the only macro
//! `jversion.h.in` adds - is what `jerror.c` prints in `error_exit()`. A build
//! that compiled the library without generating it has no library.
//!
//! `jconfigint.h` is the third input and the least obvious one. It is an
//! internal header, not an installed one (`src/CMakeLists.txt:2065-2069`
//! installs `jconfig.h`, `jerror.h`, `jmorecfg.h` and `jpeglib.h` only), but
//! `src/src/jinclude.h:26` is `#include "jconfigint.h"` and `jinclude.h` is
//! included by essentially every unit in `JPEG_SOURCES`. Two more units reach
//! it directly: `src/src/jpeg_nbits.c:9` and `src/src/jdhuff.h:20`. Generating
//! only `jconfig.h` and `jversion.h` would compile nothing at all, so this
//! generator takes a third pair of arguments.
//!
//! Every value this program is given is read out of `src/CMakeLists.txt` by
//! `build.zig` and named there with its line. Nothing here knows a libjpeg
//! version, a build string or a CPU family: this program only performs the
//! substitution, and it is the build graph that decides what the answers are.
//! That split is what keeps a configure-generated input a deterministic build
//! step rather than a second hand-written copy of the configuration
//! (`AGENTS.md` §4).
//!
//! Per-target, not per-host (`AGENTS.md` §5): the build graph runs this program
//! once per target being compiled and passes that target's `SIZEOF_SIZE_T`, so
//! a cross build never sees the generator host's word size. The generator
//! itself is compiled for `b.graph.host`; the configuration it writes is not
//! the generator's.
//!
//! It fails loudly, and that is the point. A `@VAR@` this program was not given
//! a value for is reported by name, with the template it appeared in and the
//! full list of values that *were* supplied, and the program exits non-zero
//! without writing anything. An un-substituted `@JPEG_LIB_VERSION@` reaching a
//! compile line would produce a header that fails deep inside `jmorecfg.h`
//! with an error that says nothing about the build step that caused it; a
//! `#cmakedefine` line reaching the compiler unprocessed is not C at all.
//! There is no partial output and no default value: a value this build did not
//! resolve is a defect in the build graph, not something to paper over.
//!
//! Usage:
//!   jconfig --jconfig-in PATH       --jconfig-out PATH
//!          --jversion-in PATH       --jversion-out PATH
//!          --jconfigint-in PATH     --jconfigint-out PATH
//!          [--define NAME=VALUE]...
//!          [--cmake-define NAME[=VALUE]]...
//!          [--cmake-undef NAME]...
//!
//! All three template pairs are required, not optional: one invocation writes
//! all three headers or none of them, which is what makes "no partial output"
//! above true. `parse` rejects a command line that is missing any one of the
//! six paths, and `main` renders every template before it writes any.
//!
//! `--define` supplies an `@NAME@` value. `--cmake-define` / `--cmake-undef`
//! decide a `#cmakedefine NAME 1`, `#cmakedefine NAME` or `#cmakedefine01
//! NAME` line, which CMake renders as `#define NAME <value>`, `#define NAME` or
//! `/* #undef NAME */` - and, for `#cmakedefine01`, as the value `1` or `0`.
//!
//! PENDING-VERIFICATION: this generator has never been executed. No gate has
//! been run for this package.

const std = @import("std");
const Io = std.Io;

/// The largest template this program will read. `src/src/jconfig.h.in` and its
/// two siblings are each well under 4 KiB; the limit is here so a wrong
/// `--*-in` argument naming a source file fails instead of slurping it.
const max_template_bytes = 8 * 1024 * 1024;

/// One `@NAME@` value, from `--define NAME=VALUE`.
const PlainValue = struct {
    name: []const u8,
    value: []const u8,
};

/// One `#cmakedefine` decision, from `--cmake-define` or `--cmake-undef`.
///
/// `value` is the substitution for the optional argument of
/// `#cmakedefine NAME <value>`, which CMake defaults to `1`; the templates in
/// `src/src/` always spell it `1`, and `jconfigint.h.in:60` spells the
/// value-less form.
const CmakeValue = struct {
    name: []const u8,
    /// Null means this `#cmakedefine` is undefined: CMake's `/* #undef NAME */`.
    value: ?[]const u8,
};

/// Everything one invocation was told, after parsing.
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
    /// What this template is called on the command line, for every message.
    label: []const u8,
    input: []const u8,
    output: []const u8,
};

/// Parses the command line.
///
/// Every argument is positional and explicit: there is no flag that means
/// "guess the paths", because a guessed path is a header built from the wrong
/// file and nothing downstream would say so.
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

    // Render every template before writing any of them. A run that fails half
    // way through would otherwise leave a stale header beside a fresh one, and
    // which of the two a later step reads would depend on the failure.
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
        // A duplicate is a defect in the build graph, not a last-one-wins
        // convenience: two different sources for one macro would mean the
        // resolved configuration depends on argument order.
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

/// Renders one template: CMake's `@VAR@` substitution, then its `#cmakedefine`
/// family.
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

/// Whether the identifier between two `@` characters is one CMake would
/// substitute.
///
/// CMake's own rule for an `@NAME@` is a bare identifier; anything else it
/// leaves alone. Matching that rule exactly is what keeps this program from
/// eating an `@` that upstream meant as text, such as the `@` in an email
/// address in a licence header.
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
            // An unpaired `@` is not a placeholder; CMake writes it through.
            try w.writeAll(upstream[at..]);
            break;
        };
        const name = upstream[at + 1 .. close];
        if (!isIdentifier(name)) {
            try w.writeAll(upstream[at .. close + 1]);
            i = close + 1;
            continue;
        }
        // A `#cmakedefine NAME` line is a separate mechanism and is resolved
        // below. Answering a `#cmakedefine`-only name here would invent an
        // `@NAME@` substitution upstream never wrote.
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

/// Resolves the `#cmakedefine` family, line by line.
///
/// CMake's rules, which this reproduces:
///   * `#cmakedefine NAME VALUE` with the variable set  -> `#define NAME VALUE`
///   * `#cmakedefine NAME` with the variable set          -> `#define NAME`
///   * either with the variable unset                      -> `/* #undef NAME */`
///   * `#cmakedefine01 NAME`                              -> `#define NAME 1` or
///                                                          `#define NAME 0`
///
/// A `#cmakedefine` naming a variable no `--cmake-define`/`--cmake-undef`
/// mentioned is treated as *unset*, which is CMake's own default and is not a
/// failure: `#undef` is a legitimate answer, and `jconfigint.h.in:60` spells
/// `#cmakedefine WITH_PROFILE` in exactly that form.
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

/// `arena` owns every string this returns: the macro name comes from the
/// template and the substitution from the command line, so neither is a
/// comptime value and `std.fmt.comptimePrint` cannot render them.
fn resolveCmakedefineLine(
    arena: std.mem.Allocator,
    label: []const u8,
    line: []const u8,
    cmake: std.StringHashMap(?[]const u8),
) ![]const u8 {
    const marker = "#cmakedefine";
    const hash = std.mem.indexOf(u8, line, marker) orelse return line;
    // Only a `#cmakedefine` at the start of the line, modulo leading
    // whitespace, is the directive. The marker appearing mid-line - inside a
    // comment, a string literal or prose - is text.
    // `std.mem.trim(T, slice, values_to_strip)`: the slice is the second
    // argument. Passing `" \t"` as the slice made every line look indented and
    // so return itself unchanged, which left `#cmakedefine` in the output.
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

/// Prints what *was* supplied, so the fix for a failed run is in the message
/// rather than in a re-read of `build.zig`.
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