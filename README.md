# omniwm.nix

Nix flake for [OmniWM](https://github.com/BarutSRB/OmniWM), a macOS tiling window manager. It provides the package, a Home Manager module, and helpers for writing its settings.

## Why this flake

- A Home Manager module declares the settings and the launchd agent next to the rest of your configuration.
- OmniWM rejects a `settings.toml` that is missing a required key. `settings` is merged into OmniWM's own default `settings.toml`, so you write only what you change.
- That default `settings.toml` is generated from the OmniWM sources and updated with every version bump, so new keys arrive with the package.
- OmniWM rewrites `settings.toml` at startup, so the module deploys it as a writable file.
- The module rejects unknown hotkey ids at evaluation. OmniWM would otherwise reject the whole file silently at login.
- `lib` provides helpers for the parts of the settings that are tedious to write by hand, such as ids and colors.

## Usage

```nix
{
  inputs.omniwm = {
    url = "github:mst-mkt/omniwm.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

```nix
{ inputs, ... }:
let
  omniwmLib = inputs.omniwm.lib;
in
{
  imports = [ inputs.omniwm.homeManagerModules.default ];

  programs.omniwm = {
    enable = true;
    settings = {
      general.defaultLayoutType = "dwindle";
      gaps.size = 12.0;
      borders.color = omniwmLib.colors.fromHex "#7aa2f7";

      workspaces = omniwmLib.workspaces [
        { displayName = "browse"; }
        { displayName = "code"; }
        { displayName = "chat"; monitorAssignment.type = "secondary"; }
      ];

      appRules = [
        (omniwmLib.appRule "com.apple.finder" { layout = "float"; })
        (omniwmLib.appRule "com.google.Chrome" { assignToWorkspace = "1"; })
      ];

      hotkeys = omniwmLib.hotkeys {
        "focus.left" = "Option+H";
        "focus.down" = "Option+J";
        "focus.up" = "Option+K";
        "focus.right" = "Option+L";
      };
    };
  };
}
```

## Home Manager module

| Option            | Default              | Description                                                                       |
| ----------------- | -------------------- | --------------------------------------------------------------------------------- |
| `enable`          | `false`              | Install OmniWM and manage its settings.                                           |
| `package`         | this flake's package | Another version works as long as it accepts this flake's default `settings.toml`. |
| `settings`        | `null`               | Attribute set or path to a TOML file. `null` leaves the file unmanaged.           |
| `mutableSettings` | `true`               | Deploy a writable copy instead of a symlink into the Nix store.                   |
| `launchd.enable`  | `true`               | Start OmniWM with a launchd agent.                                                |

OmniWM rejects a settings file that is missing a required key, so `settings` is merged into [OmniWM's own default `settings.toml`](./settings-defaults.toml). The keys are documented in the [Settings Reference](https://omniwm.app/config/settings-reference/).

- `hotkeys` must list every action exactly once, so its entries are merged per `id` instead of replacing the list. Unknown ids fail at evaluation.
- Other lists (`workspaces`, `appRules`, `monitor*Overrides`) replace the defaults wholesale.
- OmniWM rewrites the file at startup, so by default it is deployed as a writable copy.
- Changes made at runtime (GUI, monitor overrides) are overwritten on the next activation. The previous file is kept as `settings.toml.bak`.

## Settings helpers

`lib` exposes pure functions for the parts of the settings that are tedious to write by hand.

<table>
  <thead>
    <tr>
      <th>Function</th>
      <th>Description</th>
      <th>Example</th>
      <th>Result</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>hotkeys</code></td>
      <td>Builds the <code>hotkeys</code> list from <code>id = binding</code> pairs.</td>
      <td><pre lang="nix">hotkeys {
  "focus.left" = "Option+H";
}</pre></td>
      <td><pre lang="nix">[
  {
    id = "focus.left";
    binding = "Option+H";
  }
]</pre></td>
    </tr>
    <tr>
      <td><code>colors.fromHex</code></td>
      <td>Hex string to <code>{ red, green, blue, alpha }</code>. The alpha digits are optional.</td>
      <td><pre lang="nix">colors.fromHex "#33ccff"</pre></td>
      <td><pre lang="nix">{
  red = 0.2;
  green = 0.8;
  blue = 1.0;
  alpha = 1.0;
}</pre></td>
    </tr>
    <tr>
      <td><code>colors.toHex</code></td>
      <td><code>{ red, green, blue, alpha }</code> to a hex string. Alpha digits only when alpha &lt; 1.0.</td>
      <td><pre lang="nix">colors.toHex {
  red = 0.2;
  green = 0.8;
  blue = 1.0;
  alpha = 1.0;
}</pre></td>
      <td><pre lang="nix">"#33ccff"</pre></td>
    </tr>
    <tr>
      <td><code>appRule</code></td>
      <td>App rule with a deterministic <code>id</code>.</td>
      <td><pre lang="nix">appRule "com.apple.finder" {
  layout = "float";
}</pre></td>
      <td><pre lang="nix">{
  id = &lt;uuid&gt;;
  bundleId = "com.apple.finder";
  layout = "float";
}</pre></td>
    </tr>
    <tr>
      <td><code>workspaces</code></td>
      <td>Builds the <code>workspaces</code> list. <code>name</code> is the position in the list; each entry also gets a deterministic <code>id</code>, <code>layoutType = "default"</code>, and the main monitor.</td>
      <td><pre lang="nix">workspaces [
  { }
  { displayName = "chat"; monitorAssignment.type = "secondary"; }
]</pre></td>
      <td><pre lang="nix">[
  {
    id = &lt;uuid&gt;;
    name = "1";
    layoutType = "default";
    monitorAssignment.type = "main";
  }
  {
    id = &lt;uuid&gt;;
    name = "2";
    displayName = "chat";
    layoutType = "default";
    monitorAssignment.type = "secondary";
  }
]</pre></td>
    </tr>
    <tr>
      <td><code>monitorOverride</code></td>
      <td>Entry for the <code>monitor*Overrides</code> lists with a deterministic <code>id</code> and <code>monitorName</code>.</td>
      <td><pre lang="nix">monitorOverride "DELL U2720Q" {
  innerGap = 8.0;
}</pre></td>
      <td><pre lang="nix">{
  id = &lt;uuid&gt;;
  monitorName = "DELL U2720Q";
  innerGap = 8.0;
}</pre></td>
    </tr>
  </tbody>
</table>

The ids are UUIDs derived from the inputs, so they stay the same across rebuilds.

OmniWM identifies workspaces by number, so `workspaces` takes `name` from the position in the list, and `assignToWorkspace` refers to that number rather than to `displayName`.

Hotkey ids and their default bindings are listed in [settings-defaults.toml](./settings-defaults.toml). Bindings use OmniWM's own notation, such as `"Option+Shift+Left Arrow"`; OmniWM rejects the whole file when it cannot parse one.

## Binary cache

Prebuilt packages are available from Cachix. Add the cache with `cachix use` or in the Nix settings.

```sh
cachix use mst-mkt
```

```nix
nix.settings = {
  extra-substituters = [ "https://mst-mkt.cachix.org" ];
  extra-trusted-public-keys = [ "mst-mkt.cachix.org-1:Ap1WSTd2tPEsFkNutQ7+X8OGtv7kOy9Q+xzvBvcL7FU=" ];
};
```

## Contributing

Feedback from real users is welcome. Please file it as an [issue](https://github.com/mst-mkt/omniwm.nix/issues). When contributing changes, the setup below is available.

### Development

`nix develop ./dev` or `direnv allow` enters the dev shell.

| Command                                                   | Purpose                                                           |
| --------------------------------------------------------- | ----------------------------------------------------------------- |
| `treefmt`                                                 | Format.                                                           |
| `nix flake check`                                         | lib tests. macOS only.                                            |
| `nix run nixpkgs#nushell -- codegen/generate-defaults.nu` | Regenerate `settings-defaults.toml`. macOS with a matching Xcode. |

`settings-defaults.toml` is the `settings.toml` that OmniWM writes on first launch. [codegen/generate-defaults.nu](./codegen/generate-defaults.nu) generates it from the upstream sources at the packaged tag. The Update workflow bumps the version and regenerates the file every three days, so neither needs to be done by hand.

## License

- [MIT](./LICENSE), unless noted below
- GPL-2.0-only for the files derived from the [OmniWM](https://github.com/BarutSRB/OmniWM) sources
  - `settings-defaults.toml`
  - `codegen/GenerateDefaultsTemplateTests.swift`
