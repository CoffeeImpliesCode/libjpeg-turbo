# Changelog

- Port to Zig 0.17.0.
- The nested consumer build keeps its own install prefix; a top-level custom `--prefix` does not apply to it.
- Use `-Dconsumer-libc-runtimes=<path>` to supply libc runtimes to the nested consumer build.

- Added a Zig build of libjpeg-turbo 3.2.0's libjpeg API library with target-generated headers; SIMD, tools, arithmetic coding, and profiling are disabled.
