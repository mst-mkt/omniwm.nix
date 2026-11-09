{ lib }:

let
  # Hand-written from OmniWM's source, so recheck them whenever settings-defaults.toml is regenerated.

  # OmniWM's own migration renames these, but never runs because schemaVersion comes from the template.
  renamedHotkeyIds = {
    "setContainerPrimarySpan.decrease10Percent" = "resizeContainerPrimarySpan.shrink";
    "setContainerPrimarySpan.increase10Percent" = "resizeContainerPrimarySpan.grow";
    "setWindowPrimarySpan.decrease10Percent" = "resizeWindowPrimarySpan.shrink";
    "setWindowPrimarySpan.increase10Percent" = "resizeWindowPrimarySpan.grow";
    "setWindowSecondarySpan.decrease10Percent" = "resizeWindowSecondarySpan.shrink";
    "setWindowSecondarySpan.increase10Percent" = "resizeWindowSecondarySpan.grow";
  };

  # `switchWorkspace.9` is workspace 10; `.0` to `.8` are in the template.
  # Narrower than OmniWM's own checks, because OmniWM rejects the entire settings file over a single invalid id.
  dynamicHotkeyIdPatterns = [
    "(switchWorkspace|moveToWorkspace|moveColumnToWorkspace)\\.(9|[1-9][0-9]{1,17})"
    "(toggleShellWidget|openApp|openShellApp|newShellAppWindow)\\.[A-Za-z0-9][A-Za-z0-9._-]{0,127}"
  ];

  # Absent from the template, yet valid in preserveSettings.
  optionalSettingPaths = [
    "borders.darkColor"
    "borders.glow"
    "borders.gradient"
    "general.language"
    "keyboardModes.pauseTimeoutSeconds"
    "monitorBarOverrides"
    "monitorDwindleOverrides"
    "monitorGapOverrides"
    "monitorNiriOverrides"
    "monitorOrientationOverrides"
    "monitors"
    "overview.mouseButton"
    "quakeTerminal.foot"
    "quakeTerminal.kitty"
    "workspaceBar.accentColor"
    "workspaceBar.inactiveIconOpacity"
    "workspaceBar.textColor"
  ];

  hasOldId = hotkey: renamedHotkeyIds ? ${hotkey.id or ""};
  hasPath = settings: name: lib.hasAttrByPath (lib.splitString "." name) settings;
in

rec {
  isDynamicHotkeyId =
    id: builtins.any (pattern: builtins.match pattern id != null) dynamicHotkeyIdPatterns;

  # rename old ids, move them to the end
  # [ { id = "setWindowPrimarySpan.decrease10Percent"; } { id = "focus.left"; } ]
  #   -> [ { id = "focus.left"; } { id = "resizeWindowPrimarySpan.shrink"; } ]
  renameHotkeys =
    entries:
    let
      parts = lib.partition hasOldId entries;
    in
    parts.wrong ++ map (hotkey: hotkey // { id = renamedHotkeyIds.${hotkey.id}; }) parts.right;

  # list old ids with their new ones
  # [ { id = "setWindowPrimarySpan.decrease10Percent"; } { id = "focus.left"; } ]
  #   -> [ { from = "setWindowPrimarySpan.decrease10Percent"; to = "resizeWindowPrimarySpan.shrink"; } ]
  hotkeyRenames =
    entries:
    map (hotkey: {
      from = hotkey.id;
      to = renamedHotkeyIds.${hotkey.id};
    }) (builtins.filter hasOldId entries);

  # pick dynamic ids, dedupe, drop known ones
  # [ "openShellApp.example" ] [ { id = "openApp.foo"; } { id = "openApp.foo"; } { id = "openShellApp.example"; } ]
  #   -> [ "openApp.foo" ]
  dynamicHotkeyIds =
    knownIds: entries:
    lib.unique (
      lib.subtractLists knownIds (
        builtins.filter isDynamicHotkeyId (map (hotkey: hotkey.id or "") entries)
      )
    );

  # update each base by the first override with its id, drop the rest
  # [ { id = "focus.left"; binding = "Option+H"; } ]
  # [ { id = "focus.left"; binding = "Option+J"; } { id = "focus.left"; binding = "Option+K"; } { id = "focus.up"; } ]
  #   -> [ { id = "focus.left"; binding = "Option+J"; } ]
  mergeById =
    bases: overrides:
    map (base: base // lib.findFirst (override: override.id == base.id) { } overrides) bases;

  # bindings of entries without an id
  # [ { binding = "Option+H"; } { } { id = "focus.left"; binding = "Option+J"; } ] -> [ "Option+H" "(no binding)" ]
  hotkeysWithoutId =
    entries:
    map (
      hotkey: if builtins.isString (hotkey.binding or null) then hotkey.binding else "(no binding)"
    ) (builtins.filter (hotkey: !(hotkey ? id)) entries);

  # ids neither known nor dynamic
  # [ "focus.left" ] [ { id = "focus.left"; } { id = "focus.up"; } { id = "openApp.foo"; } ] -> [ "focus.up" ]
  unknownHotkeyIds =
    knownIds: entries:
    map (hotkey: hotkey.id) (
      builtins.filter (
        hotkey: hotkey ? id && !(builtins.elem hotkey.id knownIds) && !(isDynamicHotkeyId hotkey.id)
      ) entries
    );

  # merge settings.hotkeys into the template's per id, and report problems
  # [ { id = "resizeWindowPrimarySpan.shrink"; binding = "Unassigned"; } ]
  # [ { id = "setWindowPrimarySpan.decrease10Percent"; binding = "Option+Minus"; } { id = "openApp.foo"; } { id = "focus.up"; } ]
  #   -> {
  #     merged = [ { id = "resizeWindowPrimarySpan.shrink"; binding = "Option+Minus"; } { id = "openApp.foo"; binding = "Unassigned"; } ];
  #     renamed = [ { from = "setWindowPrimarySpan.decrease10Percent"; to = "resizeWindowPrimarySpan.shrink"; } ];
  #     withoutId = [ ];
  #     unknownIds = [ "focus.up" ];
  #   }
  hotkeys =
    defaults: declared:
    let
      knownIds = map (hotkey: hotkey.id) defaults;
      # renamed ones last, so mergeById prefers entries already using the new id, as OmniWM does
      userHotkeys = renameHotkeys declared;
      # known ones dropped, since the template has `openShellApp.example` and OmniWM rejects an id listed twice
      dynamicHotkeys = map (id: {
        inherit id;
        binding = "Unassigned";
      }) (dynamicHotkeyIds knownIds userHotkeys);
    in
    {
      merged = mergeById (defaults ++ dynamicHotkeys) userHotkeys;
      renamed = hotkeyRenames declared;
      withoutId = hotkeysWithoutId userHotkeys;
      unknownIds = unknownHotkeyIds knownIds userHotkeys;
    };

  # deep-merge settings into the template, keep its schemaVersion
  # { schemaVersion = 4; general = { animationsEnabled = true; ipcEnabled = false; }; hotkeys = [ ]; }
  # { schemaVersion = 1; general.ipcEnabled = true; }
  #   -> { schemaVersion = 4; general = { animationsEnabled = true; ipcEnabled = true; }; hotkeys = [ ]; }
  merge =
    defaultSettings: userSettings:
    lib.recursiveUpdate defaultSettings (
      removeAttrs userSettings [
        "hotkeys"
        "schemaVersion"
      ]
    )
    // {
      hotkeys = (hotkeys defaultSettings.hotkeys (userSettings.hotkeys or [ ])).merged;
    };

  # split paths, drop schemaVersion, find ones unknown or also in settings
  # { general.ipcEnabled = false; } { general.ipcEnabled = true; } [ "general.ipcEnabled" "schemaVersion" "foo" ]
  #   -> { paths = [ [ "general" "ipcEnabled" ] [ "foo" ] ]; unknown = [ "foo" ]; declared = [ "general.ipcEnabled" ]; }
  preserved =
    defaultSettings: userSettings: names:
    let
      kept = builtins.filter (name: name != "schemaVersion") names;
    in
    {
      paths = map (lib.splitString ".") kept;
      unknown = builtins.filter (
        name: !(builtins.elem name optionalSettingPaths) && !(hasPath defaultSettings name)
      ) kept;
      declared = builtins.filter (hasPath userSettings) kept;
    };
}
