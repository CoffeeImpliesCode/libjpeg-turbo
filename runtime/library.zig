// SPDX-License-Identifier: MIT
// See ../FORK-LICENSE.md for what that identifier covers.

//! libjpeg-turbo's side of the runtime loader: the names its synchronization
//! binding has, what it requires of a provider beyond resolving its symbols, and
//! what the external ABI boundary for this provider actually is.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them
//! libjpeg-turbo's, and it is the file another SDK replaces.
//!
//! ## What a provider must be
//!
//! Every `extern` declaration `zig/translate.h` produces that is not the C
//! library's own. In this configuration that is every function the four
//! translated headers declare: the 66 `EXTERN(...)` lines of
//! `src/src/jpeglib.h`, all of them named `jpeg_` or `jpeg12_`/`jpeg16_`.
//!
//! Nothing sits behind a macro this build leaves off, so `provider_optional`
//! and `provider_excluded` in `runtime/graph.zig` are both empty and a provider
//! that does not export the whole set is refused rather than half used.
//!
//! The 12- and 16-bit family is worth naming, because it is the one place a
//! conforming provider could plausibly be short. `jpeg12_*` and `jpeg16_*` are
//! declared unconditionally in every configuration - `src/src/jconfig.h.in:24-35`
//! explains why - and **refuse at run time on an 8-bit build**. They are still
//! symbols the library exports, so they are still required of a provider, and
//! `MEM_SRCDST_SUPPORTED` is a plain `#define` rather than a `#cmakedefine`
//! (`src/src/jconfig.h.in:18-19`), so `jpeg_mem_src`/`jpeg_mem_dest` exist in
//! this configuration unconditionally too.
//!
//! The C library's own surface reaches the translation and is classified as
//! noise in `runtime/graph.zig` rather than being part of what a provider owes:
//! `src/src/jpeglib.h:21-29` says in as many words that it does *not* include
//! `<stdio.h>` "despite the fact that it uses `FILE` and `size_t`", so
//! `zig/translate.h` opens `<stddef.h>` and `<stdio.h>` itself. That is the only
//! route by which any C library header enters this translation:
//! `src/src/jconfig.h` opens no header, `src/src/jmorecfg.h` is typedefs and
//! macros from `:49` to `:389`, `src/src/jerror.h` opens no header, and
//! `src/src/jpeglib.h:1212-1215`'s `jpegint.h`/`jerror.h` tail is behind
//! `JPEG_INTERNALS`, which this wrapper leaves undefined. A `libjpeg.so` exports
//! none of the C library's `stdio` surface, so asking a provider for one would
//! either fail the load outright or resolve it out of the C library the provider
//! itself depends on.
//!
//! ## The ABI boundary, stated honestly
//!
//! The supported external ABI family is **the libjpeg v6b API, as libjpeg-turbo
//! 3.2.0 implements it with `WITH_SIMD`, `WITH_ARITH_ENC`, `WITH_ARITH_DEC` and
//! `WITH_JPEG7`/`WITH_JPEG8` all off**, which is exactly the configuration this
//! package builds. That is a narrower claim than "a shared object that exports
//! these names", and the difference is real:
//!
//!   * **The struct layouts must match, and nothing checks them by name.**
//!     `jpeg_compress_struct` and `jpeg_decompress_struct` are large public
//!     structs (`src/src/jpeglib.h:352` onward), not opaque handles. Resolving
//!     `jpeg_CreateCompress` says the name exists; it says nothing about whether
//!     this build's `sizeof` agrees with the provider's, nor about whether the
//!     `J_COLOR_SPACE` and `J_DCT_METHOD` enumerations have the same values.
//!     **That is why the load-time check below is behavioural and not a version
//!     comparison** - see "There is no version to check".
//!   * **`error_exit` must not return.** `struct jpeg_error_mgr`'s first member
//!     is documented as "Error exit handler: does not return to caller"
//!     (`src/src/jpeglib.h:784-785`), and libjpeg's own `error_exit` formats the
//!     message, destroys the object and calls `exit(EXIT_FAILURE)`
//!     (`src/src/jerror.c:66-76`). A caller that installed a handler returning
//!     normally would re-enter libjpeg at an arbitrary point.
//!   * **Function pointers cross the boundary in both directions.**
//!     `cinfo->err->error_exit`, `emit_message`, `output_message` and
//!     `format_message` are the provider's own C calling this module's Zig code
//!     with the provider's own calling convention.
//!   * **The allocator is the provider's.** Everything a JPEG object allocates
//!     comes out of `src/src/jmemmgr.c` through `src/src/jmemnobs.c:31-58`, where
//!     `jpeg_get_small`/`jpeg_get_large` are `malloc` and the frees are `free`.
//!     `jpeg_mem_dest` allocates its output buffer with plain `malloc`
//!     (`src/src/jdatadst.c:143`) and upstream says the application is
//!     responsible for freeing it (`src/src/jdatadst.c:240-244`), so this file
//!     frees it with the C library's own `free` - the only `free` that can
//!     legally release a pointer this library's `malloc` returned. No Zig
//!     allocator is anywhere in that path, so a Zig test allocator cannot be
//!     given a leak oracle for it.
//!
//! ## There is no version to check, and none is invented
//!
//! **libjpeg-turbo exports no version symbol.** `JPEG_LIB_VERSION`,
//! `LIBJPEG_TURBO_VERSION` and `LIBJPEG_TURBO_VERSION_NUMBER` are compile-time
//! constants in the *generated* `jconfig.h` (`src/src/jconfig.h.in:4,7,10`). They
//! live in a header, not in a shared object's symbol table, so no loader can ask
//! a provider which release it is. So there is no load-time version check here,
//! and no substitute for one disguised as one.
//!
//! What `validate` does instead is the exchange that would actually break if the
//! ABI families disagreed: it compresses a 1x1 greyscale image through the
//! candidate table, takes the bytes the provider's own `jpeg_mem_dest` says it
//! wrote, and decompresses them back through the same table, requiring the
//! original sample. A provider whose `sizeof(jpeg_compress_struct)` or whose
//! enumeration values disagree fails there - in the provider's own `error_exit`,
//! or on the value it hands back - rather than passing a string comparison
//! against a constant this package compiled in.
//!
//! **One consequence has to be stated rather than discovered.** A failure inside
//! that exchange reaches `error_exit`, which upstream declares may not return
//! (`src/src/jpeglib.h:784-785`). This file installs its own handler there, and
//! it **stops the process with libjpeg's own formatted message** rather than
//! returning `ValidationFailed`. It does not `exit()` - that would take this
//! package's diagnostics with it - and it does not `longjmp`, because a longjmp
//! skips Zig frames rather than unwinding them and would leave the loader's own
//! bookkeeping half-done. So: a provider that exports every name and still
//! disagrees on the ABI stops the program instead of being refused. The
//! hand-written part of the check - a provider that cannot do the exchange at
//! all - does return a refusal, and the loader closes the candidate without
//! publishing it.
//!
//! What is deliberately *not* called during a load is anything whose failure this
//! file cannot intercept. The exchange below uses only upstream's normal
//! `require_image = TRUE` calls and a well-formed 1x1 image, both of which are
//! the documented success paths.
const std = @import("std");

const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.c` compiled with
/// `RT_SYNC_PREFIX=jpeg_turbo_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols, and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
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

/// The one `free` in this file.
///
/// `jpeg_mem_dest`'s output buffer is a `malloc` pointer from the provider's own
/// allocator (`src/src/jdatadst.c:143`) and upstream requires the application to
/// free it (`src/src/jdatadst.c:240-244`). It is declared here rather than
/// reached through the dispatch because `zig/translate.h` opens `<stddef.h>` and
/// `<stdio.h>` and neither declares `free`; adding `<stdlib.h>` would drag the
/// whole `stdlib` surface into every dispatch's noise classification for one
/// symbol.
///
/// This is the C library's `free`, which is linked. It is **not** part of the
/// dispatch table: declaring an `extern` does not make it libjpeg-turbo's.
extern fn free(ptr: ?*anyopaque) void;

/// The colorspace the self-check compresses and decompresses: greyscale, which
/// is `JCS_GRAYSCALE`.
///
/// The `J_COLOR_SPACE` values are the libjpeg v6b ABI's and have been fixed
/// since v6b: `JCS_UNKNOWN` 0, `JCS_GRAYSCALE` 1, `JCS_RGB` 2, `JCS_YCbCr` 3
/// (`src/src/jpeglib.h:264-290`). The literal is used rather than a constant
/// read through the table because the table routes *functions*, not macros, and
/// `JCS_GRAYSCALE` is a macro. A 1-component greyscale image is the smallest one
/// upstream documents, and its decode is exact under the default quantisation,
/// so the check does not depend on any rounding.
const jcs_grayscale: c_int = 1;

/// The one sample the self-check writes and requires back.
///
/// 200 is neither 0 nor 255, so a value that arrived as a saturated clamp or a
/// truncated coefficient would not match it. It is also the same constant
/// `fixtures/grey8x8-200.jpg` decodes to, which is what makes the self-check and
/// the four independent known answers the same question asked of one block
/// instead of two.
const probe_sample: u8 = 200;

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the headers said, and neither imports the other.
///
/// Everything that has to name a translated *type* - the error manager, the two
/// JPEG structs, the scanline row array - lives inside this returned struct,
/// because `dispatch` is only in scope here.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "libjpeg_turbo";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated headers, not from this file.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// This project's namespaced synchronization binding.
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

        /// The load-time check, run after every symbol resolved and before
        /// anything is published.
        ///
        /// A non-null answer is `ValidationFailed` and the loader closes the
        /// candidate without publishing it. Null means the candidate did the
        /// exchange below.
        ///
        /// The check has no allocator and no state of its own. Everything it
        /// allocates it allocates through the candidate provider and frees before
        /// returning - the compressed buffer through this file's `free`, which is
        /// the C library's, and everything else through
        /// `jpeg_destroy_compress`/`jpeg_destroy_decompress`.
        pub fn validate(dst: *const table) ?[]const u8 {
            // The one thing that can be answered without doing any work:
            // `jpeg_std_error` must hand back a manager the caller may write to
            // (`src/src/jpeglib.h`, the `jpeg_std_error` declaration). A provider
            // that cannot is not usable at all.
            var err: dispatch.jpeg_error_mgr = undefined;
            const errp = dst.jpeg_std_error(&err) orelse
                return "this provider's jpeg_std_error answered NULL, so no caller " ++
                    "could install an error manager on it";

            // Both halves of the exchange go through the same `dst`, which is the
            // point: a table that wired two names to two different providers
            // would fail here even though every symbol resolved.
            errp.error_exit = onErrorExit;
            errp.emit_message = onEmitMessage;

            const sample = exchange(dst, errp) orelse
                return "this provider could not compress and decompress a 1x1 " ++
                    "greyscale image through the resolved table, so its " ++
                    "jpeg_compress_struct / jpeg_decompress_struct layouts or its " ++
                    "J_COLOR_SPACE values disagree with the headers this SDK compiled " ++
                    "against";

            // The answer, as a fact rather than as a return code: the sample has
            // to come back exactly. `exchange` checked it; this only names it.
            if (sample != probe_sample) {
                return "a 1x1 greyscale image round-tripped through this provider " ++
                    "with the wrong sample, so it is not implementing the libjpeg " ++
                    "v6b decode this SDK's headers describe";
            }
            return null;
        }

        /// Stops the program with libjpeg's own message.
        ///
        /// `error_exit` is documented not to return
        /// (`src/src/jpeglib.h:784-785`) and every `ERREXIT*` macro in
        /// `src/src/jerror.h:239-277` is written as though nothing follows it, so
        /// this cannot return either. It formats the message with the provider's
        /// own `format_message` - upstream's text with upstream's parameters - and
        /// stops there. See the module comment for why this is a stop and not a
        /// refusal.
        fn onErrorExit(cinfo: ?*dispatch.jpeg_common_struct) callconv(.c) noreturn {
            var buffer: [200]u8 = undefined;
            buffer[0] = 0;
            if (cinfo) |info| {
                if (info.err) |err| {
                    // `format_message` NUL-terminates (`src/src/jerror.c:147-150`).
                    err.format_message(info, &buffer);
                }
            }
            std.debug.panic("libjpeg_turbo: the provider reported {s}", .{std.mem.span(&buffer)});
        }

        /// Keeps the load quiet.
        ///
        /// `jpeg_std_error`'s own `emit_message` writes to stderr
        /// (`src/src/jerror.c:129-137`), and a loader that printed to stderr
        /// while deciding whether to accept a candidate would make that decision
        /// indistinguishable from a library complaining. Nothing here is a message
        /// channel; the only output this file produces is the refusal the loader
        /// prints, and the panic above.
        fn onEmitMessage(_: ?*dispatch.jpeg_common_struct, _: c_int) callconv(.c) void {}

        /// Compresses one sample, reads it back, and frees everything.
        ///
        /// Returns the sample the provider produced, or null when either half
        /// could not be carried out. There is deliberately no `errdefer` on the
        /// objects the provider allocates: `onErrorExit` may stop the process from
        /// inside a provider call, and a `defer` that such an exit skipped would
        /// then be the thing that hid the leak. The success path frees everything
        /// explicitly, and each failure path frees what it can before returning.
        fn exchange(dst: *const table, errp: *dispatch.jpeg_error_mgr) ?u8 {
            // -------------------------------------------------------- compress
            var cinfo: dispatch.jpeg_compress_struct = undefined;
            dst.jpeg_CreateCompress(
                &cinfo,
                // The documented macro's own argument (`src/src/jpeglib.h:1014-1016`
                // and `JPEG_LIB_VERSION`), not a re-derivation: a provider whose
                // `JPEG_LIB_VERSION` differs refuses here through `ERREXIT`.
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

            // The documented order: `in_color_space` has to be right *before*
            // `jpeg_set_defaults` (`src/src/jpeglib.h:351-359`).
            dst.jpeg_set_defaults(&cinfo);
            // Quality 100 with `force_baseline = TRUE`, upstream's own round-trip
            // recipe. It needs no arithmetic about quantisation tables: the
            // question this answers is whether the provider agrees with itself,
            // not whether a JPEG file is well made.
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

            // ------------------------------------------------------ decompress
            var result: ?u8 = null;
            var dcinfo: dispatch.jpeg_decompress_struct = undefined;
            dst.jpeg_CreateDecompress(
                &dcinfo,
                dispatch.JPEG_LIB_VERSION,
                @sizeOf(dispatch.jpeg_decompress_struct),
            );
            dcinfo.err = errp;
            dst.jpeg_mem_src(&dcinfo, @constCast(buffer), @intCast(length));

            // `require_image = TRUE` (`src/src/jpeglib.h:1068-1071`), the
            // documented normal case.
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