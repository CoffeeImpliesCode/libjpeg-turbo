// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

//! Zig facade over the libjpeg-turbo 3.2.0 C implementation.
//! It owns JPEG state and compressed output; input and output slices are borrowed.
//! Checked failures return `Error`; fatal libjpeg errors panic.

const std = @import("std");

/// The translated public headers, for upstream APIs not wrapped by this facade.
/// Direct callers inherit libjpeg-turbo's API and error-handler requirements.
pub const c = @import("c");

const rt = @import("rt");

/// True when native symbols are resolved at runtime; false for linked builds.
/// This comptime value lets callers select the matching configuration.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Explicit path or platform-loader name for `load`; there is no fallback.
///
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Errors returned when loading a runtime provider.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load an explicit runtime provider and retain its handle until process exit.
/// Repeated identical requests succeed; mismatches return `LoadError`; linked use panics.
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

/// The retained provider request, or null when no runtime provider is loaded.
pub fn loadedSource() ?LoadSource {
    if (runtime_loaded) return c.loadedSource();
    return null;
}

/// This header's `JPEG_LIB_VERSION`, not a version read from a runtime provider.
/// Use it to record the ABI this module was compiled against.
pub const libjpeg_api_version: c_int = c.JPEG_LIB_VERSION;

/// Maximum buffer size required by libjpeg's `format_message`.
pub const message_length_max: usize = c.JMSG_LENGTH_MAX;

/// libjpeg's `J_COLOR_SPACE`; `.unknown` preserves upstream's default-selection sentinel.
/// Values come from the translated headers.
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

/// Inverse DCT method; `.islow` is upstream's default.
pub const DctMethod = enum(c_int) {
    islow = c.JDCT_ISLOW,
    ifast = c.JDCT_IFAST,
    float = c.JDCT_FLOAT,
};

/// The result values returned by `jpeg_read_header`.
pub const HeaderResult = enum(c_int) {
    /// `JPEG_SUSPENDED`; reachable only with a suspending source.
    suspended = c.JPEG_SUSPENDED,
    /// `JPEG_HEADER_OK`: a complete image datastream.
    header_ok = c.JPEG_HEADER_OK,
    /// Tables-only response; this facade requires an image.
    tables_only = c.JPEG_HEADER_TABLES_ONLY,
};

/// Errors returned by facade checks; fatal libjpeg errors panic instead.
/// See the enum tags for each checked condition.
pub const Error = error{
    NotAJpegImage,
    NotDecompressing,
    PrematureEnd,
    ShortWrite,
    RowBufferTooSmall,
};

extern fn free(ptr: ?*anyopaque) void;

/// Formats the fatal libjpeg error and panics; the upstream handler must not return.
fn errorExit(cinfo: ?*c.jpeg_common_struct) callconv(.c) noreturn {
    var buffer: [message_length_max]u8 = undefined;
    buffer[0] = 0;
    if (cinfo) |info| {
        if (info.err) |err| {
            err.*.format_message.?(info, &buffer);
        }
    }
    std.debug.panic("libjpeg_turbo: {s}", .{std.mem.span(@as([*:0]u8, @ptrCast(&buffer)))});
}

/// Count warnings and retain the first message for `lastWarning`.
fn emitMessage(cinfo: ?*c.jpeg_common_struct, msg_level: c_int) callconv(.c) void {
    // Ignore trace messages; retain the first warning and count all warnings.
    if (msg_level >= 0) return;
    const info = cinfo orelse return;
    const err = info.err orelse return;

    var buffer: [message_length_max]u8 = undefined;
    buffer[0] = 0;
    err.*.format_message.?(info, &buffer);
    const text = std.mem.span(@as([*:0]u8, @ptrCast(&buffer)));

    if (err.*.num_warnings == 0) {
        if (info.client_data) |scratch| {
            const slot: *WarningSlot = @ptrCast(@alignCast(scratch));
            const room = @min(text.len, slot.text.len);
            @memcpy(slot.text[0..room], text[0..room]);
            slot.len = room;
        }
    }
    err.*.num_warnings += 1;
}

const WarningSlot = struct {
    text: [message_length_max]u8 = undefined,
    len: usize = 0,
};

fn installHandlers(err: *c.jpeg_error_mgr) void {
    _ = c.jpeg_std_error(err);
    err.error_exit = errorExit;
    err.emit_message = emitMessage;
}

/// Owns a decompressor record, its error manager, and warning text.
pub const Decompress = struct {
    /// The upstream master record, stored at a stable address.
    storage: c.jpeg_decompress_struct = undefined,

    /// Pointer to the live record, or null when closed.
    raw: ?*c.jpeg_decompress_struct = null,
    err: c.jpeg_error_mgr = undefined,
    warning_slot: WarningSlot = .{},

    /// The decompressor `init` creates, for anything the facade does not wrap.
    pub const Raw = *c.jpeg_decompress_struct;

    /// Read a JPEG header from borrowed input bytes, which must remain valid until `deinit`.
    /// Returns facade errors for checked failures; fatal libjpeg errors panic.
    pub fn init(self: *Decompress, bytes: []const u8) Error!void {
        if (self.raw != null) @panic(
            "libjpeg_turbo: this Decompress is already open. A second init " ++
                "would replace the error-manager pointer the existing object " ++
                "holds, so create one object per decode instead.",
        );

        installHandlers(&self.err);

        self.raw = &self.storage;

        self.raw.?.err = &self.err;

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

        const result: HeaderResult = @fromBackingInt(@intCast(c.jpeg_read_header(self.raw, 1)));
        if (result != .header_ok) return error.NotAJpegImage;
    }

    /// Destroy the decompressor and release its libjpeg-owned resources.
    /// Repeated calls are safe; the input bytes remain caller-owned.
    pub fn deinit(self: *Decompress) void {
        const raw = self.raw orelse return;
        self.raw = null;
        c.jpeg_destroy_decompress(raw);
    }

    /// Whether this object has a live decompressor.
    pub fn isOpen(self: *const Decompress) bool {
        return self.raw != null;
    }

    /// Return the raw record; panics when the object is closed.
    pub fn handle(self: *const Decompress) Raw {
        return self.raw orelse @panic(
            "libjpeg_turbo: this Decompress is not open; call init() first, " ++
                "or do not use it after deinit().",
        );
    }

    /// Nominal image width from the frame header.
    pub fn width(self: *const Decompress) u32 {
        return self.handle().image_width;
    }

    /// Nominal image height from the frame header.
    pub fn height(self: *const Decompress) u32 {
        return self.handle().image_height;
    }

    /// Number of components in the encoded image, before output conversion.
    /// Use `outColorComponents` for the decoded component count.
    pub fn numComponents(self: *const Decompress) i32 {
        return self.handle().num_components;
    }

    /// Colorspace of the encoded image.
    pub fn jpegColorSpace(self: *const Decompress) ColorSpace {
        return @fromBackingInt(@intCast(self.handle().jpeg_color_space));
    }

    /// Current requested output colorspace; upstream may resolve `.unknown` at startup.
    /// Read again after `startDecompress` to see the selected value.
    pub fn outColorSpace(self: *const Decompress) ColorSpace {
        return @fromBackingInt(@intCast(self.handle().out_color_space));
    }

    /// Request an output colorspace before `startDecompress`.
    /// Unsupported conversions are fatal libjpeg errors.
    pub fn requestOutColorSpace(self: *Decompress, space: ColorSpace) void {
        self.handle().out_color_space = @intCast(@backingInt(space));
    }

    /// Select the inverse DCT method; the default is `.islow`.
    pub fn requestDctMethod(self: *Decompress, method: DctMethod) void {
        self.handle().dct_method = @backingInt(method);
    }

    /// Start decoding and compute output dimensions and components.
    /// Returns `NotDecompressing` if upstream declines to start.
    pub fn startDecompress(self: *Decompress) Error!void {
        if (c.jpeg_start_decompress(self.handle()) == 0) return error.NotDecompressing;
    }

    /// Decoded image width, which may differ from `width`.
    pub fn outputWidth(self: *const Decompress) u32 {
        return self.handle().output_width;
    }

    /// Decoded image height.
    pub fn outputHeight(self: *const Decompress) u32 {
        return self.handle().output_height;
    }

    /// Number of components in each decoded pixel.
    pub fn outColorComponents(self: *const Decompress) i32 {
        return self.handle().out_color_components;
    }

    /// Number of samples per output row pixel, including colormap indices.
    /// This can differ from `outColorComponents` when quantizing colors.
    pub fn outputComponents(self: *const Decompress) i32 {
        return self.handle().output_components;
    }

    /// Recommended number of rows to provide per call.
    /// Smaller buffers are valid but may cause extra copying.
    pub fn recommendedRowBufferHeight(self: *const Decompress) i32 {
        return self.handle().rec_outbuf_height;
    }

    /// Decoded row size in bytes: output width times output components.
    pub fn rowBytes(self: *const Decompress) usize {
        const raw = self.handle();
        return @as(usize, raw.output_width) * @as(usize, @intCast(raw.output_components));
    }

    /// Index of the next output row.
    pub fn outputScanline(self: *const Decompress) u32 {
        return self.handle().output_scanline;
    }

    /// Decode whole rows into caller-owned storage and return the row count.
    /// Requires one row of space; returns `RowBufferTooSmall` or `PrematureEnd`.
    pub fn readScanlines(self: *Decompress, out: []u8) Error!usize {
        const stride = self.rowBytes();
        if (stride == 0 or out.len < stride) return error.RowBufferTooSmall;
        const rows = out.len / stride;

        // JSAMPARRAY needs one pointer per row; one-row calls keep the array in bounds.
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

    /// Decode the full image into a caller-owned buffer of `rowBytes() * outputHeight()` bytes.
    /// Returns `RowBufferTooSmall` or `PrematureEnd` for checked failures.
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

    /// Finish decoding; call after all output rows have been read.
    pub fn finishDecompress(self: *Decompress) void {
        _ = c.jpeg_finish_decompress(self.handle());
    }

    /// Number of recoverable warnings from this decode.
    pub fn warningCount(self: *const Decompress) c_long {
        const raw = self.raw orelse return 0;
        const err = raw.err orelse return 0;
        return err.*.num_warnings;
    }

    /// Borrowed text of the first warning, or null; valid until `deinit`.
    pub fn lastWarning(self: *const Decompress) ?[]const u8 {
        if (self.warning_slot.len == 0) return null;
        return self.warning_slot.text[0..self.warning_slot.len];
    }
};

/// Owns a compressor record, its error manager, and the compressed output buffer.
/// Initialize it in place because libjpeg retains pointers into the object.
pub const Compress = struct {
    /// The upstream master record, stored at a stable address.
    storage: c.jpeg_compress_struct = undefined,

    /// Pointer to the live record, or null when closed.
    raw: ?*c.jpeg_compress_struct = null,
    err: c.jpeg_error_mgr = undefined,
    warning_slot: WarningSlot = .{},

    /// Buffer allocated by `jpeg_mem_dest`; released by `deinit`.
    out_buffer: [*c]u8 = null,
    /// Compressed byte length, set when `finishCompress` runs.
    out_size: c_ulong = 0,

    /// Whether the destination has been finished and `bytes()` is complete.
    finished: bool = false,

    /// The compressor `init` creates, for anything the facade does not wrap.
    pub const Raw = *c.jpeg_compress_struct;

    /// Initialize a memory compressor for the given image dimensions.
    /// Set input colorspace before `setDefaults`; fatal libjpeg errors panic.
    pub fn init(self: *Compress, width: u32, height: u32, components: i32) void {
        if (self.raw != null) @panic(
            "libjpeg_turbo: this Compress is already open. A second init would " ++
                "replace the error-manager pointer the existing object holds, " ++
                "so create one object per image instead.",
        );

        installHandlers(&self.err);

        self.raw = &self.storage;

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

        c.jpeg_mem_dest(self.raw, &self.out_buffer, &self.out_size);
    }

    /// Destroy the compressor and free its output buffer.
    /// Repeated calls are safe; borrowed output bytes expire on destruction.
    pub fn deinit(self: *Compress) void {
        const buffer = self.out_buffer;
        const raw = self.raw orelse return;
        self.out_buffer = null;
        self.raw = null;
        c.jpeg_destroy_compress(raw);
        if (buffer) |owned| {
            free(@constCast(owned));
        }
    }

    /// Whether this object has a live compressor.
    pub fn isOpen(self: *const Compress) bool {
        return self.raw != null;
    }

    /// Return the raw record; panics when the object is closed.
    pub fn handle(self: *const Compress) Raw {
        return self.raw orelse @panic(
            "libjpeg_turbo: this Compress is not open; call init() first, " ++
                "or do not use it after deinit().",
        );
    }

    /// Set the colorspace of input pixels; call before `setDefaults`.
    pub fn setInputColorSpace(self: *Compress, space: ColorSpace) void {
        self.handle().in_color_space = @intCast(@backingInt(space));
    }

    /// Apply upstream defaults after setting the input colorspace.
    pub fn setDefaults(self: *Compress) void {
        c.jpeg_set_defaults(self.handle());
    }

    /// Set quality from 1 to 100.
    /// `force_baseline` requests a baseline-compatible stream.
    pub fn setQuality(self: *Compress, quality: i32, force_baseline: bool) void {
        c.jpeg_set_quality(self.handle(), quality, if (force_baseline) 1 else 0);
    }

    /// Borrowed compressed bytes, available after `finishCompress`.
    /// The slice length is exact and remains valid until `deinit`.
    pub fn bytes(self: *const Compress) []const u8 {
        if (!self.finished) return &.{};
        const buffer = self.out_buffer;
        if (buffer == null) return &.{};
        return @as([*]const u8, buffer)[0..@intCast(self.out_size)];
    }

    /// Start compression; fatal libjpeg errors panic rather than return.
    /// Call `setInputColorSpace` and `setDefaults` first.
    pub fn startCompress(self: *Compress) void {
        c.jpeg_start_compress(self.handle(), 0);
    }

    /// Compress whole rows from caller-owned storage and return the row count.
    /// Returns `RowBufferTooSmall` or `ShortWrite` for checked failures.
    pub fn writeScanlines(self: *Compress, rows: []const u8) Error!usize {
        const pixel_bytes = @as(usize, @intCast(self.handle().input_components));
        const stride = @as(usize, self.handle().image_width) * pixel_bytes;
        if (stride == 0 or rows.len % stride != 0) return error.RowBufferTooSmall;
        const count = rows.len / stride;

        // JSAMPARRAY needs one pointer per row, so submit one row at a time.
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

    /// Finish compression and finalize the output length returned by `bytes()`.
    pub fn finishCompress(self: *Compress) void {
        c.jpeg_finish_compress(self.handle());
        self.finished = true;
    }

    /// Number of recoverable warnings from this compressor.
    pub fn warningCount(self: *const Compress) c_long {
        const raw = self.raw orelse return 0;
        const err = raw.err orelse return 0;
        return err.*.num_warnings;
    }

    /// The text of the first warning, or null when there has been none.
    pub fn lastWarning(self: *const Compress) ?[]const u8 {
        if (self.warning_slot.len == 0) return null;
        return self.warning_slot.text[0..self.warning_slot.len];
    }
};
