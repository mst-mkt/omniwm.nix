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

  # shared by the six monitor*Overrides lists
  monitorOverride =
    name: attrs:
    {
      id = mkId "monitor:${name}";
      monitorName = name;
    }
    // attrs;
}
