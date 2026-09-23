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

  preservedNames = builtins.filter (name: name != "schemaVersion") cfg.preserveSettings;
  preservedPaths = map (lib.splitString ".") preservedNames;
  # OmniWM leaves out the `monitors` table when `ranking` is empty, so the template has no such key.
  unknownPreservedPaths = builtins.filter (
    name: name != "monitors" && !(lib.hasAttrByPath (lib.splitString "." name) defaultSettings)
  ) preservedNames;
  declaredPreservedPaths = builtins.filter (
    name: lib.hasAttrByPath (lib.splitString "." name) userSettings
  ) preservedNames;
in

{
  disabledModules = [ "programs/omniwm.nix" ];

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
      {
        assertion = cfg.settings == null || preservedNames == [ ] || cfg.mutableSettings;
        message = ''
          programs.omniwm: preserveSettings requires mutableSettings = true.
          With mutableSettings = false, settings.toml is a read-only symlink into the Nix store, so OmniWM never persists the values you are asking to preserve.'';
      }
      {
        assertion = unknownPreservedPaths == [ ];
        message = ''
          programs.omniwm: preserveSettings contains paths unknown to OmniWM ${
            cfg.package.version or "unknown"
          }: ${lib.concatStringsSep ", " unknownPreservedPaths}.
          See settings-defaults.toml in the omniwm.nix flake for the known keys.'';
      }
      {
        assertion = cfg.settings == null || declaredPreservedPaths == [ ];
        message = ''
          programs.omniwm: preserveSettings and settings both set ${lib.concatStringsSep ", " declaredPreservedPaths}.
          A preserved path is taken from the file OmniWM has, so the declared value would only survive until OmniWM first writes it. Set it in one of the two.'';
      }
    ];

    warnings =
      lib.optional (cfg.settings == null && preservedNames != [ ])
        "programs.omniwm: preserveSettings has no effect while settings is null, because the settings file is left unmanaged and nothing overwrites it."
      ++
        lib.optional (cfg.settings != null && userSettings ? schemaVersion)
          "programs.omniwm: settings.schemaVersion is set, but it is managed by OmniWM (schema migrations) and will be ignored. Remove it from your settings."
      ++
        lib.optional (cfg.settings != null && userSettings ? monitorRoutingOverrides)
          "programs.omniwm: settings.monitorRoutingOverrides was removed in OmniWM 0.6.9 (settings schema 3) and will be ignored. Move the entries to settings.routing.arrangements.";

    home.packages = [ cfg.package ];

    xdg.configFile."omniwm/settings.toml" = lib.mkIf (cfg.settings != null && !cfg.mutableSettings) {
      source = settingsFile;
    };

    # OmniWM rewrites the file at startup, so deploy a writable copy.
    # The launchd-started app never sees shell exports, so avoid $XDG_CONFIG_HOME.
    home.activation.omniwmSettings = lib.mkIf (cfg.settings != null && cfg.mutableSettings) (
      # Run after linkGeneration so a store symlink from mutableSettings = false is already removed.
      lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
        omniwmSettings="${config.xdg.configHome}/omniwm/settings.toml"
        settingsSource="${settingsFile}"
        ${
          # Referring to nushell only here keeps it out of the closure when nothing is preserved.
          lib.optionalString (preservedPaths != [ ]) ''
            settingsSource="$(mktemp)"
            ${lib.getExe pkgs.nushell} ${./preserve-settings.nu} \
              ${settingsFile} "$omniwmSettings" "$settingsSource" \
              ${lib.escapeShellArg (builtins.toJSON preservedPaths)}
          ''
        }
        if ! cmp -s "$settingsSource" "$omniwmSettings"; then
          run mkdir -p "$(dirname "$omniwmSettings")"
          # install unlinks the destination first, so a symlinked .bak never has its target overwritten.
          if [[ -e "$omniwmSettings" ]]; then
            run install -T -m 644 "$omniwmSettings" "$omniwmSettings.bak"
          fi
          # OmniWM reloads on every change without debounce, so replace the file atomically.
          run install -T -m 644 "$settingsSource" "$omniwmSettings.tmp"
          run mv -fT "$omniwmSettings.tmp" "$omniwmSettings"
        fi
        ${lib.optionalString (preservedPaths != [ ]) ''rm -f "$settingsSource"''}
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
