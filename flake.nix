{
  description = "Input Usage Monitor — Linux evdev key statistics aggregator in Zig";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zig
            zls
          ];

          shellHook = ''
            echo "🔧 Input Usage Monitor dev environment loaded"
            echo "   Zig: $(zig version)"
            echo "   Build: zig build"
            echo "   Run:   sudo ./zig-out/bin/input-monitor"
          '';
        };
      }
    );
}
