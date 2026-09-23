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

    nutest = {
      url = "github:vyadh/nutest/v1.2.0";
      flake = false;
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

      devShells = forAllSystems (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              treefmtEval.${system}.config.build.wrapper
              pkgs.nushell
            ]
            ++ preCommit.${system}.enabledPackages;
            env.NU_LIB_DIRS = "${inputs.nutest}";
            inherit (preCommit.${system}) shellHook;
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
        in
        {
          treefmt = treefmtEval.${system}.config.build.check (pkgs.lib.cleanSource ./..);

          lib =
            let
              inherit (pkgs) lib;
              failures = lib.runTests (
                import ../nix/lib-tests.nix { omniwm = import ../nix/lib.nix { inherit lib; }; }
              );
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

          nu =
            pkgs.runCommand "omniwm-nu-tests"
              {
                nativeBuildInputs = [ pkgs.nushell ];
                NU_LIB_DIRS = "${inputs.nutest}";
                src = pkgs.lib.fileset.toSource {
                  root = ./..;
                  fileset = pkgs.lib.fileset.unions [
                    ../scripts
                    ../settings-defaults.toml
                  ];
                };
              }
              ''
                cd "$src"
                nu -n -c 'use nutest; nutest run-tests --path scripts --fail'
                touch $out
              '';
        }
      );
    };
}
