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
      in
      {
        devShells.default = pkgs.mkShell {
          name = "hydrogen-dev";

          buildInputs = [
            nodejs
            pnpm
            pkgs.git
          ];

          shellHook = ''
            echo "Hydrogen dev shell"
            echo "  Node.js $(node --version)"
            echo "  pnpm $(pnpm --version)"
          '';
        };
      }
    );
}
