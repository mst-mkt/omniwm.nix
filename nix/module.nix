{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.omniwm;
  tomlFormat = pkgs.formats.toml { };

  # OmniWM rejects partial settings files, so user settings are merged over the full defaults template.
  defaultSettings = fromTOML (builtins.readFile ../settings-defaults.toml);

  # Read derivations (writeText etc.) as files, not as attrsets.
  userSettings =
    if builtins.isAttrs cfg.settings && !lib.isDerivation cfg.settings then
      cfg.settings
    else
      fromTOML (builtins.readFile cfg.settings);

  # OmniWM requires the full list of known hotkey ids, so merge per id.
  userHotkeys = userSettings.hotkeys or [ ];
  hotkeysWithoutId = map (
    hotkey: if builtins.isString (hotkey.binding or null) then hotkey.binding else "(no binding)"
  ) (builtins.filter (hotkey: !(hotkey ? id)) userHotkeys);
  knownHotkeyIds = map (hotkey: hotkey.id) defaultSettings.hotkeys;
  unknownHotkeyIds = map (hotkey: hotkey.id) (
    builtins.filter (hotkey: hotkey ? id && !(builtins.elem hotkey.id knownHotkeyIds)) userHotkeys
  );
  mergedHotkeys = map (
    default:
    let
      override = lib.findFirst (hotkey: hotkey.id == default.id) null userHotkeys;
    in
    if override == null then default else default // override
  ) defaultSettings.hotkeys;

  # hotkeys are merged above; schemaVersion always comes from the template.
  userOverrides = removeAttrs userSettings [
    "hotkeys"
    "schemaVersion"
  ];
  mergedSettings = lib.recursiveUpdate defaultSettings userOverrides // {
    hotkeys = mergedHotkeys;
  };

  settingsFile = tomlFormat.generate "omniwm-settings.toml" mergedSettings;
in

{
  options.programs.omniwm = {
    enable = lib.mkEnableOption "OmniWM";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
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

        See <https://github.com/BarutSRB/OmniWM> for available options.
      '';
    };

    mutableSettings = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Whether {file}`settings.toml` is deployed as a writable copy that OmniWM can update, instead of a read-only symlink into the Nix store.

        When true, changes made at runtime (GUI, monitor overrides) are overwritten on the next activation and the previous file is kept as {file}`settings.toml.bak`.

        When false, OmniWM reports a persistent "Settings writes blocked" health warning and cannot persist runtime state or schema migrations.
      '';
    };

    launchd = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to manage OmniWM with a launchd agent.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "programs.omniwm" pkgs lib.platforms.darwin)
      {
        assertion = cfg.settings == null || hotkeysWithoutId == [ ];
        message = ''
          programs.omniwm: some settings.hotkeys entries have no `id`: ${lib.concatStringsSep ", " hotkeysWithoutId}.
          Hotkeys are matched to OmniWM's defaults by id; see settings-defaults.toml in the omniwm.nix flake for the known ids.'';
      }
      {
        assertion = cfg.settings == null || unknownHotkeyIds == [ ];
        message = ''
          programs.omniwm: settings.hotkeys contains ids unknown to OmniWM ${
            cfg.package.version or "unknown"
          }: ${lib.concatStringsSep ", " unknownHotkeyIds}.
          OmniWM rejects the entire settings file when it contains unknown hotkey ids; see settings-defaults.toml in the omniwm.nix flake for the known ids.'';
      }
    ];

    warnings = lib.mkIf (cfg.settings != null && userSettings ? schemaVersion) [
      "programs.omniwm: settings.schemaVersion is set, but it is managed by OmniWM (schema migrations) and will be ignored. Remove it from your settings."
    ];

    home.packages = [ cfg.package ];

    xdg.configFile."omniwm/settings.toml" = lib.mkIf (cfg.settings != null && !cfg.mutableSettings) {
      source = settingsFile;
    };

    # OmniWM rewrites the file at startup, so deploy a writable copy.
    # The launchd-started app never sees shell exports, so avoid $XDG_CONFIG_HOME.
    home.activation.omniwmSettings = lib.mkIf (cfg.settings != null && cfg.mutableSettings) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        omniwmSettings="${config.xdg.configHome}/omniwm/settings.toml"
        if ! cmp -s ${settingsFile} "$omniwmSettings"; then
          run install -D -m 644 -b -S .bak ${settingsFile} "$omniwmSettings"
        fi
      ''
    );

    launchd.agents.omniwm = {
      inherit (cfg.launchd) enable;
      config = {
        Program = "${cfg.package}/Applications/OmniWM.app/Contents/MacOS/OmniWM";
        KeepAlive = lib.mkDefault { SuccessfulExit = false; };
        RunAtLoad = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/omniwm.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/omniwm.err.log";
      };
    };
  };
}
