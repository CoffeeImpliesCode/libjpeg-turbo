# Zig facade API

The facade wraps the libjpeg API in `zig/root.zig`. It owns JPEG objects and
checks buffer lengths; codec behavior remains in the C library.

## Raw declarations and constants

- `c` exposes the translated C declarations for callers who need an operation
  not wrapped by the facade.
- `runtime_loaded` is a compile-time `bool` describing this module's load mode.
- `libjpeg_api_version` is the compile-time `JPEG_LIB_VERSION` from the
  translated header. It does not identify a runtime provider.
- `message_length_max` is the size of a libjpeg error-message buffer.

## Loading types

`LoadSource` selects an explicit provider:

- `.path`: an absolute file path.
- `.system`: a library name searched by the platform loader.

The variants do not fall back to each other. `LoadError` includes
`EmptySource`, `SourceTooLong`, `InvalidSource`, `UnsupportedTarget`,
`OpenFailed`, `MissingSymbol`, `ValidationFailed`, `ProviderMismatch`, and
`ReentrantLoad`.

`load(source) LoadError!void` resolves and validates the provider in a
runtime-loaded build. The same request after success is a no-op; another
provider returns `ProviderMismatch`. A failed attempt can be retried explicitly.
The handle and a copy of the request remain for the process lifetime. There is
no unload or reset. Calling `load` in a linked build panics.

`loadedSource() ?LoadSource` returns the retained request, or `null` before a
successful load and in linked builds.

## Types and checked errors

- `ColorSpace` maps the C colorspaces: `unknown`, `grayscale`, `rgb`, `ycbcr`,
  `cmyk`, `ycck`, `rgb565`, and the `ext_*` RGB/BGR/alpha variants. `rgb565` is
  for decompression.
- `DctMethod` selects `islow`, `ifast`, or `float`; `islow` is upstream's default.
- `HeaderResult` represents `suspended`, `header_ok`, and `tables_only` results
  from `jpeg_read_header`.
- `Error` contains `NotAJpegImage`, `NotDecompressing`, `PrematureEnd`,
  `ShortWrite`, and `RowBufferTooSmall`.

The typed errors cover conditions the facade checks. Fatal libjpeg errors call
`std.debug.panic`; recoverable warnings are available through each object's
`warningCount()` and `lastWarning()`.

## `Decompress`

Initialize the object in place and keep it at a stable address. The JPEG input
slice is borrowed until `deinit`; do not free or mutate it while the object is
open.

- `init(bytes) Error!void` creates the decompressor, installs the memory source,
  and reads the header. A non-image header returns `NotAJpegImage`.
- `deinit()` destroys the object and its libjpeg allocations. Calling it again
  on the same value is a no-op.
- `isOpen()` reports whether the object is live. `handle()` returns its raw
  `Raw` pointer and panics if it is closed.
- `width()`, `height()`, `numComponents()`, `jpegColorSpace()`, and
  `outColorSpace()` read header fields.
- `requestOutColorSpace(space)` and `requestDctMethod(method)` set output
  parameters before `startDecompress()`.
- After `startDecompress()`, `outputWidth()`, `outputHeight()`,
  `outColorComponents()`, `outputComponents()`, `recommendedRowBufferHeight()`,
  `rowBytes()`, and `outputScanline()` describe decoded output.
- `readScanlines(out) Error!usize` decodes whole rows into `out` and returns the
  row count. The slice must hold at least one row.
- `readAll(buffer) Error!void` decodes the full image; `buffer` must hold
  `rowBytes() * outputHeight()` bytes.
- Call `finishDecompress()` when decoding is complete. `warningCount()` counts
  recoverable input warnings; `lastWarning()` returns the first warning text or
  `null`.

## `Compress`

Initialize in place and keep the object at a stable address. The object owns the
C-allocated compressed buffer; the facade takes no Zig allocator.

- `init(width, height, components)` creates the compressor and memory
  destination. Set `setInputColorSpace(space)` before `setDefaults()`.
- `setDefaults()` applies upstream defaults; `setQuality(quality,
  force_baseline)` sets the quality from 1 to 100.
- `startCompress()` begins compression. `writeScanlines(rows) Error!usize`
  writes whole rows of input samples and returns the row count.
- `finishCompress()` terminates the memory destination. `bytes()` returns a
  borrowed slice of the exact compressed length, with no terminator; it remains
  valid until the object is destroyed or another image is started.
- `deinit()` destroys the compressor and frees the compressed buffer.
  `isOpen()` reports its state; `handle()` returns the raw `Raw` pointer and
  panics if closed.
- `warningCount()` and `lastWarning()` report recoverable warnings as for
  `Decompress`.

Do not copy or move either object after `init`: libjpeg stores pointers to its
error manager and, for compression, to output fields in the object. Use each
object from one thread at a time.
