{ omniwm }:

let
  uuidPattern = "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}";
  isUuid = s: builtins.match uuidPattern s != null;
  fails = expr: !(builtins.tryEval expr).success;
  displayUuid = "37D8832A-2D66-02CA-B9F7-8F30A301B230";
  displayUuidLower = "37d8832a-2d66-02ca-b9f7-8f30a301b230";
  otherDisplayUuid = "5B0F5F3C-0B2E-4C0F-9E0A-6C3E1D2A7B41";
  routingLeft = omniwm.monitor.routing "DELL U2723QE" {
    monitorDisplayUUID = displayUuid;
    gridColumn = 0;
    gridRow = 0;
  };
  routingRight = omniwm.monitor.routing "LG 27UL850" {
    monitorDisplayUUID = otherDisplayUuid;
    gridColumn = 1;
    gridRow = 0;
  };
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

  # monitor.*
  testMonitorShape = {
    expr = removeAttrs (omniwm.monitor.gap "DELL U2723QE" {
      monitorDisplayUUID = displayUuid;
      innerGap = 8.0;
    }) [ "id" ];
    expected = {
      monitorName = "DELL U2723QE";
      monitorDisplayUUID = displayUuid;
      innerGap = 8.0;
    };
  };
  testMonitorUpperCasesUuid = {
    expr =
      (omniwm.monitor.gap "DELL U2723QE" {
        monitorDisplayUUID = displayUuidLower;
      }).monitorDisplayUUID;
    expected = displayUuid;
  };
  testMonitorIdIsUuid = {
    expr = isUuid (omniwm.monitor.gap "DELL U2723QE" { monitorDisplayUUID = displayUuid; }).id;
    expected = true;
  };
  testMonitorIdIgnoresUuidCase = {
    expr =
      (omniwm.monitor.gap "DELL U2723QE" { monitorDisplayUUID = displayUuid; }).id
      == (omniwm.monitor.gap "DELL U2723QE" { monitorDisplayUUID = displayUuidLower; }).id;
    expected = true;
  };
  testMonitorIdIgnoresMonitorName = {
    expr =
      (omniwm.monitor.gap "DELL U2723QE" { monitorDisplayUUID = displayUuid; }).id
      == (omniwm.monitor.gap "LG 27UL850" { monitorDisplayUUID = displayUuid; }).id;
    expected = true;
  };
  testMonitorIdVariesByDisplay = {
    expr =
      (omniwm.monitor.gap "DELL U2723QE" { monitorDisplayUUID = displayUuid; }).id
      == (omniwm.monitor.gap "DELL U2723QE" {
        monitorDisplayUUID = otherDisplayUuid;
      }).id;
    expected = false;
  };
  testMonitorIdVariesByMonitorNameWithoutUuid = {
    expr =
      (omniwm.monitor.gap "DELL U2723QE" { monitorDisplayId = 1; }).id
      == (omniwm.monitor.gap "LG 27UL850" { monitorDisplayId = 1; }).id;
    expected = false;
  };
  testMonitorIdVariesByDisplayIdWithoutUuid = {
    expr =
      (omniwm.monitor.gap "DELL U2723QE" { monitorDisplayId = 1; }).id
      == (omniwm.monitor.gap "DELL U2723QE" { monitorDisplayId = 2; }).id;
    expected = false;
  };
  testMonitorIdOverride = {
    expr =
      (omniwm.monitor.gap "DELL U2723QE" {
        monitorDisplayUUID = displayUuid;
        id = "custom";
      }).id;
    expected = "custom";
  };
  testMonitorAcceptsDisplayId = {
    expr = removeAttrs (omniwm.monitor.gap "DELL U2723QE" {
      monitorDisplayId = 1;
      innerGap = 8.0;
    }) [ "id" ];
    expected = {
      monitorName = "DELL U2723QE";
      monitorDisplayId = 1;
      innerGap = 8.0;
    };
  };
  testMonitorDropsNullUuid = {
    expr =
      omniwm.monitor.gap "DELL U2723QE" {
        monitorDisplayUUID = null;
        monitorDisplayId = 1;
      } ? monitorDisplayUUID;
    expected = false;
  };
  testMonitorRejectsMissingIdentity = {
    expr = fails (omniwm.monitor.gap "DELL U2723QE" { innerGap = 8.0; });
    expected = true;
  };
  testMonitorRejectsMalformedUuid = {
    expr = fails (omniwm.monitor.gap "DELL U2723QE" { monitorDisplayUUID = "DELL U2723QE"; });
    expected = true;
  };
  testMonitorRejectsMalformedDisplayId = {
    expr = map (id: fails (omniwm.monitor.gap "DELL U2723QE" { monitorDisplayId = id; })) [
      1.0
      (-1)
      4294967296
    ];
    expected = [
      true
      true
      true
    ];
  };
  testMonitorIdPerList = {
    expr = builtins.mapAttrs (
      _: helper: helper "DELL U2723QE" { monitorDisplayUUID = displayUuid; } ? id
    ) omniwm.monitor;
    expected = {
      bar = true;
      dwindle = true;
      gap = true;
      niri = true;
      orientation = false;
      routing = false;
    };
  };
  testMonitorOrientationShape = {
    expr = omniwm.monitor.orientation "DELL U2723QE" {
      monitorDisplayUUID = displayUuidLower;
      orientation = "vertical";
    };
    expected = {
      monitorName = "DELL U2723QE";
      monitorDisplayUUID = displayUuid;
      orientation = "vertical";
    };
  };
  testMonitorRoutingRejectsMissingIdentity = {
    expr = fails (
      omniwm.monitor.routing "DELL U2723QE" {
        gridColumn = 0;
        gridRow = 0;
      }
    );
    expected = true;
  };

  # routingArrangement
  testRoutingArrangementShape = {
    expr = removeAttrs (omniwm.routingArrangement [ routingLeft ]) [ "id" ];
    expected = {
      monitors = [ routingLeft ];
    };
  };
  testRoutingArrangementIdIsUuid = {
    expr = isUuid (omniwm.routingArrangement [ routingLeft ]).id;
    expected = true;
  };
  testRoutingArrangementIdIgnoresOrder = {
    expr =
      (omniwm.routingArrangement [
        routingLeft
        routingRight
      ]).id == (omniwm.routingArrangement [
        routingRight
        routingLeft
      ]).id;
    expected = true;
  };
  testRoutingArrangementIdVariesByMonitors = {
    expr =
      (omniwm.routingArrangement [ routingLeft ]).id == (omniwm.routingArrangement [
        routingLeft
        routingRight
      ]).id;
    expected = false;
  };

  # monitorOverride
  testMonitorOverrideMatchesListsWithId = {
    expr =
      builtins.mapAttrs
        (
          _: helper:
          helper "DELL U2723QE" { monitorDisplayUUID = displayUuid; }
          == omniwm.monitorOverride "DELL U2723QE" { monitorDisplayUUID = displayUuid; }
        )
        {
          inherit (omniwm.monitor)
            bar
            dwindle
            gap
            niri
            ;
        };
    expected = {
      bar = true;
      dwindle = true;
      gap = true;
      niri = true;
    };
  };
}
