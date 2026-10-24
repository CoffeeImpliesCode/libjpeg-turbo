# Changelog

- Export the 12- and 16-bit libjpeg APIs from ELF shared libraries for runtime loading.
- Fix runtime-loader compilation and reject providers that do not finish decompression.
- Fix runtime-provider error-manager pointers and initialization, fatal-message formatting, and compressor warning counts.
- Fix ELF shared-library export scripts and omit WASI from dynamic and runtime-loaded check matrices.
- Port to Zig 0.17.0.
- The nested consumer build keeps its own install prefix; Zig 0.17 exposes the outer prefix only at make time.
- Use `-Dconsumer-libc-runtimes=<path>` to supply libc runtimes to the nested consumer build.

- Added a Zig build of libjpeg-turbo 3.2.0's libjpeg API library with target-generated headers; SIMD, tools, arithmetic coding, and profiling are disabled.
