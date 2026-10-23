# Source-only derivation; build.zig owns compilation and installation.
#
# SPDX-License-Identifier: MIT
# See FORK-LICENSE.md for what that identifier covers, and NOTICE.md for the
# per-file inventory of the upstream material this package ships.

{ lib
, stdenv
, zig
, patchelf
  # Empty uses the build default; static and dynamic select linkage variants.
, linkage ? "static"
, optimize ? "ReleaseSafe"
}:

let
  requestedLinkage =
    if builtins.elem linkage [ "" "static" "dynamic" ] then linkage
    else throw "package.nix: linkage must be \"\", \"static\" or \"dynamic\", not ${toString linkage}";

# Exclude version-control, cache, environment and output directories; retain upstream sources and data.
src = lib.cleanSourceWith {
  src = ./.;
  filter = path: _type:
    let name = builtins.baseNameOf (toString path); in
    !(lib.elem name [
      ".git"
      ".direnv"
      ".devenv"
      ".zig-cache"
      "zig-cache"
      "zig-pkg"
      "zig-out"
      "result"
    ]);
};

# `patchelf` handles ELF only; omit it on Darwin.
isElfTarget = !stdenv.hostPlatform.isDarwin;
in

# Refuse cross builds; this derivation supports matching build and host systems only.
assert stdenv.buildPlatform.system == stdenv.hostPlatform.system;

stdenv.mkDerivation {
  pname = "libjpeg-turbo";
  version = "3.2.0";

  inherit src;

  strictDeps = true;
  dontPatch = true;

  # Use only the Zig install phase; avoid a separate build from the setup hook.
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ zig ] ++ lib.optional isElfTarget patchelf;

  # The library needs libc; zlib belongs to the excluded command-line tools.
  propagatedBuildInputs = [ stdenv.cc.libc ];

  doCheck = false;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Keep Zig caches under TMPDIR and preserve caller-provided paths.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"

    # build.zig owns the source list, generated headers, configuration and layout.
    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      -Dsimd=c \
      ${lib.optionalString (requestedLinkage != "") "-Dlinkage=${requestedLinkage}"}

    # Remove Zig-cache rpaths from ELF outputs but keep `$ORIGIN` and dependency paths.
    # Resolve symlinks first so SONAME links are not replaced by copies.
    ${lib.optionalString isElfTarget ''
      for elf in "$out"/bin/* "$out"/lib/*.so*; do
        [ -f "$elf" ] || continue
        elf=$(readlink -f "$elf")
        rpath=$(patchelf --print-rpath "$elf") || rpath=""
        kept=""
        rest=$rpath
        while [ -n "$rest" ]; do
          entry="''${rest%%:*}"
          case "$entry" in
            "$TMPDIR"/*) ;;
            *) if [ -z "$kept" ]; then kept=$entry; else kept=$kept:$entry; fi ;;
          esac
          if [ "$entry" = "$rest" ]; then rest=""; else rest="''${rest#*:}"; fi
        done
        [ "$kept" = "$rpath" ] || patchelf --set-rpath "$kept" "$elf"
      done
    ''}

    runHook postInstall
  '';

  # Both variants share the layout installed by build.zig; only the artifact differs.

  enableParallelBuilding = true;

  meta = {
    description = "libjpeg-turbo 3.2.0 JPEG codec (libjpeg API), built from the official release sources without SIMD";
    longDescription = ''
      The complete libjpeg-turbo 3.2.0 release source -- the libjpeg API
      library's 98 translation units, every internal header, the manuals, the
      test images, the SIMD sources and both licence texts -- compiled from the
      tarball's own src/ directory with Zig, with no CMake, no autotools and no
      build-time download. Ships the library, its four public headers and a
      pkg-config file.

      This is the portable C configuration: no SIMD is compiled on any target,
      because x86 SIMD is NASM assembly and this toolchain has no NASM, and the
      intrinsics families are selected upstream by configure-time capability
      probes this build does not reimplement. See UPSTREAM.md for the full
      boundary and FORK-NOTES.md entry 1. No command-line tools are built; see
      UPSTREAM.md, "The excluded command-line tools".
    '';
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
