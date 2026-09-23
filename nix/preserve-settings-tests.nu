#!/usr/bin/env nu

use std/assert

const script = path self preserve-settings.nu
const template = path self ../settings-defaults.toml
const paths = '[["monitors"],["routing"],["workspaceBar","iconOverrides"]]'

def main [] {
  let defaults = open --raw $template | from toml
  let work = mktemp --directory
  cd $work
  $defaults | to toml | save --force generated.toml

  let gui = {
    monitors: { ranking: ["37D8832A-2D66-02CA-B9F7-8F30A301B230"] }
    routing: { arrangements: [], mode: "custom" }
    workspaceBar: ($defaults.workspaceBar
      | upsert iconOverrides { "com.apple.Safari": "safari" }
      | upsert height 99.0)
  }
  $defaults | merge $gui | to toml | save --force live.toml

  nu $script generated.toml live.toml merged.toml $paths
  let merged = open --raw merged.toml | from toml
  assert equal $merged.monitors $gui.monitors
  assert equal $merged.routing $gui.routing
  assert equal $merged.workspaceBar.iconOverrides $gui.workspaceBar.iconOverrides
  assert equal $merged.workspaceBar.height $defaults.workspaceBar.height
  assert equal $merged.appearance.mode $defaults.appearance.mode

  # The module skips the write when the merge matches the file already in place.
  nu $script generated.toml merged.toml again.toml $paths
  assert equal (open --raw merged.toml) (open --raw again.toml)

  # A table written for an older schema keeps the keys the generated one adds.
  $defaults | upsert routing { mode: "custom" } | to toml | save --force legacy.toml
  nu $script generated.toml legacy.toml upgraded.toml $paths
  let upgraded = open --raw upgraded.toml | from toml
  assert equal $upgraded.routing.mode "custom"
  assert equal $upgraded.routing.arrangements $defaults.routing.arrangements

  nu $script generated.toml absent.toml fresh.toml $paths
  assert equal (open --raw fresh.toml) (open --raw generated.toml)

  "= not toml" | save --force broken.toml
  nu $script generated.toml broken.toml recovered.toml $paths
  assert equal (open --raw recovered.toml) (open --raw generated.toml)

  # A cell path errors out on a live file that holds a scalar where the schema has a table.
  $defaults | upsert workspaceBar true | to toml | save --force scalar.toml
  nu $script generated.toml scalar.toml kept.toml $paths
  assert equal (open --raw kept.toml) (open --raw generated.toml)

  cd ..
  rm --recursive --force $work
}
