{ lib }:

let
  # decoded as UUID by OmniWM, version bits unchecked
  mkId =
    seed:
    let
      hash = builtins.hashString "sha256" seed;
      part = start: len: builtins.substring start len hash;
    in
    lib.toUpper "${part 0 8}-${part 8 4}-${part 12 4}-${part 16 4}-${part 20 12}";

  # keys of MonitorSettingsType, shared by all six lists
  monitorSettings =
    caller: name: attrs:
    let
      uuid = attrs.monitorDisplayUUID or null;
      displayId = attrs.monitorDisplayId or null;
      canonicalUuid = lib.toUpper uuid;
      hasUuidShape =
        builtins.match "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}" uuid
        != null;
      isUint32 = builtins.isInt displayId && displayId >= 0 && displayId <= lib.fromHexString "FFFFFFFF";
      entry = {
        monitorName = name;
      }
      // removeAttrs attrs [
        "monitorDisplayUUID"
        "monitorDisplayId"
      ]
      // lib.optionalAttrs (uuid != null) { monitorDisplayUUID = canonicalUuid; }
      // lib.optionalAttrs (displayId != null) { monitorDisplayId = displayId; };
    in
    assert lib.assertMsg (uuid != null || displayId != null)
      "omniwm.lib.${caller}: ${builtins.toJSON name} has neither `monitorDisplayUUID` nor `monitorDisplayId`, so OmniWM applies it to no display.";
    assert lib.assertMsg (
      uuid == null || hasUuidShape
    ) "omniwm.lib.${caller}: expected `monitorDisplayUUID` in UUID form, got ${builtins.toJSON uuid}.";
    assert lib.assertMsg (displayId == null || isUint32)
      "omniwm.lib.${caller}: expected `monitorDisplayId` to be a UInt32, got ${builtins.toJSON displayId}.";
    if uuid != null then
      entry
    else
      lib.warn "omniwm.lib.${caller}: ${builtins.toJSON name} is matched by `monitorDisplayId` ${toString displayId} and a name equal to the one macOS reports, and that id can change when displays are reconnected." entry;

  # display an entry applies to, seed of its id
  monitorIdentity =
    entry:
    entry.monitorDisplayUUID or "${entry.monitorName}:${toString (entry.monitorDisplayId or "")}";

  # for the four lists whose entries store an id
  withMonitorId = entry: { id = mkId "monitor:${monitorIdentity entry}"; } // entry;
in

{
  # { "focus.left" = "Option+H"; ... } -> [ { id = "focus.left"; binding = "Option+H"; } ... ]
  hotkeys = bindings: lib.mapAttrsToList (id: binding: { inherit id binding; }) bindings;

  colors = {
    # "#rrggbb" or "#rrggbbaa" -> { red, green, blue, alpha } with 0.0-1.0 floats
    fromHex =
      hex:
      let
        raw = lib.removePrefix "#" hex;
        channel = offset: (lib.fromHexString (builtins.substring offset 2 raw)) / 255.0;
      in
      assert lib.assertMsg (
        builtins.match "[0-9a-fA-F]{6}([0-9a-fA-F]{2})?" raw != null
      ) "omniwm.lib.colors.fromHex: expected \"#rrggbb\" or \"#rrggbbaa\", got ${builtins.toJSON hex}";
      {
        red = channel 0;
        green = channel 2;
        blue = channel 4;
        alpha = if builtins.stringLength raw == 8 then channel 6 else 1.0;
      };

    # { red, green, blue, alpha } -> "#rrggbb", or "#rrggbbaa" when alpha < 1.0
    toHex =
      color:
      let
        byte = v: builtins.floor (v * 255 + 0.5);
        hex2 = v: lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString (byte v)));
        rgb = lib.concatMapStrings hex2 [
          color.red
          color.green
          color.blue
        ];
        alpha = color.alpha or 1.0;
      in
      "#${rgb}${lib.optionalString (alpha < 1.0) (hex2 alpha)}";
  };

  appRule =
    bundleId: attrs:
    let
      matchers = lib.concatMapStrings (m: ":${attrs.${m} or ""}") [
        "appNameSubstring"
        "titleSubstring"
        "titleRegex"
        "axRole"
        "axSubrole"
      ];
    in
    {
      id = mkId "appRule:${bundleId}${matchers}";
      inherit bundleId;
    }
    // attrs;

  # [ { } { displayName = "chat"; } ] -> [ { id; name = "1"; ... } { id; name = "2"; displayName; ... } ]
  workspaces =
    let
      workspace =
        index: attrs:
        let
          name = toString index;
        in
        assert lib.assertMsg (
          !(attrs ? name)
        ) "omniwm.lib.workspaces: `name` is the position in the list, got ${builtins.toJSON attrs.name}";
        {
          id = mkId "workspace:${name}";
          inherit name;
          # follows general.defaultLayoutType
          layoutType = "default";
          monitorAssignment.type = "main";
        }
        // attrs;
    in
    lib.imap1 workspace;

  # one per MonitorSettingsType implementation
  monitor = {
    bar = name: attrs: withMonitorId (monitorSettings "monitor.bar" name attrs);
    dwindle = name: attrs: withMonitorId (monitorSettings "monitor.dwindle" name attrs);
    gap = name: attrs: withMonitorId (monitorSettings "monitor.gap" name attrs);
    niri = name: attrs: withMonitorId (monitorSettings "monitor.niri" name attrs);
    orientation = monitorSettings "monitor.orientation";
    routing =
      name: attrs:
      let
        column = attrs.gridColumn or null;
        row = attrs.gridRow or null;
      in
      assert lib.assertMsg (builtins.isInt column)
        "omniwm.lib.monitor.routing: expected `gridColumn` to be an integer, got ${builtins.toJSON column}.";
      assert lib.assertMsg (builtins.isInt row)
        "omniwm.lib.monitor.routing: expected `gridRow` to be an integer, got ${builtins.toJSON row}.";
      monitorSettings "monitor.routing" name attrs;
  };

  # [ (monitor.routing ...) ... ] -> { id; monitors = [ ... ]; }, id independent of the order
  routingArrangement = monitors: {
    id = mkId "arrangement:${lib.concatStringsSep "," (lib.sort lib.lessThan (map monitorIdentity monitors))}";
    inherit monitors;
  };

  # deprecated, emits an id even for orientation and routing
  monitorOverride =
    lib.warn
      "omniwm.lib.monitorOverride is deprecated; use omniwm.lib.monitor.{bar,dwindle,gap,niri,orientation,routing} instead."
      (name: attrs: withMonitorId (monitorSettings "monitorOverride" name attrs));
}
