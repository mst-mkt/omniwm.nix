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

      apps = forAllSystems (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          inherit (pkgs) lib;

          libTestFailures = lib.runTests (
            import ../nix/lib-tests.nix {
              # lib.nix warns on purpose for the inputs the tests pass it.
              omniwm = import ../nix/lib.nix {
                lib = lib // {
                  warn = _: value: value;
                };
              };
            }
          );

          app = description: drv: {
            type = "app";
            program = lib.getExe drv;
            meta = { inherit description; };
          };
        in
        {
          test = app "Run the lib and nushell tests" (
            lib.throwIf (libTestFailures != [ ])
              "lib tests failed:\n${lib.generators.toPretty { } libTestFailures}"
              (
                pkgs.writeShellApplication {
                  name = "omniwm-test";
                  runtimeInputs = [ pkgs.nushell ];
                  runtimeEnv.NU_LIB_DIRS = "${inputs.nutest}";
                  text = "nu -n -c 'use nutest; nutest run-tests --path scripts --fail'";
                }
              )
          );

          format = app "Format the repository" treefmtEval.${system}.config.build.wrapper;

          generate-defaults = app "Regenerate settings-defaults.toml (macOS with a matching Xcode)" (
            pkgs.writeShellApplication {
              name = "omniwm-generate-defaults";
              runtimeInputs = [ pkgs.nushell ];
              text = "nu codegen/generate-defaults.nu";
            }
          );
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
        in
        {
          treefmt = treefmtEval.${system}.config.build.check (pkgs.lib.cleanSource ./..);

          test =
            pkgs.runCommand "omniwm-tests"
              {
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
                ${inputs.self.apps.${system}.test.program}
                touch $out
              '';
        }
      );
    };
}
