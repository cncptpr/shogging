{
  description = "Shogging";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nix-gleam = {
      url = "github:cncptpr/nix-gleam?ref=fix/local-packages";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-gleam,
      ...
    }:
    let
      forEachSystem = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    in
    {
      packages = forEachSystem (system: {
        default = self.packages.${system}.server;
        server = nix-gleam.packages.${system}.buildGleamApplication {
          src = ./server;
          localPackages = [ ./shogg ];
        };
      });
    };
}
