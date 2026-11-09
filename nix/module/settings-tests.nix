{ lib }:

let
  settings = import ./settings.nix { inherit lib; };
  template = fromTOML (builtins.readFile ../../settings-defaults.toml);

  bind = id: binding: { inherit id binding; };
  defaultHotkeys = [
    (bind "focus.left" "Option+H")
    (bind "focus.right" "Option+L")
    (bind "resizeWindowPrimarySpan.shrink" "Unassigned")
    (bind "openShellApp.example" "Unassigned")
  ];
  defaultSettings = {
    schemaVersion = 4;
    general = {
      updateChecksEnabled = true;
      defaultLayoutType = "niri";
    };
    workspaces = [
      { name = "1"; }
      { name = "2"; }
    ];
    hotkeys = defaultHotkeys;
  };
  bindingOf = id: hotkeys: (lib.findFirst (hotkey: hotkey.id == id) null hotkeys).binding;
in

{
  # renameHotkeys
  testRenameHotkeysReplacesOldId = {
    expr = settings.renameHotkeys [ (bind "setWindowPrimarySpan.decrease10Percent" "Option+H") ];
    expected = [ (bind "resizeWindowPrimarySpan.shrink" "Option+H") ];
  };
  testRenameHotkeysMovesRenamedLast = {
    expr = settings.renameHotkeys [
      (bind "setWindowPrimarySpan.decrease10Percent" "Old")
      (bind "focus.left" "Option+H")
      (bind "resizeWindowPrimarySpan.shrink" "New")
    ];
    expected = [
      (bind "focus.left" "Option+H")
      (bind "resizeWindowPrimarySpan.shrink" "New")
      (bind "resizeWindowPrimarySpan.shrink" "Old")
    ];
  };
  testRenameHotkeysKeepsEntriesWithoutId = {
    expr = settings.renameHotkeys [ { binding = "Option+H"; } ];
    expected = [ { binding = "Option+H"; } ];
  };

  # hotkeyRenames
  testHotkeyRenames = {
    expr = settings.hotkeyRenames [
      (bind "setWindowPrimarySpan.decrease10Percent" "Option+H")
      (bind "focus.left" "Option+J")
      { binding = "Option+X"; }
    ];
    expected = [
      {
        from = "setWindowPrimarySpan.decrease10Percent";
        to = "resizeWindowPrimarySpan.shrink";
      }
    ];
  };

  # dynamicHotkeyIds
  testDynamicHotkeyIds = {
    expr =
      settings.dynamicHotkeyIds
        [ "openShellApp.example" ]
        [
          (bind "openApp.foo" "Option+F")
          (bind "focus.left" "Option+H")
          (bind "openApp.foo" "Option+G")
          (bind "openShellApp.example" "Option+E")
          { binding = "Option+X"; }
        ];
    expected = [ "openApp.foo" ];
  };

  # mergeById
  testMergeByIdKeepsBaseOrder = {
    expr =
      settings.mergeById
        [
          (bind "a" "1")
          (bind "b" "2")
        ]
        [
          (bind "b" "3")
          (bind "c" "4")
        ];
    expected = [
      (bind "a" "1")
      (bind "b" "3")
    ];
  };
  testMergeByIdFirstOverrideWins = {
    expr =
      settings.mergeById
        [ (bind "a" "1") ]
        [
          (bind "a" "2")
          (bind "a" "3")
        ];
    expected = [ (bind "a" "2") ];
  };
  testMergeByIdKeepsBaseAttrs = {
    expr = settings.mergeById [ ((bind "a" "1") // { enabled = true; }) ] [ (bind "a" "2") ];
    expected = [ ((bind "a" "2") // { enabled = true; }) ];
  };

  # hotkeysWithoutId
  testHotkeysWithoutId = {
    expr = settings.hotkeysWithoutId [
      { binding = "Option+H"; }
      { }
      { binding = 1; }
      (bind "focus.left" "Option+J")
    ];
    expected = [
      "Option+H"
      "(no binding)"
      "(no binding)"
    ];
  };

  # unknownHotkeyIds
  testUnknownHotkeyIds = {
    expr =
      settings.unknownHotkeyIds
        [ "focus.left" ]
        [
          (bind "focus.left" "Option+H")
          (bind "focus.up" "Option+K")
          (bind "openApp.foo" "Option+F")
          { binding = "Option+X"; }
        ];
    expected = [ "focus.up" ];
  };

  # hotkeys
  testHotkeysKeepsDefaults = {
    expr = (settings.hotkeys defaultHotkeys [ ]).merged;
    expected = defaultHotkeys;
  };
  testHotkeysPrefersNewIdOverOldId = {
    expr =
      map
        (
          declared:
          bindingOf "resizeWindowPrimarySpan.shrink" (settings.hotkeys defaultHotkeys declared).merged
        )
        [
          [
            (bind "setWindowPrimarySpan.decrease10Percent" "Old")
            (bind "resizeWindowPrimarySpan.shrink" "New")
          ]
          [
            (bind "resizeWindowPrimarySpan.shrink" "New")
            (bind "setWindowPrimarySpan.decrease10Percent" "Old")
          ]
        ];
    expected = [
      "New"
      "New"
    ];
  };
  testHotkeysAppendsDynamicHotkeys = {
    expr =
      (settings.hotkeys defaultHotkeys [
        (bind "openApp.foo" "Option+F")
        (bind "focus.left" "Option+Left")
        (bind "openApp.foo" "Option+G")
      ]).merged;
    expected = [
      (bind "focus.left" "Option+Left")
      (bind "focus.right" "Option+L")
      (bind "resizeWindowPrimarySpan.shrink" "Unassigned")
      (bind "openShellApp.example" "Unassigned")
      (bind "openApp.foo" "Option+F")
    ];
  };
  testHotkeysRenamed = {
    expr =
      (settings.hotkeys defaultHotkeys [
        (bind "setWindowPrimarySpan.decrease10Percent" "Option+H")
        (bind "focus.left" "Option+J")
      ]).renamed;
    expected = [
      {
        from = "setWindowPrimarySpan.decrease10Percent";
        to = "resizeWindowPrimarySpan.shrink";
      }
    ];
  };
  testHotkeysChecksRenamedIds = {
    expr =
      (settings.hotkeys defaultHotkeys [ (bind "setWindowPrimarySpan.decrease10Percent" "Option+H") ])
      .unknownIds;
    expected = [ ];
  };

  # merge
  testMergeEmpty = {
    expr = settings.merge defaultSettings { };
    expected = defaultSettings;
  };
  testMergeDeep = {
    expr = (settings.merge defaultSettings { general.updateChecksEnabled = false; }).general;
    expected = {
      updateChecksEnabled = false;
      defaultLayoutType = "niri";
    };
  };
  testMergeReplacesLists = {
    expr = (settings.merge defaultSettings { workspaces = [ { name = "1"; } ]; }).workspaces;
    expected = [ { name = "1"; } ];
  };
  testMergeIgnoresSchemaVersion = {
    expr = (settings.merge defaultSettings { schemaVersion = 1; }).schemaVersion;
    expected = 4;
  };
  testMergeHotkeys = {
    expr =
      bindingOf "focus.left"
        (settings.merge defaultSettings { hotkeys = [ (bind "focus.left" "Option+Left") ]; }).hotkeys;
    expected = "Option+Left";
  };

  # preserved
  testPreservedPaths = {
    expr =
      (settings.preserved defaultSettings { } [
        "general.updateChecksEnabled"
        "schemaVersion"
        "monitors"
      ]).paths;
    expected = [
      [
        "general"
        "updateChecksEnabled"
      ]
      [ "monitors" ]
    ];
  };
  testPreservedUnknown = {
    expr =
      (settings.preserved defaultSettings { } [
        "general.updateChecksEnabled"
        "workspaces"
        "schemaVersion"
        "borders.glow"
        "general.missing"
        "missing"
      ]).unknown;
    expected = [
      "general.missing"
      "missing"
    ];
  };
  testPreservedDeclared = {
    expr =
      (settings.preserved defaultSettings
        {
          general.updateChecksEnabled = false;
          workspaces = [ ];
          schemaVersion = 1;
        }
        [
          "general.updateChecksEnabled"
          "general.defaultLayoutType"
          "workspaces"
          "schemaVersion"
        ]
      ).declared;
    expected = [
      "general.updateChecksEnabled"
      "workspaces"
    ];
  };

  # isDynamicHotkeyId
  testIsDynamicHotkeyIdAcceptsWorkspaceNumbers = {
    expr = builtins.filter (id: !settings.isDynamicHotkeyId id) [
      "switchWorkspace.9"
      "moveToWorkspace.10"
      "moveColumnToWorkspace.123456789012345678"
    ];
    expected = [ ];
  };
  testIsDynamicHotkeyIdRejectsWorkspaceNumbers = {
    expr = builtins.filter settings.isDynamicHotkeyId [
      # in the template
      "switchWorkspace.8"
      # leading zero
      "switchWorkspace.09"
      # more than 18 digits
      "switchWorkspace.1234567890123456789"
      # not a number
      "switchWorkspace.next"
      # unknown prefix
      "switchWorkspaceSlot.9"
    ];
    expected = [ ];
  };
  testIsDynamicHotkeyIdAcceptsNames = {
    expr = builtins.filter (id: !settings.isDynamicHotkeyId id) [
      "openApp.com.apple.Safari"
      "toggleShellWidget.clock"
      "openShellApp.x_y-z"
      "newShellAppWindow.${lib.strings.replicate 128 "a"}"
    ];
    expected = [ ];
  };
  testIsDynamicHotkeyIdRejectsNames = {
    expr = builtins.filter settings.isDynamicHotkeyId [
      # more than 128 characters
      "newShellAppWindow.${lib.strings.replicate 129 "a"}"
      # starts with `.`
      "openApp..hidden"
      # starts with `-`
      "openApp.-x"
      # empty
      "openApp."
      # contains a space
      "openApp.a b"
    ];
    expected = [ ];
  };

  # settings-defaults.toml
  testTemplateMergesToItself = {
    expr = settings.merge template { } == template;
    expected = true;
  };
}
