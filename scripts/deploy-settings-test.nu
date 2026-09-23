use std/assert
use std/testing *

const script = path self deploy-settings.nu
const template = path self ../settings-defaults.toml
const paths = '[["monitorGapOverrides"],["monitors"],["routing"],["workspaceBar","iconOverrides"]]'

@before-each
def setup []: nothing -> record {
  let dir = mktemp --directory
  let defaults = open --raw $template | from toml
  $defaults | to toml | save ($dir | path join generated.toml)
  $defaults | to json | save ($dir | path join generated.json)

  let gui = {
    monitorGapOverrides: [{ displayId: "37D8832A-2D66-02CA-B9F7-8F30A301B230", gap: 8.0 }]
    monitors: { ranking: ["37D8832A-2D66-02CA-B9F7-8F30A301B230"] }
    routing: { arrangements: [], mode: "custom" }
    workspaceBar: ($defaults.workspaceBar
      | upsert iconOverrides { "com.apple.Safari": "safari" }
      | upsert height 99.0)
  }

  {
    dir: $dir
    path: ($dir | path join settings.toml)
    defaults: $defaults
    gui: $gui
    gui_toml: ($defaults | merge $gui | to toml)
  }
}

@after-each
def cleanup [] {
  rm --recursive --force $in.dir
}

def deploy [context: record, --paths: string = $paths, --dry-run]: nothing -> string {
  let flags = if $dry_run { [--dry-run] } else { [] }
  let result = ^$nu.current-exe --no-config-file $script ...$flags ($context.dir | path join generated.toml) ($context.dir | path join generated.json) $context.path $paths
    | complete
  if $result.exit_code != 0 { error make { msg: $result.stderr } }
  $result.stdout
}

@test
def "layers the preserved paths over the generated settings" [] {
  let context = $in
  $context.gui_toml | save $context.path

  deploy $context

  let merged = open --raw $context.path | from toml
  assert equal $merged.monitorGapOverrides $context.gui.monitorGapOverrides
  assert equal $merged.monitors $context.gui.monitors
  assert equal $merged.routing $context.gui.routing
  assert equal $merged.workspaceBar.iconOverrides $context.gui.workspaceBar.iconOverrides
  assert equal $merged.workspaceBar.height $context.defaults.workspaceBar.height
  assert equal $merged.appearance.mode $context.defaults.appearance.mode
}

@test
def "keeps floats as floats and array-of-tables headers without spaces" [] {
  let context = $in
  $context.gui_toml | save $context.path

  deploy $context

  let merged = open --raw $context.path
  # A float that looks like an integer stays a float through JSON.
  assert equal ($merged | from toml | get borders.width | describe) "float"
  assert str contains $merged "[[monitorGapOverrides]]"
}

@test
def "keeps the previous file as .bak" [] {
  let context = $in
  $context.gui_toml | save $context.path

  deploy $context

  assert equal (open --raw $"($context.path).bak") $context.gui_toml
  assert not ($"($context.path).tmp" | path exists)
}

@test
def "writes nothing when the merge matches the file in place" [] {
  let context = $in
  $context.gui_toml | save $context.path
  # Bring the file in line with the merge first.
  deploy $context
  "previous" | save --force $"($context.path).bak"

  deploy $context

  assert equal (open --raw $"($context.path).bak") "previous"
}

@test
def "writes nothing when OmniWM has laid out the same values its own way" [] {
  let context = $in
  cp $template $context.path
  assert not equal (open --raw $context.path) (open --raw ($context.dir | path join generated.toml))

  deploy $context --paths '[]'
  deploy $context

  assert equal (open --raw $context.path) (open --raw $template)
  assert not ($"($context.path).bak" | path exists)
}

@test
def "treats an integer from Nix and the equal float from OmniWM as the same value" [] {
  let context = $in
  $context.defaults | upsert borders.width 4.0 | to toml | save $context.path
  let before = open --raw $context.path
  $context.defaults | upsert borders.width 4 | to json | save --force ($context.dir | path join generated.json)

  deploy $context

  assert equal (open --raw $context.path) $before
  assert not ($"($context.path).bak" | path exists)
}

@test
def "rewrites a value outside the preserved paths" [] {
  let context = $in
  $context.defaults | upsert appearance.mode "changed" | to toml | save $context.path

  deploy $context

  assert equal (open --raw $context.path | from toml) $context.defaults
}

@test
def "changes nothing on a dry run" [] {
  let context = $in
  $context.gui_toml | save $context.path

  deploy $context --dry-run

  assert equal (open --raw $context.path) $context.gui_toml
}

@test
def "keeps the keys a newer schema adds to a preserved table" [] {
  let context = $in
  $context.defaults | upsert routing { mode: "custom" } | to toml | save $context.path

  deploy $context

  let upgraded = open --raw $context.path | from toml
  assert equal $upgraded.routing.mode "custom"
  assert equal $upgraded.routing.arrangements $context.defaults.routing.arrangements
}

@test
def "creates a missing file and its directory" [] {
  let context = $in
  let path = $context.dir | path join absent settings.toml

  deploy ($context | upsert path $path)

  assert equal (open --raw $path | from toml) $context.defaults
  assert not ($"($path).bak" | path exists)
}

@test
def "writes the generated TOML byte for byte when nothing is preserved" [] {
  let context = $in
  $context.gui_toml | save $context.path

  deploy $context --paths '[]'

  assert equal (open --raw $context.path) (open --raw ($context.dir | path join generated.toml))
}

@test
def "replaces a symlink instead of writing through it" [] {
  let context = $in
  let target = $context.dir | path join target.toml
  "target" | save $target
  ^ln -s $target $context.path

  deploy $context --paths '[]'

  assert equal (open --raw $target) "target"
  assert equal ($context.path | path type) "file"
  assert equal (open --raw $"($context.path).bak") "target"
}

@test
def "replaces a file that is not valid TOML" [] {
  let context = $in
  "= not toml" | save $context.path

  deploy $context

  assert equal (open --raw $context.path | from toml) $context.defaults
}

# A cell path errors out on a live file that holds a scalar where the schema has a table.
@test
def "ignores a preserved path under a scalar" [] {
  let context = $in
  $context.defaults | upsert workspaceBar true | to toml | save $context.path

  deploy $context

  assert equal (open --raw $context.path | from toml) $context.defaults
}
