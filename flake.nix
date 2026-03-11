{
  description = "Shopify Hydrogen - Nix development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        nodejs = pkgs.nodejs_22;
        pnpm = pkgs.pnpm_10;

        # Libraries needed by dynamically linked npm binaries (workerd, etc.)
        runtimeLibs = with pkgs; [
          stdenv.cc.cc.lib   # libatomic, libstdc++, libgcc_s
          glibc              # libc, libm, librt, libpthread, libdl
        ];

        # The dynamic linker from nixpkgs (e.g. /nix/store/.../ld-linux-x86-64.so.2)
        dynamicLinker = "${pkgs.stdenv.cc}/nix-support/dynamic-linker";
        libPath = pkgs.lib.makeLibraryPath runtimeLibs;
      in
      {
        devShells.default = pkgs.mkShell {
          name = "hydrogen-dev";

          buildInputs = [
            nodejs
            pnpm
            pkgs.git
            pkgs.patchelf
          ];

          shellHook = ''
            # NixOS compat: set NIX_LD for programs that support nix-ld.
            # We do NOT set LD_LIBRARY_PATH globally because it causes ABI
            # conflicts when npm/pnpm spawn child processes. Instead, native
            # binaries get their RPATH fixed via patchelf below.
            export NIX_LD="$(cat ${dynamicLinker})"
            export NIX_LD_LIBRARY_PATH="${libPath}''${NIX_LD_LIBRARY_PATH:+:$NIX_LD_LIBRARY_PATH}"

            # workerd (used by MiniOxygen) needs to find TLS root certificates.
            # On NixOS the default paths are not where workerd expects them.
            export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

            # Patch dynamically linked npm/node_modules binaries for NixOS.
            # npm packages like workerd ship pre-built ELF binaries that reference
            # /lib64/ld-linux-x86-64.so.2 — which on NixOS is only a stub.
            # This patches them in-place so they use the Nix store's dynamic linker.
            _patch_npm_bins() {
              local interp
              interp="$(cat ${dynamicLinker})"
              local rpath="${libPath}"

              find "$1" -type f -executable 2>/dev/null | while read -r bin; do
                # Only patch ELF files that request the generic linux interpreter
                if readelf -l "$bin" 2>/dev/null | grep -q 'Requesting program interpreter: /lib64/ld-linux'; then
                  patchelf --set-interpreter "$interp" --set-rpath "$rpath" "$bin" 2>/dev/null \
                    && echo "  patched: $bin"
                fi
              done
            }

            # Auto-patch all node_modules directories (including pnpm store at .pnpm/)
            for nm_dir in node_modules hydrogen-quickstart/node_modules; do
              if [ -d "$nm_dir" ]; then
                echo "🔧 Scanning $nm_dir for npm native binaries to patch..."
                _patch_npm_bins "$nm_dir"
              fi
            done

            echo "Hydrogen dev shell"
            echo "  Node.js $(node --version)"
            echo "  pnpm $(pnpm --version)"
          '';
        };
      }
    );
}
