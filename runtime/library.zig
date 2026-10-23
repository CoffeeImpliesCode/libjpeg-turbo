// SPDX-License-Identifier: MIT
// See ../FORK-LICENSE.md for what that identifier covers.

//! Provider-specific runtime-loader descriptor for libjpeg-turbo.
//! Requires every translated libjpeg symbol and validates providers with a 1x1 greyscale round-trip.
//! Uses the libjpeg v6b ABI; `error_exit` must not return, and JPEG-owned buffers use the C allocator.
const std = @import("std");

const rt = @import("rt");

/// Namespaced synchronization functions matching `runtime/sync.c`.
/// A distinct prefix gives each loader instance independent lock state.
pub const Sync = struct {
    extern fn jpeg_turbo_rt_lock() void;
    extern fn jpeg_turbo_rt_unlock() void;
    extern fn jpeg_turbo_rt_wait() void;
    extern fn jpeg_turbo_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every ABI
    // this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
    extern fn jpeg_turbo_rt_thread_self() u64;

    pub fn lock() void {
        jpeg_turbo_rt_lock();
    }
    pub fn unlock() void {
        jpeg_turbo_rt_unlock();
    }
    pub fn wait() void {
        jpeg_turbo_rt_wait();
    }
    pub fn broadcast() void {
        jpeg_turbo_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return jpeg_turbo_rt_thread_self();
    }
};

/// C-library `free` for buffers returned by the provider's `jpeg_mem_dest`.
/// Keep it direct; the dispatch table contains libjpeg-turbo symbols only.
extern fn free(ptr: ?*anyopaque) void;

/// The v6b `JCS_GRAYSCALE` value; color macros are not function-table entries.
/// The 1x1 greyscale check does not depend on quantization arithmetic.
const jcs_grayscale: c_int = 1;

/// A non-saturated sample that matches the known decoded value in the 8x8 fixture.
const probe_sample: u8 = 200;

/// Loader configuration bound to the generated dispatch type.
/// Header-derived types live here because only this module can name the dispatch.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Names the library in the pre-load panic.
        pub const library_name = "libjpeg_turbo";

        /// Header-derived table and required-symbol list.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// Namespaced process synchronization for this loader.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Runs after symbol resolution and before publication; non-null rejects the provider.
        /// Releases allocations through provider destructors and C `free` before return.
        pub fn validate(dst: *const table) ?[]const u8 {
            // `jpeg_std_error` must return a writable error manager.
            var err: dispatch.jpeg_error_mgr = undefined;
            const errp = dst.jpeg_std_error(&err) orelse
                return "this provider's jpeg_std_error answered NULL, so no caller " ++
                    "could install an error manager on it";

            // Both exchange halves use `dst`, so mixed-provider tables fail validation.
            errp.error_exit = onErrorExit;
            errp.emit_message = onEmitMessage;

            const sample = exchange(dst, errp) orelse
                return "this provider could not compress and decompress a 1x1 " ++
                    "greyscale image through the resolved table, so its " ++
                    "jpeg_compress_struct / jpeg_decompress_struct layouts or its " ++
                    "J_COLOR_SPACE values disagree with the headers this SDK compiled " ++
                    "against";

            // Check the decoded sample, not only the return code.
            if (sample != probe_sample) {
                return "a 1x1 greyscale image round-tripped through this provider " ++
                    "with the wrong sample, so it is not implementing the libjpeg " ++
                    "v6b decode this SDK's headers describe";
            }
            return null;
        }

        /// Formats the provider's error, then stops as libjpeg requires.
        /// The C callback is noreturn; it cannot report a recoverable refusal.
        fn onErrorExit(cinfo: ?*dispatch.jpeg_common_struct) callconv(.c) noreturn {
            var buffer: [200]u8 = undefined;
            buffer[0] = 0;
            if (cinfo) |info| {
                if (info.err) |err| {
                    // `format_message` NUL-terminates its output.
                    err.format_message(info, &buffer);
                }
            }
            std.debug.panic("libjpeg_turbo: the provider reported {s}", .{std.mem.span(&buffer)});
        }

        /// Suppress stderr while validating a candidate provider.
        fn onEmitMessage(_: ?*dispatch.jpeg_common_struct, _: c_int) callconv(.c) void {}

        /// Round-trip one sample; return null on a recoverable failure.
        /// Success frees provider/C allocations; `onErrorExit` can stop inside a call.
        fn exchange(dst: *const table, errp: *dispatch.jpeg_error_mgr) ?u8 {
            // Compress.
            var cinfo: dispatch.jpeg_compress_struct = undefined;
            dst.jpeg_CreateCompress(
                &cinfo,
                // Use the provider's macro so a version mismatch is rejected by libjpeg.
                dispatch.JPEG_LIB_VERSION,
                @sizeOf(dispatch.jpeg_compress_struct),
            );
            cinfo.err = errp;
            cinfo.image_width = 1;
            cinfo.image_height = 1;
            cinfo.input_components = 1;
            cinfo.in_color_space = jcs_grayscale;

            var out_buffer: ?[*]u8 = null;
            var out_size: c_ulong = 0;
            dst.jpeg_mem_dest(&cinfo, &out_buffer, &out_size);

            // `in_color_space` must be set immediately before `jpeg_set_defaults`.
            dst.jpeg_set_defaults(&cinfo);
            // Use upstream's baseline quality-100 recipe; quantization is not under test.
            dst.jpeg_set_quality(&cinfo, 100, 1);
            dst.jpeg_start_compress(&cinfo, 1);

            var sample = [1]u8{probe_sample};
            var one_row: [1]dispatch.JSAMPROW = .{&sample};
            _ = dst.jpeg_write_scanlines(&cinfo, &one_row, 1);
            dst.jpeg_finish_compress(&cinfo);
            dst.jpeg_destroy_compress(&cinfo);

            const buffer = out_buffer orelse return null;
            const length: usize = @intCast(out_size);
            if (length == 0) {
                free(@constCast(buffer));
                return null;
            }

            // Decompress.
            var result: ?u8 = null;
            var dcinfo: dispatch.jpeg_decompress_struct = undefined;
            dst.jpeg_CreateDecompress(
                &dcinfo,
                dispatch.JPEG_LIB_VERSION,
                @sizeOf(dispatch.jpeg_decompress_struct),
            );
            dcinfo.err = errp;
            dst.jpeg_mem_src(&dcinfo, @constCast(buffer), @intCast(length));

            // `TRUE` requests the documented normal image header.
            if (dst.jpeg_read_header(&dcinfo, 1) != dispatch.JPEG_HEADER_OK) {
                dst.jpeg_destroy_decompress(&dcinfo);
                free(@constCast(buffer));
                return null;
            }
            dcinfo.out_color_space = jcs_grayscale;
            if (dst.jpeg_start_decompress(&dcinfo) == 0) {
                dst.jpeg_destroy_decompress(&dcinfo);
                free(@constCast(buffer));
                return null;
            }
            if (dcinfo.output_width == 1 and dcinfo.output_height == 1) {
                var got: [1]u8 = undefined;
                var row: [1]dispatch.JSAMPROW = .{&got};
                if (dst.jpeg_read_scanlines(&dcinfo, &row, 1) == 1) {
                    result = got[0];
                }
            }
            dst.jpeg_finish_decompress(&dcinfo);
            dst.jpeg_destroy_decompress(&dcinfo);

            free(@constCast(buffer));
            return result;
        }
    };
}
