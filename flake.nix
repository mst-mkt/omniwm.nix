{
  description = "Nix flake for OmniWM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    inputs:
    let
      omniwm = inputs.nixpkgs.legacyPackages.aarch64-darwin.callPackage ./nix/package.nix { };
    in
    {
      packages.aarch64-darwin = {
        inherit omniwm;
        default = omniwm;
      };

      overlays.default = final: _: {
        omniwm = final.callPackage ./nix/package.nix { };
      };

      homeManagerModules.default = ./nix/module.nix;

      lib = import ./nix/lib.nix { inherit (inputs.nixpkgs) lib; };
    };
}
