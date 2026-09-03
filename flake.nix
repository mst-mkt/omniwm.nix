{
  description = "Nix flake for OmniWM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    inputs:
    let
      inherit (inputs.nixpkgs) lib;
      pkgs = inputs.nixpkgs.legacyPackages.aarch64-darwin;

      omniwm = pkgs.callPackage ./nix/package.nix { };
      omniwmLib = import ./nix/lib.nix { inherit lib; };
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

      lib = omniwmLib;

      checks.aarch64-darwin.lib =
        let
          failures = lib.runTests (import ./nix/lib-tests.nix { omniwm = omniwmLib; });
        in
        pkgs.runCommand "omniwm-lib-tests" { } (
          if failures == [ ] then
            "touch $out"
          else
            ''
              echo ${lib.escapeShellArg (lib.generators.toPretty { } failures)} >&2
              exit 1
            ''
        );
    };
}
