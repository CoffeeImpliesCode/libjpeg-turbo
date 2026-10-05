// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

//! Zig facade over the libjpeg-turbo 3.2.0 C implementation.
//!
//! No part of the codec is reimplemented here. Every decoded sample, every
//! frame-header field and every compressed byte came out of the C under
//! `src/src/`, reached through `pub const c`, the module the translation step
//! produces from `zig/translate.h`. What this facade adds is the part a C
//! header cannot express: a `Decompress` that owns exactly one
//! `jpeg_decompress_struct` plus the `jpeg_error_mgr` it points at, a
//! `Compress` that owns one `jpeg_compress_struct` *and* the byte buffer
//! `jpeg_mem_dest` hands back, a row-buffer scope libjpeg does not own, an
//! output slice that is the compressed length rather than a NUL-terminated
//! pointer, and one honest error for each failure this file actually checks.
//!
//! ## Import routes
//!
//! One Zig route is published: `dep.module("libjpeg_turbo")` in the dependent's
//! `build.zig`, which is `@import("libjpeg_turbo")` in source. The translated
//! headers are `c` on that same module and are not published as a module of
//! their own, so the declarations and the library that satisfies them arrive
//! through one route. A C consumer takes the installed headers - `jconfig.h`,
//! `jmorecfg.h`, `jpeglib.h`, `jerror.h` (`src/CMakeLists.txt:2065-2069`) -
//! and the installed library instead; `README.md` names that layout.
//!
//! ```zig
//! const jpeg = @import("libjpeg_turbo");
//!
//! pub fn main() !void {
//!     var image: jpeg.Decompress = .{};
//!     defer image.deinit();
//!     try image.init(bytes_of_a_jpeg);
//!
//!     var pixels: [8 * 8]u8 = undefined;
//!     try image.readAll(&pixels);
//! }
//! ```
//!
//! ## An object has to be initialized in place
//!
//! `jpeg_CreateDecompress` records the address of the error manager it was
//! given in `cinfo->err` (`src/jpeglib.h:319`), and that address has to keep
//! being the error manager. So `Decompress.init` and `Compress.init` take a
//! `*Decompress` / `*Compress` and fill the caller's object in place rather
//! than returning one by value. A function that returned a fully built
//! `Decompress` would hand back a copy whose `err` field points into the
//! caller's temporary, and the first error would write through a dangling
//! pointer. This is the ordinary Zig rule for an object that must live at a
//! fixed address, and it is why the example above declares the variable first.
//!
//! ## Allocation, and the third-party allocator
//!
//! This module allocates nothing itself and has no allocator parameter. It
//! does not need one, and that is worth saying precisely because it is not
//! the same as "this module does no allocation".
//!
//! Everything a JPEG object allocates comes out of libjpeg-turbo's own pool
//! manager, `src/src/jmemmgr.c`, which gets its memory through the
//! system-dependent layer `src/src/jmemnobs.c`. There `jpeg_get_small` and
//! `jpeg_get_large` are `malloc` and `jpeg_free_small` and `jpeg_free_large`
//! are `free` (`src/src/jmemnobs.c:31-58`), reached through `MALLOC`. The
//! pool manager itself hands out chunks from a linked list and frees whole
//! pools rather than individual objects (`src/src/jmemmgr.c:96-99`,
//! `:1177-1183`). No Zig allocator is anywhere in that path, so a Zig test
//! allocator cannot be given a leak oracle for it: it never sees the request.
//! `jpeg_destroy_decompress` / `jpeg_destroy_compress` is what releases it,
//! and the pool manager sets `cinfo->mem = NULL` on the way out
//! (`src/src/jmemmgr.c:1183`) so it can only happen once.
//!
//! One buffer is different and the facade does own it. `jpeg_mem_dest`
//! allocates and reallocates the compressed output with plain `malloc`
//! (`src/src/jdatadst.c:143`) and hands it back through
//! `unsigned char **outbuffer` (`src/src/jdatadst.c:195`, declared
//! `src/src/jpeglib.h:988`), and upstream says in so many words that "the
//! application is responsible for freeing the requested memory"
//! (`src/src/jdatadst.c:240-244`). `Compress` holds that pointer and frees it
//! in `deinit` with the C library's own `free`, which is the only `free` that
//! can legally release a pointer this library's `malloc` returned.
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! This module is built in one of two shapes, and `runtime_loaded` says which
//! at comptime.
//!
//! *Linked* is the default. The C library is linked, `c` is the translation
//! of the four public headers, and every call below is a direct call with no
//! table and no check.
//!
//! *Runtime-loaded* is opt-in (`-Druntime`). The library is not linked; `c` is
//! a dispatch generated from the same translation step's output, and the 66
//! functions the four headers declare (`src/src/jpeglib.h`, every `EXTERN`
//! line) are resolved through the platform loader when the caller calls
//!
//! ```zig
//! try jpeg.load(.{ .path = "/usr/lib/libjpeg.so.62" });
//! ```
//!
//! before using anything else. A call into a module that has not loaded stops
//! the program with a message naming the function, in every optimization mode.
//! That is a programming error rather than a recoverable condition: the table
//! does not exist yet and there is no partial state to fall back on. The load
//! itself reports a missing file, a provider that does not export what the
//! headers declare, a request that cannot be honoured because a different
//! provider already won, or a reentrant call, as errors rather than as a
//! different library being loaded instead.
//!
//! The provider is reached, never guessed. `.path` names a file and `.system`
//! names a library for the platform loader; neither falls back to the other,
//! the module has no unload and no reset, and it keeps the handle and its own
//! copy of the request to the end of the process.
//!
//! `runtime/library.zig` states what a provider must be. libjpeg-turbo exports
//! **no version symbol** - `JPEG_LIB_VERSION` and `LIBJPEG_TURBO_VERSION` are
//! compile-time macros in the generated `jconfig.h` and never become exported
//! data - so there is no version number to compare a provider against, and
//! `runtime/library.zig` does not invent one. What it checks instead is a
//! compress/decompress exchange through the resolved table, which exercises
//! the real entry points.
//!
//! ## There is no version check, and there is a constant for the reason
//!
//! `libjpeg_api_version` is this header's `JPEG_LIB_VERSION`, so 62 in this
//! configuration. It is *not* read back from a provider and nothing in this
//! module compares it against one. It is here for a program that has to write
//! down which ABI it was compiled against, which is what upstream uses the
//! value for ("Might be useful for tests", `src/src/jconfig.h.in:1-3`).
//!
//! ## The `error_exit` boundary: upstream's does not return, so neither does
//! this module's
//!
//! `struct jpeg_error_mgr`'s first member is documented as "Error exit
//! handler: does not return to caller" (`src/src/jpeglib.h:784-785`), and
//! libjpeg's own `error_exit` formats the message, destroys the object and
//! calls `exit(EXIT_FAILURE)` (`src/src/jerror.c:66-76`). Upstream also says
//! an application that wants control back instead "would longjmp somewhere
//! (`src/src/jerror.c:57`)".
//!
//! This module does neither. It does not `exit`, because that would take the
//! Zig runtime's diagnostics, `defer`s and error return with it, and it does
//! not `longjmp`, because a longjmp skips Zig frames rather than unwinding
//! them: every `defer` between the failing call and the jump target silently
//! does not run, so a facade that jumped out would leak whatever those frames
//! held and hide it. So this module's `error_exit` does the one thing that is
//! still true of a non-returning handler in Zig: it formats the message with
//! libjpeg's own `format_message` - upstream's text, with upstream's
//! parameters - and then calls `std.debug.panic`, which stops the program and
//! prints it.
//!
//! The consequence is stated here so nobody has to discover it: **a fatal
//! libjpeg condition stops the process; it is not a Zig error.** The `Error`
//! set below is exactly the conditions this module checks itself, and nothing
//! reaches it through `error_exit`. Recoverable corrupt-data conditions do not
//! come through `error_exit` at all - upstream's `WARNMS`
//! (`src/src/jerror.h:282-284`) goes to `emit_message` instead, and this
//! module replaces `emit_message` with one that counts and keeps the first
//! message, so a truncated stream is an observable result rather than a
//! crash. See `Decompress.warningCount`.
//!
//! ## Lifetime
//!
//! `Decompress` owns one `jpeg_decompress_struct` and one `jpeg_error_mgr`,
//! and `Compress` owns one `jpeg_compress_struct`, one `jpeg_error_mgr` and
//! the compressed buffer. `deinit` destroys through the same `c` route that
//! created, so an object created by one provider is always destroyed by that
//! provider, and then clears its fields, so a second `deinit` on the same
//! variable is a no-op rather than a second destroy. Zig cannot make a struct
//! non-copyable, so the remaining rule is the usual one: copy an object before
//! `deinit` and you have two owners of one JPEG object, and only one of them
//! should destroy it.
//!
//! The compressed bytes are a different lifetime from the object. `bytes()`
//! is a borrowed slice into the buffer `jpeg_mem_dest` produced; it is valid
//! until that `Compress` is destroyed or the compressor is started again, and
//! copying it out is the only way to keep it longer.
//!
//! ## Threading
//!
//! A `jpeg_compress_struct` or `jpeg_decompress_struct` is plain mutable state
//! with no locking, so one object belongs to one thread at a time. Nothing else
//! in this module is shared, because nothing else is stateful except the
//! loader's own table, which the loader core synchronises.

const std = @import("std");

/// The translated `jconfig.h`, `jmorecfg.h`, `jpeglib.h` and `jerror.h`, i.e.
/// upstream's public ABI exactly as published.
///
/// This is the escape hatch for everything the facade does not name -
/// `jpeg_read_coefficients`, `jpeg_save_markers`, `jpeg_crop_scanline`,
/// `jpeg_calc_output_dimensions`, the 12- and 16-bit entry points, the
/// `jpeg_std_error` install itself - and for the macros the translation lowers
/// (`ERREXIT`, `WARNMS`, `TRACEMS`). It is the same module the facade calls,
/// on the same library, so importing the facade is all a dependent needs to
/// reach it; it is not published under a name of its own.
///
/// A caller who reaches past the facade gets upstream behaviour and inherits
/// every obligation upstream declares - including that `error_exit` must not
/// return. Installing your own handler means taking over that boundary
/// yourself.
pub const c = @import("c");

/// The loader core, which is where a linked build's two public types come
/// from.
///
/// It is imported only by the linked configuration. In a runtime-loading build
/// the dispatch carries its own copy of the same declarations and this module
/// is never referenced, so it is never resolved and never compiled. Either way
/// there is exactly one `LoadSource` and one `LoadError` in a build.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the C library is linked and `c` is the
/// translation of the four public headers. True when the build generated a
/// dispatch that resolves the same symbols through the platform loader, in
/// which case `load` is the call that makes the library usable.
///
/// It is a comptime constant, so a consumer can write two different code paths
/// and have only the one it chose analyzed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader. There is no path-to-system fallback and no implicit
/// fallback of any kind; a request that cannot be honoured is an error, not a
/// different library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside the
/// loader: the caller names the failure it is handling.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then
/// use this module as if it were linked. Calling it again with the same request
/// succeeds and changes nothing; calling it with a different request after a
/// success is `ProviderMismatch`, and the library already in use stays in use.
/// A failed attempt publishes nothing and can be retried explicitly, by
/// calling this again: there is no automatic retry and no implicit second
/// source.
///
/// It keeps the process handle and its own copy of the request to the end of
/// the process. There is no unload and no reset, because the table is
/// process-global state that other code may already have called through.
///
/// Safe to call from any thread. A thread that arrives while an attempt for
/// the same request is in flight waits for that attempt and gets its result,
/// whatever it was. A call from the thread that is running the attempt is
/// `ReentrantLoad` rather than a deadlock.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly
/// succeeding. `runtime_loaded` is false there, so a consumer that supports
/// both configurations can tell the two apart at comptime.
pub fn load(source: LoadSource) LoadError!void {
    // `c.load` exists only in a runtime-loading build. The condition is known
    // at comptime, so the branch this build does not take is never analyzed
    // and never names it.
    if (runtime_loaded) return c.load(source);
    std.debug.panic(
        "libjpeg_turbo: load was called on a linked build; this module is not " ++
            "runtime-loaded, so there is no library to load. Build with " ++
            "runtime loading configured, or do not call load.",
        .{},
    );
}

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (runtime_loaded) return c.loadedSource();
    return null;
}

/// This header's `JPEG_LIB_VERSION`, so 62 in this configuration.
///
/// It is a compile-time constant of the *translated headers*, not a fact read
/// back from a loaded provider: libjpeg-turbo exports no version symbol. Use it
/// to record which ABI a program was compiled against; do not use it to accept
/// or reject a provider.
pub const libjpeg_api_version: c_int = c.JPEG_LIB_VERSION;

/// The longest message `format_message` will write, which is the size of the
/// buffer `error_exit` hands it (`src/src/jpeglib.h:792`).
pub const message_length_max: usize = c.JMSG_LENGTH_MAX;

/// A colorspace, upstream's `J_COLOR_SPACE` (`src/src/jpeglib.h:264-290`).
///
/// The values are read through `c` rather than restated, so an upstream rename
/// cannot silently disagree here. `JCS_UNKNOWN` is not a colorspace: it is the
/// value libjpeg itself leaves in `jpeg_decompress_struct.out_color_space`
/// after `jpeg_read_header`, meaning "pick the default for me"
/// (`src/src/jpeglib.h:542`, and the field's own comment says these "must be
/// set before calling jpeg_start_decompress"). This module passes that
/// sentinel through unchanged rather than choosing a replacement for it.
pub const ColorSpace = enum(c_int) {
    unknown = c.JCS_UNKNOWN,
    grayscale = c.JCS_GRAYSCALE,
    rgb = c.JCS_RGB,
    ycbcr = c.JCS_YCbCr,
    cmyk = c.JCS_CMYK,
    ycck = c.JCS_YCCK,
    ext_rgb = c.JCS_EXT_RGB,
    ext_rgbx = c.JCS_EXT_RGBX,
    ext_bgr = c.JCS_EXT_BGR,
    ext_bgrx = c.JCS_EXT_BGRX,
    ext_xbgr = c.JCS_EXT_XBGR,
    ext_xrgb = c.JCS_EXT_XRGB,
    ext_rgba = c.JCS_EXT_RGBA,
    ext_bgra = c.JCS_EXT_BGRA,
    ext_abgr = c.JCS_EXT_ABGR,
    ext_argb = c.JCS_EXT_ARGB,
    /// Decompression only (`src/src/jpeglib.h:288-289`).
    rgb565 = c.JCS_RGB565,
};

/// The inverse DCT to use, upstream's `J_DCT_METHOD`
/// (`src/src/jpeglib.h:294-298`).
///
/// `islow` is upstream's default: `JDCT_DEFAULT` is `JDCT_ISLOW`
/// (`src/src/jpeglib.h:300-302`), and `jpeg_read_header` initialises
/// `dct_method` to it.
pub const DctMethod = enum(c_int) {
    islow = c.JDCT_ISLOW,
    ifast = c.JDCT_IFAST,
    float = c.JDCT_FLOAT,
};

/// What `jpeg_read_header` found, its three documented return values
/// (`src/src/jpeglib.h:1064-1067`).
pub const HeaderResult = enum(c_int) {
    /// `JPEG_SUSPENDED`. Only reachable with a suspending source, which
    /// `jpeg_mem_src` is not.
    suspended = c.JPEG_SUSPENDED,
    /// `JPEG_HEADER_OK`: a complete image datastream.
    header_ok = c.JPEG_HEADER_OK,
    /// `JPEG_HEADER_TABLES_ONLY`: tables with no image. Passing
    /// `require_image = TRUE`, which this module always does, makes upstream
    /// raise an error instead (`src/src/jpeglib.h:1068-1069`).
    tables_only = c.JPEG_HEADER_TABLES_ONLY,
};

/// Every way a typed call in this module can fail.
///
/// One tag per condition this file actually checks, and nothing else. The
/// vocabulary is deliberately short: it is not libjpeg's message-code
/// namespace (`src/src/jerror.h:45-223`), because those codes are not returned
/// to a caller - they go to `error_exit`, which does not return. See the module
/// comment on that boundary.
///
///   * `NotAJpegImage` - `jpeg_read_header` answered something other than
///     `JPEG_HEADER_OK` (`src/src/jpeglib.h:1063-1067`).
///   * `NotDecompressing` - `jpeg_start_decompress` returned `FALSE`
///     (`src/src/jpeglib.h:1075`). Its counterpart on the compression side
///     does not exist: `jpeg_start_compress` returns `void`
///     (`src/src/jpeglib.h:1020-1021`), so there is no answer to check and a
///     tag for it would name a failure nothing can return.
///   * `PrematureEnd` - `jpeg_read_scanlines` returned zero rows before the
///     output height was reached (`src/src/jpeglib.h:1076-1078`).
///   * `ShortWrite` - `jpeg_write_scanlines` returned fewer rows than it was
///     given. With the memory destination this module installs, upstream
///     cannot suspend, so a short count would mean upstream misbehaved; the
///     check is here so that assumption is tested rather than assumed.
///   * `RowBufferTooSmall` - the slice handed to `readScanlines` /
///     `writeScanlines` cannot hold the rows it was offered.
pub const Error = error{
    NotAJpegImage,
    NotDecompressing,
    PrematureEnd,
    ShortWrite,
    RowBufferTooSmall,
};

/// The one `free` in this module.
///
/// The compressed buffer `jpeg_mem_dest` produces is a `malloc` pointer
/// (`src/src/jdatadst.c:143`) and upstream requires the application to free it
/// (`src/src/jdatadst.c:240-244`). It is declared here rather than reached
/// through `c` because `zig/translate.h` opens `<stddef.h>` and `<stdio.h>`
/// (`src/src/jpeglib.h:21-29` needs `FILE` and `size_t`) and neither declares
/// `free`; adding `<stdlib.h>` would drag the whole `stdlib` surface into every
/// runtime-loading dispatch's classification for one symbol.
///
/// Declaring an `extern` does not make it libjpeg-turbo's: this one resolves
/// against the C library, which is linked, and is not part of the dispatch
/// table.
extern fn free(ptr: ?*anyopaque) void;

/// What this module's `error_exit` does.
///
/// It must not return: `src/src/jpeglib.h:784` says the handler "does not
/// return to caller", and every `ERREXIT*` macro in `src/src/jerror.h:239-277`
/// is written as though nothing follows it. So it formats the message with
/// libjpeg's own `format_message` and then stops the program with it. See the
/// module comment for why this is a panic and not an `exit` and not a
/// `longjmp`.
fn errorExit(cinfo: ?*c.jpeg_common_struct) callconv(.c) noreturn {
    var buffer: [message_length_max]u8 = undefined;
    buffer[0] = 0;
    if (cinfo) |info| {
        if (info.err) |err| {
            // `format_message` is upstream's, called through this build's
            // translation, with this build's own `JMSG_LENGTH_MAX` buffer. It
            // NUL-terminates (`src/src/jerror.c:147-150`). `err` is
            // `[*c]jpeg_error_mgr`, so the field is reached through one
            // dereference, and the field itself is an optional function
            // pointer that `jpeg_std_error` has just filled in.
            err.*.format_message.?(info, &buffer);
        }
    }
    std.debug.panic("libjpeg_turbo: {s}", .{std.mem.span(@as([*:0]u8, @ptrCast(&buffer)))});
}

/// This module's `emit_message`: counts a warning and keeps its text.
///
/// Upstream's own handler shows only the first warning and counts them all
/// (`src/src/jerror.c:129-137`). This one prints nothing, because a library
/// that writes to stderr is not a library a test can read a result from; it
/// keeps the same count in the same field and keeps the first message so
/// `Decompress.lastWarning` can return it.
///
/// `cinfo->client_data` is the caller's own scratch space
/// (`src/src/jpeglib.h:322`) and this module uses it to reach that buffer.
fn emitMessage(cinfo: ?*c.jpeg_common_struct, msg_level: c_int) callconv(.c) void {
    // msg_level >= 0 is a trace message; upstream's policy is to show it when
    // `trace_level` allows, and this module leaves `trace_level` at the zero
    // `jpeg_std_error` set, so no trace message is ever shown.
    if (msg_level >= 0) return;
    const info = cinfo orelse return;
    const err = info.err orelse return;

    var buffer: [message_length_max]u8 = undefined;
    buffer[0] = 0;
    err.*.format_message.?(info, &buffer);
    const text = std.mem.span(@as([*:0]u8, @ptrCast(&buffer)));

    // The first warning is the one kept, matching upstream's "show only the
    // first" (src/src/jerror.c:131-134).
    if (err.*.num_warnings == 0) {
        if (info.client_data) |scratch| {
            const slot: *WarningSlot = @ptrCast(@alignCast(scratch));
            const room = @min(text.len, slot.text.len);
            @memcpy(slot.text[0..room], text[0..room]);
            slot.len = room;
        }
    }
    // "Always count warnings in num_warnings" (src/src/jerror.c:136).
    err.*.num_warnings += 1;
}

/// Where `emitMessage` leaves the first warning's text.
///
/// Not part of the public surface: `Decompress` owns one of these and hands its
/// address to libjpeg as `client_data`.
const WarningSlot = struct {
    text: [message_length_max]u8 = undefined,
    len: usize = 0,
};

/// Install this module's handlers on `err`, through upstream's own
/// `jpeg_std_error`.
///
/// `jpeg_std_error` fills in `output_message`, `format_message` and
/// `reset_error_mgr` and points `error_exit` and `emit_message` at libjpeg's
/// own (`src/src/jerror.c:227-239`). This module then replaces the two it must
/// replace and leaves the three alone, which is what upstream documents
/// applications as doing (`src/src/jerror.c:220-225`).
fn installHandlers(err: *c.jpeg_error_mgr) void {
    _ = c.jpeg_std_error(err);
    err.error_exit = errorExit;
    err.emit_message = emitMessage;
}

/// One JPEG decompressor: the struct, the error manager it points at, and
/// nothing else.
pub const Decompress = struct {
    /// Upstream's master record, owned by this object.
    ///
    /// `jpeg_CreateDecompress` takes a `j_decompress_ptr`
    /// (`src/src/jpeglib.h:976`), which `src/src/jpeglib.h:340` defines as
    /// `struct jpeg_decompress_struct *`: the application allocates the master
    /// record and hands its address over. Upstream's own `src/src/example.c`
    /// does both ways - a stack `struct jpeg_compress_struct cinfo` at `:103`
    /// with `jpeg_create_compress(&cinfo)` at `:134`, and a
    /// `struct jpeg_decompress_struct *cinfo` parameter at `:352` with
    /// `jpeg_create_decompress(cinfo)` at `:431`. Holding the record here is
    /// what gives `raw` a fixed address - the whole reason `init` fills the
    /// caller's object in place - and it is what lets `deinit` release
    /// everything without an allocator.
    storage: c.jpeg_decompress_struct = undefined,

    /// The address `init` handed to libjpeg-turbo: `&storage` while the object
    /// is open, null before `init` and null again once `deinit` has run.
    raw: ?*c.jpeg_decompress_struct = null,
    err: c.jpeg_error_mgr = undefined,
    warning_slot: WarningSlot = .{},

    /// The decompressor `init` creates, for anything the facade does not wrap.
    pub const Raw = *c.jpeg_decompress_struct;

    /// Point this object at a JPEG datastream and read its frame header.
    ///
    /// `bytes` is borrowed for the life of this object: `jpeg_mem_src` stores
    /// the pointer and the length in the source manager
    /// (`src/src/jdatasrc.c:287-288`) and reads from it for as long as the
    /// object lives. Nothing is copied, so a caller that frees or mutates the
    /// buffer must call `deinit` first.
    ///
    /// Empty input is upstream's own fatal condition - `jpeg_mem_src` raises
    /// `JERR_INPUT_EMPTY` for a null buffer or a zero length
    /// (`src/src/jdatasrc.c:263-264`) - so it reaches `error_exit` and stops
    /// the process rather than returning an error here. That is upstream's
    /// decision about its own argument, and this module does not pre-empt it
    /// with a check of its own.
    pub fn init(self: *Decompress, bytes: []const u8) Error!void {
        // libjpeg-turbo exports no version symbol, so there is nothing to read
        // back and compare. What can be checked is the struct size, and
        // upstream does that itself: `jpeg_CreateDecompress` refuses a
        // `structsize` that is not `sizeof(struct jpeg_decompress_struct)`
        // (`src/src/jdapimin.c:47-49`). Passing `@sizeOf` of this
        // translation's struct is the documented macro's own argument
        // (`src/src/jpeglib.h:971-973`), not a re-derivation of anything
        // upstream defines.
        if (self.raw != null) @panic(
            "libjpeg_turbo: this Decompress is already open. A second init " ++
                "would replace the error-manager pointer the existing object " ++
                "holds, so create one object per decode instead.",
        );

        installHandlers(&self.err);

        // The address is fixed before the call because it must not move
        // afterwards; see the module comment on initializing in place.
        self.raw = &self.storage;

        // Upstream requires the error manager to be in place *before* the
        // object is created - `src/src/jpeglib.h:966` says so in as many words
        // ("NB: you must set up the error-manager BEFORE calling
        // jpeg_create_xxx"), and `src/src/jdapimin.c:44-46` already writes
        // `cinfo->mem` and can raise a version error before anything else.
        // `jpeg_CreateDecompress` then zeroes the record it was handed
        // (`src/src/jdapimin.c:60`) and restores `err` and `client_data`
        // (`:58-62`), which is why these two are set before the call rather
        // than after it.
        self.raw.?.err = &self.err;

        // `client_data` is documented as the application's own field
        // (`src/src/jpeglib.h:322`); it is how `emit_message` reaches the
        // warning text.
        self.raw.?.client_data = @ptrCast(&self.warning_slot);

        c.jpeg_CreateDecompress(
            self.raw,
            libjpeg_api_version,
            @sizeOf(c.jpeg_decompress_struct),
        );

        c.jpeg_mem_src(
            self.raw,
            bytes.ptr,
            @intCast(bytes.len),
        );

        // `require_image = TRUE` (1) is upstream's documented normal case: with
        // it, "an abbreviated file will cause an error exit" and the caller
        // need not check for `JPEG_HEADER_TABLES_ONLY`
        // (`src/src/jpeglib.h:1068-1071`). The return is still read, because it
        // is the documented way to tell the three cases apart
        // (`src/src/jpeglib.h:1064-1067`).
        const result: HeaderResult = @enumFromInt(c.jpeg_read_header(self.raw, 1));
        if (result != .header_ok) return error.NotAJpegImage;
    }

    /// Destroy the decompressor and everything libjpeg-turbo allocated for it.
    ///
    /// The destroy goes through the same `c` route that created the object, so
    /// a decompressor created by one provider is always destroyed by that
    /// provider. It releases the pool manager's memory
    /// (`src/src/jmemmgr.c:1168-1185`) and the source manager, and the pool
    /// manager clears `cinfo->mem` as it goes so it can only happen once.
    ///
    /// The field is cleared afterwards, which makes a second `deinit` on the
    /// same variable a no-op instead of a second destroy.
    pub fn deinit(self: *Decompress) void {
        const raw = self.raw orelse return;
        self.raw = null;
        c.jpeg_destroy_decompress(raw);
    }

    /// Whether this object has a live decompressor.
    pub fn isOpen(self: *const Decompress) bool {
        return self.raw != null;
    }

    /// The decompressor itself, for anything the facade does not wrap.
    ///
    /// Stopping the program on a closed object is deliberate: calling into a
    /// destroyed `jpeg_decompress_struct` is not a condition to recover from,
    /// and the field is null precisely so that this is caught at the call
    /// rather than inside the C library.
    pub fn handle(self: *const Decompress) Raw {
        return self.raw orelse @panic(
            "libjpeg_turbo: this Decompress is not open; call init() first, " ++
                "or do not use it after deinit().",
        );
    }

    /// The nominal image width, from the SOF marker
    /// (`src/src/jpeglib.h:532`).
    ///
    /// Read through the master record rather than cached: `jpeg_read_header`
    /// filled it in, and nothing here re-derives it.
    pub fn width(self: *const Decompress) u32 {
        return self.handle().image_width;
    }

    /// The nominal image height, from the SOF marker
    /// (`src/src/jpeglib.h:533`).
    pub fn height(self: *const Decompress) u32 {
        return self.handle().image_height;
    }

    /// How many components the JPEG image itself has, which is what the SOF
    /// marker says (`src/src/jpeglib.h:534`).
    ///
    /// This is not how many components come back. A greyscale JPEG has one
    /// here and can be asked for three on the way out; `outputComponents` is
    /// that answer, and it is only known after `startDecompress`.
    pub fn numComponents(self: *const Decompress) i32 {
        return self.handle().num_components;
    }

    /// The colorspace the JPEG file's own component data is in, as libjpeg
    /// classified it (`src/src/jpeglib.h:535`).
    pub fn jpegColorSpace(self: *const Decompress) ColorSpace {
        return @enumFromInt(self.handle().jpeg_color_space);
    }

    /// The requested output colorspace, exactly as it stands.
    ///
    /// Right after `init` this is whatever `jpeg_read_header` put there, which
    /// is libjpeg's own choice and may be `JCS_UNKNOWN` - upstream's "no
    /// preference" sentinel, on a field it documents as a decompression
    /// parameter the application sets (`src/src/jpeglib.h:537-542`). This
    /// module does not substitute a default for it: use `requestOutColorSpace`
    /// to set one deliberately, or leave it and let `startDecompress` resolve
    /// it, after which this reports what libjpeg decided.
    pub fn outColorSpace(self: *const Decompress) ColorSpace {
        return @enumFromInt(self.handle().out_color_space);
    }

    /// Ask for a particular output colorspace.
    ///
    /// This writes `out_color_space` through the pointer the caller holds, which
    /// is the field libjpeg documents as one that "must be set before calling
    /// `jpeg_start_decompress`" (`src/src/jpeglib.h:537-542`). Passing
    /// `.unknown` passes upstream's sentinel back unchanged.
    ///
    /// A colorspace libjpeg cannot produce for this image is not reported here:
    /// `src/src/jdcolor.c:688-689` and `:717-718` decide that during startup
    /// and raise an error, which reaches `error_exit`. That is upstream's check
    /// on its own parameters, and duplicating it here would mean keeping a
    /// second copy of libjpeg's colorspace tables that could disagree with the
    /// ones being compiled.
    pub fn requestOutColorSpace(self: *Decompress, space: ColorSpace) void {
        self.handle().out_color_space = @intCast(@intFromEnum(space));
    }

    /// Choose the inverse DCT (`src/src/jpeglib.h:551`).
    ///
    /// `jpeg_read_header` has initialised this to `JDCT_ISLOW`
    /// (`src/src/jpeglib.h:300-302`), and this module does not change that
    /// default.
    pub fn requestDctMethod(self: *Decompress, method: DctMethod) void {
        self.handle().dct_method = @intFromEnum(method);
    }

    /// Begin decoding, after which the output dimensions and the component
    /// count are known.
    ///
    /// Upstream computes `output_width`, `output_height` and
    /// `output_components` in this call (`src/src/jpeglib.h:565-582`), so this
    /// is the earliest point at which `rowBytes` is meaningful.
    pub fn startDecompress(self: *Decompress) Error!void {
        if (c.jpeg_start_decompress(self.handle()) == 0) return error.NotDecompressing;
    }

    /// The decoded width, which can differ from `width` once a scale factor is
    /// set (`src/src/jpeglib.h:571`).
    pub fn outputWidth(self: *const Decompress) u32 {
        return self.handle().output_width;
    }

    /// The decoded height (`src/src/jpeglib.h:572`).
    pub fn outputHeight(self: *const Decompress) u32 {
        return self.handle().output_height;
    }

    /// How many components `out_color_space` has, as libjpeg computed it
    /// (`src/src/jpeglib.h:573`).
    pub fn outColorComponents(self: *const Decompress) i32 {
        return self.handle().out_color_components;
    }

    /// How many components each returned row carries
    /// (`src/src/jpeglib.h:574`).
    ///
    /// This equals `outColorComponents` unless colors are being quantized to a
    /// colormap, where upstream documents it as 1 - a colormap index rather
    /// than a color (`src/src/jpeglib.h:575-577`).
    pub fn outputComponents(self: *const Decompress) i32 {
        return self.handle().output_components;
    }

    /// The recommended minimum number of rows to hand libjpeg at once
    /// (`src/src/jpeglib.h:578-582`).
    ///
    /// A buffer shorter than this is not wrong, only wasteful: upstream says
    /// "space and time will be wasted due to unnecessary data copying". This
    /// module does not enforce it.
    pub fn recommendedRowBufferHeight(self: *const Decompress) i32 {
        return self.handle().rec_outbuf_height;
    }

    /// The number of bytes in one row of decoded output: the output width times
    /// the components per row.
    ///
    /// `JSAMPLE` is `unsigned char` (`src/src/jmorecfg.h:49`) and one pixel is
    /// `output_components` of them, so this is the row stride libjpeg writes
    /// through - the length contract `readScanlines` enforces.
    pub fn rowBytes(self: *const Decompress) usize {
        const raw = self.handle();
        return @as(usize, raw.output_width) * @as(usize, @intCast(raw.output_components));
    }

    /// The next row libjpeg will write, counted from zero
    /// (`src/src/jpeglib.h:601-605`).
    pub fn outputScanline(self: *const Decompress) u32 {
        return self.handle().output_scanline;
    }

    /// Decode into `out`, one or more whole rows.
    ///
    /// `out` must be at least `rowBytes` long; the whole slice is offered and
    /// libjpeg writes through it. How many rows that is depends on the image,
    /// so the answer is the row count upstream produced
    /// (`src/src/jpeglib.h:1076-1078`), not a length this module derived.
    ///
    /// Returning fewer rows than were offered is how upstream reports that it
    /// is done, and returning zero before the last row has arrived is
    /// `PrematureEnd`. From a truncated stream that happens only after
    /// libjpeg's own warning about it - see `warningCount`.
    pub fn readScanlines(self: *Decompress, out: []u8) Error!usize {
        const stride = self.rowBytes();
        if (stride == 0 or out.len < stride) return error.RowBufferTooSmall;
        const rows = out.len / stride;

        // `scanlines` is a `JSAMPARRAY`: an array with one row pointer **per
        // row** (`src/src/jpeglib.h:89-92`), and upstream reads
        // `scanlines[i]` for every `i < num_lines`. A one-element array
        // described as holding several rows therefore reads past its own
        // bounds, which is how this ended up segfaulting in `jccolor.c`.
        //
        // One row per call is upstream's own idiom - `src/src/example.c`
        // declares `JSAMPROW row_pointer[1]` and passes 1 - and it keeps this
        // method's stack use constant instead of proportional to the caller's
        // slice. The rows are contiguous, so each call points one stride
        // further into the caller's buffer.
        var read: usize = 0;
        while (read < rows) {
            var one: [1]c.JSAMPROW = .{out.ptr + read * stride};
            const got = c.jpeg_read_scanlines(self.handle(), &one, 1);
            if (got == 0) break;
            read += got;
        }
        if (read == 0) return error.PrematureEnd;
        return read;
    }

    /// Decode the rest of the image into `buffer`, which must hold the whole
    /// decoded image: `rowBytes() * outputHeight()` bytes, rows in order.
    ///
    /// This is `readScanlines` in a loop and adds nothing to it. It is here
    /// because "give me the image" is what most callers want, and because the
    /// row-at-a-time call above stays available for the callers that want the
    /// pixels somewhere other than one contiguous slice.
    pub fn readAll(self: *Decompress, buffer: []u8) Error!void {
        const stride = self.rowBytes();
        const needed = stride * @as(usize, self.outputHeight());
        if (buffer.len < needed) return error.RowBufferTooSmall;
        var offset: usize = 0;
        while (offset < needed) {
            const read = try self.readScanlines(buffer[offset..needed]);
            offset += read * stride;
        }
    }

    /// Finish decoding, which upstream expects before the object is destroyed
    /// (`src/src/jpeglib.h:1093`).
    pub fn finishDecompress(self: *Decompress) void {
        _ = c.jpeg_finish_decompress(self.handle());
    }

    /// How many recoverable corrupt-data warnings this decode has produced.
    ///
    /// `num_warnings` is upstream's own field under upstream's own counting
    /// rule - "Always count warnings in num_warnings"
    /// (`src/src/jerror.c:136`). A non-zero count after decoding means the
    /// input was damaged and libjpeg continued anyway, which is what makes it
    /// worth reporting rather than only stopping for.
    pub fn warningCount(self: *const Decompress) c_long {
        const raw = self.raw orelse return 0;
        const err = raw.err orelse return 0;
        return err.*.num_warnings;
    }

    /// The text of the first warning, or null when there has been none.
    ///
    /// This is libjpeg's own message, formatted by libjpeg's own
    /// `format_message`; the copy into this object is the only copy.
    pub fn lastWarning(self: *const Decompress) ?[]const u8 {
        if (self.warning_slot.len == 0) return null;
        return self.warning_slot.text[0..self.warning_slot.len];
    }
};

/// One JPEG compressor: the struct, the error manager it points at, and the
/// compressed buffer libjpeg-turbo produced into.
///
/// The buffer is the reason this type exists rather than a bare struct. The
/// memory destination hands back a `malloc` pointer through an
/// `unsigned char **` (`src/src/jdatadst.c:195`, `src/src/jpeglib.h:988`) and
/// upstream says the application is responsible for freeing it
/// (`src/src/jdatadst.c:240-244`). So `Compress` holds it, and `deinit`
/// releases it with the C library's own `free` - the only `free` that can
/// legally release a pointer this library's `malloc` returned.
///
/// `init` fills this object in place rather than returning one, for the reason
/// the module comment gives: `cinfo->err` is a pointer into the object.
pub const Compress = struct {
    /// Upstream's master record, owned by this object, for the reason
    /// `Decompress.storage` gives: `jpeg_CreateCompress` takes a
    /// `j_compress_ptr` (`src/src/jpeglib.h:974`), which
    /// `src/src/jpeglib.h:339` defines as `struct jpeg_compress_struct *`, so
    /// the application allocates it and passes its address.
    storage: c.jpeg_compress_struct = undefined,

    /// The address `init` handed to libjpeg-turbo: `&storage` while the object
    /// is open, null before `init` and null again once `deinit` has run.
    raw: ?*c.jpeg_compress_struct = null,
    err: c.jpeg_error_mgr = undefined,
    warning_slot: WarningSlot = .{},

    /// `*outbuffer`, as `jpeg_mem_dest` and `term_mem_destination` last wrote
    /// it (`src/src/jdatadst.c:283`, `:195`).
    ///
    /// This is a plain `[*c]u8`, the shape of upstream's `unsigned char *`.
    /// It is deliberately not `?[*c]u8`: a C pointer already carries null, so
    /// the double-optional has no niche to share with it and is a wider type
    /// than the eight bytes `jpeg_mem_dest` writes through `unsigned char **`.
    /// It read back null over a live pointer, which made `bytes` report an
    /// empty result for a finished compression.
    out_buffer: [*c]u8 = null,
    /// `*outsize`: the number of bytes of compressed data, which is the
    /// allocated length minus what is still free (`src/src/jdatadst.c:196`).
    ///
    /// This is the compressed length, not the buffer's capacity: the buffer
    /// doubles when it fills (`src/src/jdatadst.c:130-158`), so it is usually
    /// larger than the file.
    out_size: c_ulong = 0,

    /// Whether `finishCompress` has run.
    ///
    /// `jpeg_mem_dest` allocates the destination and sets `*outsize` to its
    /// **capacity** the moment it is called (`src/src/jdatadst.c:281-287`,
    /// `OUTPUT_BUF_SIZE`); only `term_mem_destination` writes the real
    /// compressed length back through `outsize` (`src/src/jdatadst.c:196`). So
    /// before the compressor has been finished, `out_size` is not a length,
    /// and `bytes` reports nothing rather than a capacity's worth of bytes
    /// that are not image data yet.
    finished: bool = false,

    /// The compressor `init` creates, for anything the facade does not wrap.
    pub const Raw = *c.jpeg_compress_struct;

    /// Create a compressor for a `width` by `height` image of `components`
    /// components, with the compressed output going to memory.
    ///
    /// This creates the object and installs the memory destination. The image
    /// description still has to be given, and upstream requires
    /// `in_color_space` to be correct "before you can even call
    /// jpeg_set_defaults()" (`src/src/jpeglib.h:351-359`). So the order is
    /// `init`, then `setInputColorSpace`, then `setDefaults`.
    ///
    /// `jpeg_mem_dest` is available unconditionally because
    /// `MEM_SRCDST_SUPPORTED` is a plain `#define`, not a `#cmakedefine`
    /// (`src/src/jconfig.h.in:18-19`).
    pub fn init(self: *Compress, width: u32, height: u32, components: i32) void {
        if (self.raw != null) @panic(
            "libjpeg_turbo: this Compress is already open. A second init would " ++
                "replace the error-manager pointer the existing object holds, " ++
                "so create one object per image instead.",
        );

        installHandlers(&self.err);

        // The address is fixed before the call because it must not move
        // afterwards; see the module comment on initializing in place.
        self.raw = &self.storage;

        // Before the call, for the reason `Decompress.init` gives:
        // `src/src/jpeglib.h:966` requires the error manager first, and
        // `src/src/jcapimin.c:59-62` zeroes the record and restores `err` and
        // `client_data` around it.
        self.raw.?.err = &self.err;
        self.raw.?.client_data = @ptrCast(&self.warning_slot);

        c.jpeg_CreateCompress(
            self.raw,
            libjpeg_api_version,
            @sizeOf(c.jpeg_compress_struct),
        );

        self.raw.?.image_width = width;
        self.raw.?.image_height = height;
        self.raw.?.input_components = components;

        // `outbuffer` and `outsize` are the two pointers upstream writes
        // through when the destination is set up and when it is terminated
        // (`src/src/jdatadst.c:283`, `:286`, `:195-196`). They point at this
        // object's own fields, which is a second reason this object cannot be
        // moved after `init`.
        c.jpeg_mem_dest(self.raw, &self.out_buffer, &self.out_size);
    }

    /// Destroy the compressor and release the compressed buffer.
    ///
    /// Two things are released and they come from two different allocators.
    /// The pool manager's memory goes with `jpeg_destroy_compress`
    /// (`src/src/jmemmgr.c:1168-1185`); the compressed buffer is a plain
    /// `malloc` result (`src/src/jdatadst.c:143`) and is freed here with the C
    /// library's `free`, which is what upstream's "the application is
    /// responsible for freeing the requested memory"
    /// (`src/src/jdatadst.c:242-243`) asks for. Upstream explicitly does *not*
    /// free it on abort or destroy - its own comment on `term_destination` says
    /// "surrounding application must deal with any cleanup"
    /// (`src/src/jdatadst.c:167-170`).
    ///
    /// Both pointers are cleared afterwards, so a second `deinit` on the same
    /// variable is a no-op rather than a second free.
    pub fn deinit(self: *Compress) void {
        const buffer = self.out_buffer;
        const raw = self.raw orelse return;
        self.out_buffer = null;
        self.raw = null;
        c.jpeg_destroy_compress(raw);
        // Upstream hands the pointer over and says the application owns it
        // (`src/src/jpeglib.h:988`, `src/src/jdatadst.c:240-244`). A non-null
        // `outbuffer` is therefore always this library's `malloc` result and
        // always goes back to it. There is no length test to make first: a
        // zero-length compressed stream is still an allocated buffer, and
        // `[*c]u8` has no length of its own to ask for - `std.mem.len` would
        // scan for a terminator, and `bytes` documents that there is none.
        if (buffer) |owned| {
            free(@constCast(owned));
        }
    }

    /// Whether this object has a live compressor.
    pub fn isOpen(self: *const Compress) bool {
        return self.raw != null;
    }

    /// The compressor itself, for anything the facade does not wrap.
    ///
    /// Stopping the program on a closed object is deliberate, for the reason
    /// `Decompress.handle` gives.
    pub fn handle(self: *const Compress) Raw {
        return self.raw orelse @panic(
            "libjpeg_turbo: this Compress is not open; call init() first, " ++
                "or do not use it after deinit().",
        );
    }

    /// Tell upstream what colorspace the pixels the caller supplies are in.
    ///
    /// `src/src/jpeglib.h:359`; this must be right before `setDefaults`.
    pub fn setInputColorSpace(self: *Compress, space: ColorSpace) void {
        // `J_COLOR_SPACE` is `c_uint` upstream (`src/src/jpeglib.h:104`), so
        // the tag value needs a widening cast rather than an implicit one.
        self.handle().in_color_space = @intCast(@intFromEnum(space));
    }

    /// Apply libjpeg's default compression parameters for the current image.
    ///
    /// `src/src/jpeglib.h:994`. Upstream requires `in_color_space` to be set
    /// first (`src/src/jpeglib.h:353`), which is why this is not folded into
    /// `init`.
    pub fn setDefaults(self: *Compress) void {
        c.jpeg_set_defaults(self.handle());
    }

    /// Set the quality, 1 to 100.
    ///
    /// `src/src/jpeglib.h:999-1000`. `force_baseline` is upstream's request to
    /// emit a strictly conformant baseline stream even if that costs
    /// compression; this module passes what the caller asked for rather than
    /// silently restricting anything.
    pub fn setQuality(self: *Compress, quality: i32, force_baseline: bool) void {
        c.jpeg_set_quality(self.handle(), quality, if (force_baseline) 1 else 0);
    }

    /// The compressed data, as a borrowed slice of exactly the compressed
    /// length.
    ///
    /// Valid from `finishCompress` until this object is destroyed or another
    /// image is started on it. The slice's length is `*outsize`
    /// (`src/src/jdatadst.c:196`), not the buffer's capacity, and a JPEG file
    /// contains no terminator, so reading this buffer as a C string would be
    /// wrong.
    pub fn bytes(self: *const Compress) []const u8 {
        if (!self.finished) return &.{};
        const buffer = self.out_buffer;
        if (buffer == null) return &.{};
        return @as([*]const u8, buffer)[0..@intCast(self.out_size)];
    }

    /// Begin compression.
    ///
    /// Upstream's `jpeg_start_compress` returns `void`
    /// (`src/src/jpeglib.h:1020-1021`), so there is no boolean to check and
    /// this function reports nothing: unusable parameters raise an error
    /// inside libjpeg, which reaches `error_exit`. `write_all_tables` is `FALSE`
    /// here, upstream's default behaviour of not re-emitting the standard
    /// tables (`src/src/jpeglib.h:1019-1021`); a caller that wants them all
    /// calls the raw `jpeg_start_compress` through `handle`.
    pub fn startCompress(self: *Compress) void {
        c.jpeg_start_compress(self.handle(), 0);
    }

    /// Hand `rows` of samples to the compressor.
    ///
    /// `rows` must be a whole number of rows of `image_width` pixels with
    /// `input_components` samples each. They are read, not written: upstream
    /// reads through the pointers in the `JSAMPARRAY` it is given
    /// (`src/src/jpeglib.h:89-92`, `:1022-1024`).
    ///
    /// The returned count is upstream's own. With the memory destination there
    /// is no suspension, so upstream either takes every row offered or has
    /// failed; a short count means it did, and this module reports that rather
    /// than assuming it cannot happen.
    pub fn writeScanlines(self: *Compress, rows: []const u8) Error!usize {
        const pixel_bytes = @as(usize, @intCast(self.handle().input_components));
        const stride = @as(usize, self.handle().image_width) * pixel_bytes;
        if (stride == 0 or rows.len % stride != 0) return error.RowBufferTooSmall;
        const count = rows.len / stride;

        // One row per call, for the reason `Decompress.readScanlines` gives:
        // `scanlines` is a `JSAMPARRAY` holding one pointer per row
        // (`src/src/jpeglib.h:89-92`), so one element cannot stand for
        // several. `src/src/example.c` passes a single `row_pointer[1]` with
        // 1 as well.
        //
        // Upstream's `JSAMPROW` is `unsigned char *` and it only reads the row,
        // which is why this method takes `[]const u8`. The cast is local to
        // this call and never escapes it.
        var written: usize = 0;
        while (written < count) {
            var one: [1]c.JSAMPROW = .{@constCast(rows.ptr + written * stride)};
            const got = c.jpeg_write_scanlines(self.handle(), &one, 1);
            if (got == 0) break;
            written += got;
        }
        if (written < count) return error.ShortWrite;
        return written;
    }

    /// Finish compression, which terminates the destination and is what makes
    /// `bytes` complete.
    ///
    /// `src/src/jpeglib.h:1031`; the destination is terminated here and nowhere
    /// else (`src/src/jdatadst.c:164-172`), so this is the call that writes the
    /// final length back through `outsize`.
    pub fn finishCompress(self: *Compress) void {
        c.jpeg_finish_compress(self.handle());
        // `term_mem_destination` has now written the real length through
        // `outsize` (`src/src/jdatadst.c:196`), so `out_size` stops being a
        // capacity and becomes a length.
        self.finished = true;
    }

    /// How many recoverable corrupt-data warnings this object has produced.
    ///
    /// The same upstream field and counting rule as `Decompress.warningCount`.
    pub fn warningCount(self: *const Compress) c_long {
        const raw = self.raw orelse return 0;
        const err = raw.err orelse return 0;
        return err.num_warnings;
    }

    /// The text of the first warning, or null when there has been none.
    pub fn lastWarning(self: *const Compress) ?[]const u8 {
        if (self.warning_slot.len == 0) return null;
        return self.warning_slot.text[0..self.warning_slot.len];
    }
};
