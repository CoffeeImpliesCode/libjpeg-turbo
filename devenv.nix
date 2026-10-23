# SPDX-License-Identifier: MIT

{ pkgs, ... }:

let
  # Share one Zig package between the assertion and shell tools.
  zig = pkgs.zig_0_16;

  libjpeg_turbo = linkage: pkgs.callPackage ./package.nix { … };

  # Resolve this checkout from the module path without copying it into the Nix store.
  sdk_root = builtins.toString ./.;

  # Preserve caller cache paths; otherwise use XDG_CACHE_HOME or TMPDIR.
  zig_caches = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        export ZIG_LOCAL_CACHE_DIR="$XDG_CACHE_HOME/libjpeg-turbo/zig-local-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        export ZIG_LOCAL_CACHE_DIR="$TMPDIR/libjpeg-turbo/zig-local-cache"
      fi
    fi
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        export ZIG_GLOBAL_CACHE_DIR="$XDG_CACHE_HOME/libjpeg-turbo/zig-global-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/libjpeg-turbo/zig-global-cache"
      fi
    fi
    if [ -n "''${ZIG_LOCAL_CACHE_DIR}" ]; then
      mkdir -p "$ZIG_LOCAL_CACHE_DIR"
    fi
    if [ -n "''${ZIG_GLOBAL_CACHE_DIR}" ]; then
      mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
    fi
  '';

  # Fail tasks that have no cache path outside the checkout.
  require_external_output = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR}" ]; then
      echo "libjpeg-turbo devenv: ZIG_LOCAL_CACHE_DIR, XDG_CACHE_HOME and TMPDIR are all unset," >&2
      echo "so there is nowhere outside this checkout to put build output." >&2
      echo "Export one of them at approved scratch, then run the task again." >&2
      exit 1
    fi
  '';

  # Run tasks from this checkout, not the caller's `--from` project.
  in_sdk = ''
    ${zig_caches}
    ${require_external_output}
    cd "${sdk_root}" || exit 1
  '';

  # Share native-build flags and append caller arguments last.
  native_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/native" "''$@"
  '';

  # Isolate the consumer cache from the library build.
  consumer_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/consumer" "''$@"
  '';

  # Pass the portable C-only SIMD setting explicitly.
  simd_flags = "-Dsimd=c";
in

{
  packages = [
    zig
    pkgs.gnumake
    pkgs.pkg-config
    pkgs.valgrind
  ];

  assertions = [
    {
      assertion = zig.version == "0.16.0";
      message = "The libjpeg-turbo SDK requires Zig 0.16.0; nixpkgs resolved zig_0_16 to ${zig.version}";
    }
  ];

  # Apply the cache rule in the shell without overriding caller paths.
  enterShell = ''
    ${zig_caches}
  '';

  # Outputs stay lazy; entering the shell does not build the SDK.
  outputs.static = libjpeg_turbo "static";
  outputs.shared = libjpeg_turbo "dynamic";
  outputs.default = libjpeg_turbo "static";

  tasks = {
    # Install both variants outside the checkout.
    "sdk:build" = {
      description = ''
        Compile the libjpeg API library (default step) and install the delivery
        tree under the external cache rather than in this checkout. Non-SIMD
        configuration, no command-line tools.
      '';
      exec = ''
        ${in_sdk}
        zig build --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/static" ${simd_flags} ${native_flags}
      '';
    };

    "sdk:build:shared" = {
      description = ''
        Compile the library as libjpeg.so.62.4.0 instead of an archive, and
        install it under its own external prefix.
      '';
      exec = ''
        ${in_sdk}
        zig build -Dlinkage=dynamic --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/dynamic" ${simd_flags} ${native_flags}
      '';
    };

    # Test and check tasks need a cache but do not install outputs.
    "sdk:test" = {
      description = "Run the behavioural tests";
      exec = ''
        ${in_sdk}
        zig build test ${simd_flags} ${native_flags}
      '';
    };

    "sdk:test:release-safe" = {
      description = "Run the behavioural tests in ReleaseSafe";
      exec = ''
        ${in_sdk}
        zig build test -Doptimize=ReleaseSafe ${simd_flags} ${native_flags}
      '';
    };

    "sdk:smoke" = {
      description = "Run the deterministic example";
      exec = ''
        ${in_sdk}
        zig build smoke ${simd_flags} ${native_flags}
      '';
    };

    "sdk:check" = {
      description = "Compile and link every public entry point for the six compile-only targets without running any of them";
      exec = ''
        ${in_sdk}
        zig build check ${simd_flags} ${native_flags}
      '';
    };

    "sdk:check:shared" = {
      description = "The same six-target compile check against the shared object";
      exec = ''
        ${in_sdk}
        zig build check -Dlinkage=dynamic ${simd_flags} ${native_flags}
      '';
    };

    # Build and run the separate consumer through its relative path dependency.
    "sdk:consumer" = {
      description = "Build and run the separate consumer package against this SDK";
      exec = ''
        ${in_sdk}
        cd consumer
        zig build run ${simd_flags} ${consumer_flags}
      '';
    };

    # Run the provenance check from the checkout described by UPSTREAM.sha256.
    "sdk:provenance" = {
      description = ''
        Check the 613 recorded upstream digests, the exact native file set, the
        preserved upstream README bytes, all four licence notices and the four
        fixture digests. This is a source-integrity check, not a build gate.
      '';
      exec = ''
        ${in_sdk}
        bash tools/check-provenance.sh
      '';
    };

    # Package tasks use the caller's devenv project and write only to the Nix store.
    "sdk:package:static" = {
      description = ''
        Build the static Nix variant through devenv's own lazy output. No lock
        is needed by this path; `devenv build outputs.static` resolves the
        pinned input from devenv.lock, which the driver owns.
      '';
      exec = "devenv build outputs.static";
    };

    "sdk:package:shared" = {
      description = "Build the shared Nix variant through devenv's own lazy output";
      exec = "devenv build outputs.shared";
    };
  };
}
