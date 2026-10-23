// SPDX-License-Identifier: MIT
//
//! Runtime loader with one process-wide dispatch table.
//! Explicit loads publish only after required symbols resolve and provider validation succeeds.
//! Failed attempts leave no provider; successful handles and request copies live until process exit.

const std = @import("std");
const builtin = @import("builtin");

/// Request a library by absolute path or platform-loader name; there is no fallback between forms.
pub const LoadSource = union(enum) {
    /// Absolute file path; relative paths are invalid.
    path: []const u8,
    /// Platform-loader basename or SONAME; separators and NUL bytes are invalid.
    system: []const u8,
};

/// Reasons a load can be refused.
pub const LoadError = error{
    /// Empty path or system name, rejected before calling the platform loader.
    EmptySource,
    /// Request exceeds `max_source_len`; it is refused, never truncated.
    SourceTooLong,
    /// Path is not absolute, system name has a path component, or request contains NUL.
    InvalidSource,
    /// Target has no dynamic library loader.
    UnsupportedTarget,
    /// Platform loader refused the library or one of its dependencies.
    OpenFailed,
    /// Required export is missing; the candidate is closed.
    MissingSymbol,
    /// Provider validation declined the candidate; it is closed.
    ValidationFailed,
    /// A different request conflicts with the in-flight or published provider.
    ProviderMismatch,
    /// The attempt thread called `load` recursively.
    ReentrantLoad,
};

/// Maximum remembered request length, in bytes.
pub const max_source_len = 32768;

/// Fixed-size copy of a request; it allocates nothing and lasts for the process.
const SourceRecord = struct {
    tag: enum(u8) { none = 0, path, system } = .none,
    len: u32 = 0,
    bytes: [max_source_len]u8 = undefined,

    /// Copy a validated request while holding the loader lock.
    fn set(self: *SourceRecord, request: LoadSource) void {
        const text = switch (request) {
            .path => |p| p,
            .system => |s| s,
        };
        @memcpy(self.bytes[0..text.len], text);
        self.len = @intCast(text.len);
        self.tag = switch (request) {
            .path => .path,
            .system => .system,
        };
    }

    /// Return the remembered request, backed by this process-lifetime record.
    pub fn source(self: *const SourceRecord) ?LoadSource {
        const text = self.bytes[0..self.len];
        return switch (self.tag) {
            .none => null,
            .path => .{ .path = text },
            .system => .{ .system = text },
        };
    }
};

/// Requests match only when both kind and bytes match; paths are not normalized.
pub fn eqlSource(a: LoadSource, b: LoadSource) bool {
    return switch (a) {
        .path => |pa| switch (b) {
            .path => |pb| std.mem.eql(u8, pa, pb),
            .system => false,
        },
        .system => |sa| switch (b) {
            .system => |sb| std.mem.eql(u8, sa, sb),
            .path => false,
        },
    };
}

fn validateSource(source: LoadSource) LoadError!void {
    const text = switch (source) {
        .path => |p| p,
        .system => |s| s,
    };
    if (text.len == 0) return error.EmptySource;
    if (text.len > max_source_len) return error.SourceTooLong;
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidSource;
    switch (source) {
        .path => {
            const absolute = if (builtin.target.os.tag == .windows)
                switch (std.fs.path.getWin32PathType(u8, text)) {
                    .drive_absolute, .unc_absolute, .local_device, .root_local_device => true,
                    .relative, .rooted, .drive_relative => false,
                }
            else
                std.fs.path.isAbsolutePosix(text);
            if (!absolute) return error.InvalidSource;
        },
        .system => {
            for (text) |byte| {
                if (std.fs.path.isSep(byte)) return error.InvalidSource;
                if (builtin.target.os.tag == .windows and byte == ':') return error.InvalidSource;
            }
        },
    }
}

/// Loader state.
pub const Phase = enum(u8) {
    /// No active provider; failed attempts return here for explicit retry.
    not_loaded = 0,
    /// One thread is filling the table; readers cannot observe it.
    loading = 1,
    /// The table has been published.
    ready = 2,
};

/// Readiness flag for table publication.
/// The release store and acquire reads make table writes visible to routed calls.
pub const Ready = struct {
    phase: std.atomic.Value(u8) = .init(@backingInt(Phase.not_loaded)),

    /// Acquire-read readiness before a routed call uses the table.
    pub fn isReady(self: *const Ready) bool {
        return self.phase.load(.acquire) == @backingInt(Phase.ready);
    }

    /// Read the state for decisions made under the loader lock.
    pub fn state(self: *const Ready) Phase {
        return @fromBackingInt(self.phase.load(.acquire));
    }

    /// Publish or withdraw readiness with release ordering.
    pub fn set(self: *Ready, value: Phase) void {
        self.phase.store(@backingInt(value), .release);
    }
};

/// Required export kind: function pointer or address of exported data.
pub const SymbolKind = enum {
    /// Table stores the exact function-pointer type declared by the translated header.
    function,
    /// Table stores the object's address, not a copy.
    data,
};

/// Required export name and kind.
pub const Symbol = struct {
    /// Exported name as declared by the C header.
    name: [:0]const u8,
    /// Value stored in the corresponding table field.
    kind: SymbolKind,
};

/// Panic with the library and symbol name when a routed call precedes a successful load.
pub fn panicNotReady(library: []const u8, comptime symbol: []const u8) noreturn {
    std.debug.panic(
        "{s}: {s} was called before this module was loaded; call " ++
            "load({{ .path = \"...\" }}) or load({{ .system = \"...\" }}) first",
        .{ library, symbol },
    );
}

/// Whether the target provides a dynamic library loader.
pub const supported_target: bool = switch (builtin.target.os.tag) {
    .wasi, .emscripten, .freestanding => false,
    else => true,
};

/// Process-global loader for one configured module.
/// `Config` provides `library_name`, `table`, `symbols`, `tablePtr`, `ready`, `assign`, and `sync`.
/// Optional symbols use `optional_symbols`, `assignOptional`, and `assignMissing`; optional `validate` runs before publication.
/// Success publishes once and retains the handle and request; failure closes the candidate and allows explicit retry.
/// Same-request callers join an in-flight attempt; a different request mismatches, and recursive loads return `ReentrantLoad`.
/// Failed attempts remain until their waiters drain.
/// A provider constructor that waits for another thread calling `load` can deadlock; the loader cannot break that cycle.
pub fn Loader(comptime Config: type) type {
    return struct {
        const LoaderType = @This();

        /// Table type filled by this loader.
        pub const table_type = Config.table;

        /// Current or undrained attempt, local to this configured module.
        attempt: ?Attempt = null,

        /// Request copy, read under the lock until readiness is published.
        request: SourceRecord = .{},

        /// Fill the table or return a load error.
        /// Safe from any thread; this is the only table-filling entry point.
        pub fn load(self: *LoaderType, source: LoadSource) LoadError!void {
            try validateSource(source);
            // The loaded fast path needs one acquire read and no lock.
            if (Config.ready().isReady()) return self.accept(source);

            Config.sync.lock();
            while (true) {
                switch (Config.ready().state()) {
                    .ready => {
                        Config.sync.unlock();
                        return self.accept(source);
                    },
                    .loading => {
                        const attempt = &self.attempt.?;
                        if (attempt.owner == Config.sync.threadSelf()) {
                            Config.sync.unlock();
                            return error.ReentrantLoad;
                        }
                        if (!eqlSource(self.request.source().?, source)) {
                            Config.sync.unlock();
                            return error.ProviderMismatch;
                        }
                        // Same-source callers join this attempt and receive its result.
                        attempt.waiters += 1;
                        while (Config.ready().state() == .loading) Config.sync.wait();
                        const result = attempt.result;
                        attempt.waiters -= 1;
                        // Keep the attempt until every waiter has copied its result.
                        Config.sync.broadcast();
                        Config.sync.unlock();
                        return result;
                    },
                    .not_loaded => {
                        // A failed attempt remains until its waiters drain.
                        if (self.attempt != null) {
                            Config.sync.wait();
                            continue;
                        }
                        break;
                    },
                }
            }

            self.request.set(source);
            self.attempt = .{ .owner = Config.sync.threadSelf() };
            Config.ready().set(.loading);
            Config.sync.unlock();

            // Run constructors and symbol resolution without holding the loader lock.
            const outcome = runAttempt(self.request.source().?);
            const succeeded = if (outcome) |_| true else |_| false;

            Config.sync.lock();
            self.attempt.?.result = outcome;
            Config.ready().set(if (succeeded) .ready else .not_loaded);
            // Wake all waiters; each must leave before the attempt can be cleared.
            Config.sync.broadcast();
            // Wait with the lock released so attached callers can drain.
            while (self.attempt.?.waiters > 0) Config.sync.wait();
            self.attempt = null;
            // Wake callers waiting to start a retry.
            Config.sync.broadcast();
            Config.sync.unlock();

            return outcome;
        }

        /// Return the retained successful request, or null before a load succeeds.
        pub fn loadedSource(self: *const LoaderType) ?LoadSource {
            if (!Config.ready().isReady()) return null;
            return self.request.source();
        }

        /// Return success for the selected source or `ProviderMismatch`.
        fn accept(self: *const LoaderType, source: LoadSource) LoadError!void {
            // Read the request only after acquiring readiness.
            const published = self.request.source() orelse unreachable;
            if (eqlSource(published, source)) return;
            return error.ProviderMismatch;
        }

        /// Open, resolve, and validate without holding the loader lock.
        /// Close the candidate on every failure; this function never publishes.
        fn runAttempt(source: LoadSource) LoadError!void {
            const handle = platform.open(source) catch |err| return err;

            var retain = false;
            defer if (!retain) platform.close(handle);

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |_, index| {
                    Config.assignMissing(index, Config.tablePtr());
                }
            }

            inline for (Config.symbols, 0..) |symbol, index| {
                const address = platform.lookup(handle, symbol.name) orelse
                    return error.MissingSymbol;
                Config.assign(index, Config.tablePtr(), address);
            }

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |symbol, index| {
                    if (platform.lookup(handle, symbol.name)) |address| {
                        Config.assignOptional(index, Config.tablePtr(), address);
                    }
                }
            }

            if (@hasDecl(Config, "validate")) {
                if (Config.validate(Config.tablePtr())) |refusal| {
                    // Preserve the provider's validation reason in the refusal message.
                    std.debug.print("{s}: refusing this provider: {s}\n", .{
                        Config.library_name,
                        refusal,
                    });
                    return error.ValidationFailed;
                }
            }

            // Retain the handle because the published table points into it.
            retain = true;
        }
    };
}

/// State retained for one in-flight or undrained load attempt.
const Attempt = struct {
    /// Thread identity used to detect recursive loads.
    owner: u64,
    /// Written under the lock before readiness leaves `loading`; then read by waiters.
    result: LoadError!void = error.OpenFailed,
    /// Attached callers that must take their result before this attempt is cleared.
    waiters: usize = 0,
};

/// UTF-16 buffer bound; each accepted UTF-8 byte needs at most one code unit.
const windows_path_units = 32768;

const platform = if (builtin.target.os.tag == .windows)
    Windows
else if (supported_target)
    Unix
else
    NoLoader;

/// Refuse every load request on targets without a dynamic loader.
const NoLoader = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        _ = source;
        return error.UnsupportedTarget;
    }
    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        _ = handle;
        _ = name;
        return null;
    }
    fn close(handle: *anyopaque) void {
        _ = handle;
    }
};

/// Unix `dlopen`/`dlsym`/`dlclose` implementation.
const Unix = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        var buffer: [max_source_len + 1]u8 = undefined;
        @memcpy(buffer[0..text.len], text);
        buffer[text.len] = 0;
        // Resolve dependencies now and keep provider symbols out of the global namespace.
        return std.c.dlopen(
            // `dlopen` requires a sentinel-terminated name.
            buffer[0..text.len :0].ptr,
            .{ .NOW = true, .GLOBAL = false },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return std.c.dlsym(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = std.c.dlclose(handle);
    }
};

/// Minimal direct bindings to the Windows dynamic loader.
const kernel32 = struct {
    extern "kernel32" fn LoadLibraryExW(
        file_name: [*:0]const u16,
        file: ?*anyopaque,
        flags: u32,
    ) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(module: *anyopaque) callconv(.winapi) i32;
};

/// Windows `LoadLibraryExW`/`GetProcAddress`/`FreeLibrary` implementation.
const Windows = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget, SourceTooLong };

    /// Search default directories, not the current directory; explicit paths also search their DLL directory.
    const load_library_search_default_dirs: u32 = 0x0000_1000;
    const load_library_search_dll_load_dir: u32 = 0x0000_0100;

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        if (text.len > windows_path_units) return error.SourceTooLong;
        var buffer: [windows_path_units + 1]u16 = undefined;
        const units = std.unicode.utf8ToUtf16Le(buffer[0..text.len], text) catch
            return error.OpenFailed;
        buffer[units] = 0;
        return kernel32.LoadLibraryExW(
            buffer[0..units :0],
            null,
            load_library_search_default_dirs | switch (source) {
                .path => load_library_search_dll_load_dir,
                .system => @as(u32, 0),
            },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return kernel32.GetProcAddress(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = kernel32.FreeLibrary(handle);
    }
};
