# Source-only package derivation for the libjpeg-turbo SDK.
#
# One file, consumed by both flake.nix and devenv.nix, so the two entry points
# cannot describe different packages. It builds nothing but this repository: the
# native source is upstream's `src/`, which is the complete libjpeg-turbo 3.2.0
# release tree imported whole from the release tarball, and build.zig owns every
# compile flag, every generated header, the source list and the whole installed
# layout. Nothing here restates a C flag, fetches a tarball, reaches into a
# sibling checkout, or installs an artifact of its own. The one edit it makes is
# the rpath of the ELF files the build installed: Zig records its own build cache
# there, and that directory does not exist once a binary is installed.
#
# No SIMD is compiled and no command-line tool is installed; see UPSTREAM.md.
# Both are upstream configuration decisions recorded there, not omissions here,
# and `build.zig`'s `-Dsimd` accepts only `c`.
#
# No lock file is written here. `flake.lock` and `devenv.lock` belong to the
# driver.
#
# SPDX-License-Identifier: MIT
# See FORK-LICENSE.md for what that identifier covers, and NOTICE.md for the
# per-file inventory of the upstream material this package ships.

{ lib
, stdenv
, zig
, patchelf
  # Zig's own `std.builtin.LinkMode` spelling, passed straight through as
  # `-Dlinkage`. "static" and "dynamic" are two variants of one derivation, and
  # `""` passes nothing at all so the SDK's own default policy runs unchanged.
  # Upstream's own build produces both libjpeg.a and libjpeg.so; static is this
  # fork's default and `.shared` is the separate variant.
, linkage ? "static"
, optimize ? "ReleaseSafe"
}:

let
  requestedLinkage =
    if builtins.elem linkage [ "" "static" "dynamic" ] then linkage
    else throw "package.nix: linkage must be \"\", \"static\" or \"dynamic\", not ${toString linkage}";

# Everything except build outputs, version control and developer-tool state.
# Filtering by directory name rather than by an allow list means a file added
# here later is packaged without editing this file, while `.zig-cache/`,
# `zig-out/`, `.devenv/`, `.direnv/` and `result` stay out of a published output
# at any depth, including under consumer/. The upstream manuals, man pages,
# test images, SIMD sources, both CMake trees and every licence text are
# deliberately kept: they are upstream material with digests in UPSTREAM.sha256,
# and the audit surface is the whole upstream tree even though only 98 of its
# C units are compiled.
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

# patchelf rewrites ELF rpaths and does not read Mach-O, so the rpath
# normalisation in the install phase exists for ELF targets only, and the tool is
# a build input exactly where that code runs.
isElfTarget = !stdenv.hostPlatform.isDarwin;
in

# These packages build for the compiler's own native target. A cross build here
# would mean hand-building a libc-suffixed triple that has to track nixpkgs, so
# this derivation refuses one instead of silently producing a host-architecture
# library under a foreign name. The comparison is against stdenv's own
# platforms, which are pure values; `builtins.currentSystem` is not evaluable
# in a sandbox and is not used. A remote builder is unaffected: this compares
# build against host, not against any particular machine.
assert stdenv.buildPlatform.system == stdenv.hostPlatform.system;

stdenv.mkDerivation {
  pname = "libjpeg-turbo";
  version = "3.2.0";

  inherit src;

  strictDeps = true;
  dontPatch = true;

  # The real work is one `zig build install` in installPhase below. Disabling
  # configure and build phases keeps the Zig setup hook from running a first,
  # differently-flagged build of its own; `dontInstall` is deliberately NOT set,
  # because that is what would disable the real install phase.
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ zig ] ++ lib.optional isElfTarget patchelf;

  # The libjpeg API library's entire dependency closure is the C library. It is
  # not the zlib the command-line tools need: those are gated by WITH_TOOLS and
  # are not built (UPSTREAM.md). Nothing else is propagated, and in particular no
  # third-party library from anywhere on the system is.
  propagatedBuildInputs = [ stdenv.cc.libc ];

  # The driver owns every gate for this SDK, and a Nix build is not a
  # verification receipt. No check phase is declared here rather than a check
  # phase that runs something smaller than the real gates; the commands that do
  # verify this package are in README.md and CHANGELOG.md.
  doCheck = false;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Both caches go under the Nix-provided TMPDIR, outside the unpacked source
    # tree, so a build cannot write into $src and so two parallel derivations
    # cannot share state. Any caller-supplied cache variables are left alone:
    # they are the caller's scratch, not this file's to clear.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"

    # build.zig owns the source list (the 98 units of JPEG_SOURCES at
    # src/CMakeLists.txt:653-690), the generated jconfig.h, jconfigint.h and
    # jversion.h, the non-SIMD configuration, the pkg-config file and every
    # installed path. Declaring any of them here as well would create a second
    # place where they can disagree with the build graph.
    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      -Dsimd=c \
      ${lib.optionalString (requestedLinkage != "") "-Dlinkage=${requestedLinkage}"}

    # Zig records the build cache in the rpath of anything that links a dynamic
    # artifact it has just built (lib/std/Build/Step/Compile.zig:1192-1199), so
    # an installed binary names a directory that is gone, and Nix rejects an
    # installed file that names its build directory at all. Both Zig caches above
    # are under $TMPDIR, so dropping those entries and no other removes it: the
    # $ORIGIN/../lib build.zig adds, and every store path a real dependency
    # needs, stay. Symlinks are resolved first so the libjpeg.so.62 soname link
    # is rewritten through to the object and never replaced by a copy of it.
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

  # The layout this derivation produces is the build graph's, not this file's:
  # $out/lib/libjpeg.a (or libjpeg.so.62.4.0 with the libjpeg.so.62 soname
  # link), $out/include/{jconfig,jerror,jmorecfg,jpeglib}.h as upstream installs
  # them at src/CMakeLists.txt:2065-2069, $out/lib/pkgconfig/libjpeg.pc, and
  # $out/share/licenses/libjpeg-turbo/ carrying README.ijg, src/LICENSE.md and
  # this fork's records. Both variants keep it; only the artifact kind differs.
  # Nothing is copied or generated by hand here, so
  # `zig build install --prefix $out` and `nix build` produce one layout by
  # construction rather than two that have to be kept in agreement.

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
