{
  config,
  options,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.omniwm;
  tomlFormat = pkgs.formats.toml { };
  settingsLib = import ./settings.nix { inherit lib; };

  # userSettings reads cfg.settings, so check its results only while this holds.
  managed = cfg.settings != null;

  defaultSettings = fromTOML (builtins.readFile ../../settings-defaults.toml);

  # Read derivations (writeText etc.) as files, not as attrsets.
  userSettings =
    if builtins.isAttrs cfg.settings && !lib.isDerivation cfg.settings then
      cfg.settings
    else
      fromTOML (builtins.readFile cfg.settings);

  hotkeys = settingsLib.hotkeys defaultSettings.hotkeys (userSettings.hotkeys or [ ]);
  mergedSettings = settingsLib.merge defaultSettings userSettings;

  settingsFile = tomlFormat.generate "omniwm-settings.toml" mergedSettings;
  # Given a .toml file, nushell's `to toml` edits that file instead of writing the record afresh, and keeps its spacing (`[[monitorGapOverrides ]]`).
  settingsJson = pkgs.writeText "omniwm-settings.json" (builtins.toJSON mergedSettings);
  deploySettings = pkgs.writers.writeNu "omniwm-deploy-settings" ../../scripts/deploy-settings.nu;

  preserved = settingsLib.preserved defaultSettings userSettings cfg.preserveSettings;
in

{
  disabledModules = [ "programs/omniwm.nix" ];

  options.programs.omniwm = {
    enable = lib.mkEnableOption "OmniWM";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../package.nix { }";
      description = "The OmniWM package to use.";
    };

    settings = lib.mkOption {
      type = with lib.types; nullOr (either path (attrsOf tomlFormat.type));
      default = null;
      example = lib.literalExpression ''
        {
          general = {
            updateChecksEnabled = false;
          };
          niri = {
            visibleContainerCount = 3;
          };
          hotkeys = [
            {
              id = "focus.left";
              binding = "Option+H";
            }
          ];
        }
      '';
      description = ''
        OmniWM settings written to {file}`$XDG_CONFIG_HOME/omniwm/settings.toml`.

        Can be either an attribute set (serialized to TOML) or a path to an existing TOML file.

        The given settings are deep-merged over the complete built-in defaults of the packaged OmniWM version, because OmniWM rejects a settings file that does not contain its full schema.
        Entries in `hotkeys` are merged per `id`; other lists (`workspaces`, `appRules`, monitor overrides) replace the defaults wholesale.

        When `null` (the default), the settings file is not managed and can be edited freely via the GUI.

        See <https://github.com/OmniNull/OmniWM> for available options.
      '';
    };

    preserveSettings = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      example = [
        "monitorGapOverrides"
        "monitors"
        "routing"
        "shellPermissions"
        "workspaceBar.iconOverrides"
      ];
      description = ''
        Settings that OmniWM owns at runtime, as dot-separated paths into {file}`settings.toml`.

        The whole file is regenerated on every activation, so a value set in the GUI is replaced by the built-in default.
        Each path listed here is read out of the file OmniWM currently has and layered back over the generated one instead.

        A path the current file does not hold keeps the built-in default, as on the first activation.
      '';
    };

    mutableSettings = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Whether {file}`settings.toml` is deployed as a writable copy that OmniWM can update, instead of a read-only symlink into the Nix store.

        When true, changes made at runtime (GUI, monitor overrides) are overwritten on the next activation, except for the paths listed in `preserveSettings`.
        The file is replaced only when its settings values differ from the generated ones, and the previous file is then kept as {file}`settings.toml.bak`.

        When false, OmniWM reports a persistent "Settings writes blocked" health warning and cannot persist runtime state or schema migrations.
      '';
    };

    launchd = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to manage OmniWM with a launchd agent.";
      };

      keepAlive = lib.mkOption {
        type =
          ((options.launchd.agents.type.getSubOptions [ ]).config.type.getSubOptions [ ]).KeepAlive.type;
        default = {
          SuccessfulExit = false;
        };
        example = true;
        description = "launchd's `KeepAlive` key for the agent.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "programs.omniwm" pkgs lib.platforms.darwin)
      {
        assertion = !managed || hotkeys.withoutId == [ ];
        message = ''
          programs.omniwm: some settings.hotkeys entries have no `id`: ${lib.concatStringsSep ", " hotkeys.withoutId}.
          Hotkeys are matched to OmniWM's defaults by id; see settings-defaults.toml in the omniwm.nix flake for the known ids.'';
      }
      {
        assertion = !managed || hotkeys.unknownIds == [ ];
        message = ''
          programs.omniwm: settings.hotkeys contains ids unknown to OmniWM ${
            cfg.package.version or "unknown"
          }: ${lib.concatStringsSep ", " hotkeys.unknownIds}.
          OmniWM rejects the entire settings file when it contains unknown hotkey ids; see settings-defaults.toml in the omniwm.nix flake for the known ids, plus ids built from a workspace number or a name of letters, digits, `.`, `_` and `-`, such as `switchWorkspace.9` for workspace 10 and `openApp.<bundle id>`.'';
      }
      {
        assertion = !managed || preserved.paths == [ ] || cfg.mutableSettings;
        message = ''
          programs.omniwm: preserveSettings requires mutableSettings = true.
          With mutableSettings = false, settings.toml is a read-only symlink into the Nix store, so OmniWM never persists the values you are asking to preserve.'';
      }
      {
        assertion = preserved.unknown == [ ];
        message = ''
          programs.omniwm: preserveSettings contains paths unknown to OmniWM ${
            cfg.package.version or "unknown"
          }: ${lib.concatStringsSep ", " preserved.unknown}.
          See settings-defaults.toml in the omniwm.nix flake for the known keys.'';
      }
      {
        assertion = !managed || preserved.declared == [ ];
        message = ''
          programs.omniwm: preserveSettings and settings both set ${lib.concatStringsSep ", " preserved.declared}.
          A preserved path is taken from the file OmniWM has, so the declared value would only survive until OmniWM first writes it. Set it in one of the two.'';
      }
    ];

    warnings =
      lib.optional (!managed && preserved.paths != [ ])
        "programs.omniwm: preserveSettings has no effect while settings is null, because the settings file is left unmanaged and nothing overwrites it."
      ++
        lib.optional (managed && userSettings ? schemaVersion)
          "programs.omniwm: settings.schemaVersion is set, but it is managed by OmniWM (schema migrations) and will be ignored. Remove it from your settings."
      ++
        lib.optional (managed && userSettings ? monitorRoutingOverrides)
          "programs.omniwm: settings.monitorRoutingOverrides was removed in OmniWM 0.6.9 (settings schema 3) and will be ignored. Move the entries to settings.routing.arrangements."
      ++ lib.optionals managed (
        map (
          rename:
          "programs.omniwm: the hotkey id `${rename.from}` in settings.hotkeys has been renamed to `${rename.to}`."
        ) hotkeys.renamed
      );

    home.packages = [ cfg.package ];

    xdg.configFile."omniwm/settings.toml" = lib.mkIf (managed && !cfg.mutableSettings) {
      source = settingsFile;
    };

    # OmniWM rewrites the file at startup, so deploy a writable copy.
    # The launchd-started app never sees shell exports, so avoid $XDG_CONFIG_HOME.
    home.activation.omniwmSettings = lib.mkIf (managed && cfg.mutableSettings) (
      # Run after linkGeneration so a store symlink from mutableSettings = false is already removed.
      lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
        ${deploySettings} ''${DRY_RUN:+--dry-run} \
          ${settingsFile} ${settingsJson} ${lib.escapeShellArg "${config.xdg.configHome}/omniwm/settings.toml"} \
          ${lib.escapeShellArg (builtins.toJSON preserved.paths)}
      ''
    );

    launchd.agents.omniwm = {
      inherit (cfg.launchd) enable;
      config = {
        Program = "${cfg.package}/Applications/OmniWM.app/Contents/MacOS/OmniWM";
        KeepAlive = lib.mkDefault cfg.launchd.keepAlive;
        RunAtLoad = true;
        EnvironmentVariables.XDG_CONFIG_HOME = config.xdg.configHome;
        StandardOutPath = lib.mkDefault "${config.home.homeDirectory}/Library/Logs/omniwm.log";
        StandardErrorPath = lib.mkDefault "${config.home.homeDirectory}/Library/Logs/omniwm.err.log";
      };
    };
  };
}
