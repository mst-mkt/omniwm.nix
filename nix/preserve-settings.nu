#!/usr/bin/env nu

# OmniWM ignores a settings file it cannot parse, so neither a missing nor a broken one is worth failing the switch over.
def current-settings [live: path]: nothing -> record {
  if not ($live | path exists) { return {} }

  try { open --raw $live | from toml } catch {
    print --stderr $"warning: ($live) is not valid TOML; nothing is preserved from it"
    {}
  }
}

# Layer the settings OmniWM owns at runtime over the generated ones.
def main [
  generated: path # settings.toml as the module generated it
  live: path # settings.toml as OmniWM currently has it
  out: path # where to write the merged settings
  paths: string # JSON key paths to take from <live>, e.g. [["routing"],["hiddenBar","hiddenBundleIDs"]]
] {
  let current = current-settings $live

  $paths
  | from json
  | reduce --fold (open --raw $generated | from toml) {|path, settings|
      let key = $path | into cell-path
      # A cell path errors out when an intermediate is a scalar rather than missing.
      # A live file that disagrees with the schema then keeps the generated value.
      let value = try { $current | get --optional $key } catch { null }
      if $value == null { $settings } else { $settings | upsert $key $value }
    }
  | to toml
  | save --force $out
}
