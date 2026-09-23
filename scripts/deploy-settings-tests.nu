#!/usr/bin/env nu

use std/assert

const script = path self deploy-settings.nu
const template = path self ../settings-defaults.toml
const paths = '[["monitorGapOverrides"],["monitors"],["routing"],["workspaceBar","iconOverrides"]]'

def main [] {
  let defaults = open --raw $template | from toml
  let work = mktemp --directory
  cd $work
  $defaults | to json | save --force generated.json

  let gui = {
    monitorGapOverrides: [{ displayId: "37D8832A-2D66-02CA-B9F7-8F30A301B230", gap: 8.0 }]
    monitors: { ranking: ["37D8832A-2D66-02CA-B9F7-8F30A301B230"] }
    routing: { arrangements: [], mode: "custom" }
    workspaceBar: ($defaults.workspaceBar
      | upsert iconOverrides { "com.apple.Safari": "safari" }
      | upsert height 99.0)
  }
  let live = $defaults | merge $gui | to toml
  $live | save --force settings.toml

  nu $script $template generated.json settings.toml $paths
  let merged = open --raw settings.toml | from toml
  assert equal $merged.monitorGapOverrides $gui.monitorGapOverrides
  assert equal $merged.monitors $gui.monitors
  assert equal $merged.routing $gui.routing
  assert equal $merged.workspaceBar.iconOverrides $gui.workspaceBar.iconOverrides
  assert equal $merged.workspaceBar.height $defaults.workspaceBar.height
  assert equal $merged.appearance.mode $defaults.appearance.mode
  # A float that looks like an integer stays a float through JSON.
  assert equal ($merged.borders.width | describe) "float"
  assert str contains (open --raw settings.toml) "[[monitorGapOverrides]]"
  assert equal (open --raw settings.toml.bak) $live
  assert not ("settings.toml.tmp" | path exists)

  # Nothing is written when the merge matches the file already in place.
  "previous" | save --force settings.toml.bak
  nu $script $template generated.json settings.toml $paths
  assert equal (open --raw settings.toml.bak) "previous"

  $live | save --force settings.toml
  nu $script --dry-run $template generated.json settings.toml $paths
  assert equal (open --raw settings.toml) $live

  # A table written for an older schema keeps the keys the generated one adds.
  $defaults | upsert routing { mode: "custom" } | to toml | save --force settings.toml
  nu $script $template generated.json settings.toml $paths
  let upgraded = open --raw settings.toml | from toml
  assert equal $upgraded.routing.mode "custom"
  assert equal $upgraded.routing.arrangements $defaults.routing.arrangements

  nu $script $template generated.json absent/settings.toml $paths
  assert equal (open --raw absent/settings.toml | from toml) $defaults
  assert not ("absent/settings.toml.bak" | path exists)

  # With nothing to preserve, the generated TOML is written byte for byte.
  $live | save --force settings.toml
  nu $script $template generated.json settings.toml '[]'
  assert equal (open --raw settings.toml) (open --raw $template)

  "target" | save --force target.toml
  rm --force settings.toml
  ^ln -s target.toml settings.toml
  nu $script $template generated.json settings.toml '[]'
  assert equal (open --raw target.toml) "target"
  assert equal ("settings.toml" | path type) "file"
  assert equal (open --raw settings.toml.bak) "target"

  "= not toml" | save --force settings.toml
  nu $script $template generated.json settings.toml $paths
  assert equal (open --raw settings.toml | from toml) $defaults

  # A cell path errors out on a live file that holds a scalar where the schema has a table.
  $defaults | upsert workspaceBar true | to toml | save --force settings.toml
  nu $script $template generated.json settings.toml $paths
  assert equal (open --raw settings.toml | from toml) $defaults

  cd ..
  rm --recursive --force $work
}
