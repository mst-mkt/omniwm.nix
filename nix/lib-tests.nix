{ omniwm }:

let
  uuidPattern = "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}";
  isUuid = s: builtins.match uuidPattern s != null;
  fails = expr: !(builtins.tryEval expr).success;
  twoWorkspaces = omniwm.workspaces [
    { }
    { }
  ];
in

{
  # hotkeys
  testHotkeysList = {
    expr = omniwm.hotkeys {
      "focus.left" = "Option+H";
      "focus.right" = "Option+L";
    };
    expected = [
      {
        id = "focus.left";
        binding = "Option+H";
      }
      {
        id = "focus.right";
        binding = "Option+L";
      }
    ];
  };

  # colors.fromHex
  testFromHexChannels = {
    expr = omniwm.colors.fromHex "#ff8000";
    expected = {
      red = 1.0;
      green = 128 / 255.0;
      blue = 0.0;
      alpha = 1.0;
    };
  };
  testFromHexAlpha = {
    expr = omniwm.colors.fromHex "#ff800080";
    expected = {
      red = 1.0;
      green = 128 / 255.0;
      blue = 0.0;
      alpha = 128 / 255.0;
    };
  };
  testFromHexUpperCaseAndNoHash = {
    expr = omniwm.colors.fromHex "FF8000";
    expected = omniwm.colors.fromHex "#ff8000";
  };
  testFromHexRejectsShort = {
    expr = fails (omniwm.colors.fromHex "#fff");
    expected = true;
  };
  testFromHexRejectsNonHex = {
    expr = fails (omniwm.colors.fromHex "#gggggg");
    expected = true;
  };

  # colors.toHex
  testToHexRoundTrip = {
    expr = map (hex: omniwm.colors.toHex (omniwm.colors.fromHex hex)) [
      "#ff8000"
      "#ff800080"
      "#0a0b0c"
    ];
    expected = [
      "#ff8000"
      "#ff800080"
      "#0a0b0c"
    ];
  };
  testToHexRounds = {
    expr = omniwm.colors.toHex {
      red = 0.5;
      green = 0.999;
      blue = 0.001;
      alpha = 1.0;
    };
    expected = "#80ff00";
  };

  # appRule
  testAppRuleShape = {
    expr = removeAttrs (omniwm.appRule "com.apple.Safari" { minWidth = 500.0; }) [ "id" ];
    expected = {
      bundleId = "com.apple.Safari";
      minWidth = 500.0;
    };
  };
  testAppRuleIdIsUuid = {
    expr = isUuid (omniwm.appRule "com.apple.Safari" { }).id;
    expected = true;
  };
  testAppRuleIdIsDeterministic = {
    expr =
      (omniwm.appRule "com.apple.Safari" { }).id
      == (omniwm.appRule "com.apple.Safari" { layout = "float"; }).id;
    expected = true;
  };
  testAppRuleIdVariesByMatcher = {
    expr =
      (omniwm.appRule "com.apple.Safari" { titleSubstring = "Preferences"; }).id
      == (omniwm.appRule "com.apple.Safari" { titleRegex = "Preferences"; }).id;
    expected = false;
  };
  testAppRuleIdOverride = {
    expr = (omniwm.appRule "com.apple.Safari" { id = "custom"; }).id;
    expected = "custom";
  };

  # workspaces
  testWorkspacesShape = {
    expr = map (workspace: removeAttrs workspace [ "id" ]) (
      omniwm.workspaces [
        { }
        {
          displayName = "chat";
          layoutType = "dwindle";
          monitorAssignment.type = "secondary";
        }
      ]
    );
    expected = [
      {
        name = "1";
        layoutType = "default";
        monitorAssignment.type = "main";
      }
      {
        name = "2";
        displayName = "chat";
        layoutType = "dwindle";
        monitorAssignment.type = "secondary";
      }
    ];
  };
  testWorkspacesIdIsUuid = {
    expr = builtins.all (workspace: isUuid workspace.id) twoWorkspaces;
    expected = true;
  };
  testWorkspacesIdVariesByPosition = {
    expr = (builtins.head twoWorkspaces).id == (builtins.elemAt twoWorkspaces 1).id;
    expected = false;
  };
  testWorkspacesRejectsName = {
    expr = fails (builtins.head (omniwm.workspaces [ { name = "code"; } ]));
    expected = true;
  };

  # monitorOverride
  testMonitorOverrideShape = {
    expr = removeAttrs (omniwm.monitorOverride "DELL U2723QE" { innerGap = 8.0; }) [ "id" ];
    expected = {
      monitorName = "DELL U2723QE";
      innerGap = 8.0;
    };
  };
}
