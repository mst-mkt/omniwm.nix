{
  description = "development environment for omniwm.nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      forAllSystems = inputs.nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      treefmtEval = forAllSystems (
        system:
        inputs.treefmt-nix.lib.evalModule inputs.nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";

          programs = {
            nixfmt.enable = true;
            deadnix.enable = true;
            statix.enable = true;
            oxfmt.enable = true;
            swift-format.enable = true;
          };
        }
      );

      preCommit = forAllSystems (
        system:
        inputs.git-hooks.lib.${system}.run {
          src = ./..;
          hooks.treefmt = {
            enable = true;
            package = treefmtEval.${system}.config.build.wrapper;
          };
        }
      );
    in
    {
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      devShells = forAllSystems (system: {
        default = inputs.nixpkgs.legacyPackages.${system}.mkShellNoCC {
          packages = [ treefmtEval.${system}.config.build.wrapper ] ++ preCommit.${system}.enabledPackages;
          inherit (preCommit.${system}) shellHook;
        };
      });

      checks = forAllSystems (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
        in
        {
          treefmt = treefmtEval.${system}.config.build.check (pkgs.lib.cleanSource ./..);
        }
      );
    };
}
