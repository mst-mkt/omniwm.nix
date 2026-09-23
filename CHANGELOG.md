# Changelog

## 2026-09-23

- **Breaking** `lib.monitorOverride` now requires `monitorDisplayUUID` or `monitorDisplayId`. Existing entries need one added, or the evaluation fails. ([#11](https://github.com/mst-mkt/omniwm.nix/pull/11))
- The OmniWM source, `meta.homepage` and `meta.changelog` now point to [`OmniNull/OmniWM`](https://github.com/OmniNull/OmniWM) instead of `BarutSRB/OmniWM`, following the upstream repository transfer. The fetched source is identical, so no action is needed. ([#15](https://github.com/mst-mkt/omniwm.nix/pull/15))
- `settings.toml` is now replaced atomically, so OmniWM no longer reads a partly written file. ([#16](https://github.com/mst-mkt/omniwm.nix/pull/16))
- When `xdg.configHome` is not `~/.config`, OmniWM started by the launchd agent now reads the deployed settings instead of `~/.config/omniwm/settings.toml`. ([#16](https://github.com/mst-mkt/omniwm.nix/pull/16))
- `launchd.keepAlive` sets the launchd agent's `KeepAlive` key. ([#18](https://github.com/mst-mkt/omniwm.nix/pull/18))
- `lib.monitorOverride` is split into `lib.monitor.{bar,dwindle,gap,niri,orientation,routing}`, one helper per settings list, so a list with required keys now has them checked at evaluation, such as `gridColumn` and `gridRow` for `lib.monitor.routing`. `lib.routingArrangement` builds an element of `routing.arrangements` from `lib.monitor.routing` entries. `lib.monitorOverride` remains as deprecated. ([#19](https://github.com/mst-mkt/omniwm.nix/pull/19))

## Earlier

No changelog was kept. See the history up to [`eac6a0b`](https://github.com/mst-mkt/omniwm.nix/commit/eac6a0bfdc9e26fbe46c3b2119fc88597d9fd842).
