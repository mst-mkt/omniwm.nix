#!/usr/bin/env nu

# OmniWM ignores a settings file it cannot parse, so neither a missing nor a broken one is worth failing the switch over.
def current-settings [live: path]: nothing -> record {
  if not ($live | path exists) { return {} }

  try { open --raw $live | from toml } catch {
    print --stderr $"warning: ($live) is not valid TOML; nothing is preserved from it"
    {}
  }
}

# Stands in for Home Manager's `run`, which nushell cannot call: on a dry run, print the command instead of running it.
def run-or-print [dry_run: bool, command: list<string>] {
  if $dry_run {
    print ($command | str join " ")
  } else {
    run-external ...$command
  }
}

# Write the generated settings to <live>, with the settings OmniWM owns at runtime layered over them.
def main [
  generated_toml: path # the settings the module generated, written as-is when <paths> is empty
  generated_json: path # the same settings as JSON, to layer the preserved ones over
  live: path # settings.toml as OmniWM currently has it
  paths: string # JSON key paths to take from <live>, e.g. [["routing"],["hiddenBar","hiddenBundleIDs"]]
  --dry-run # print the commands that would change <live> instead of running them
] {
  let live = $live | path expand --no-symlink
  let paths = $paths | from json

  let settings = if ($paths | is-empty) {
    open --raw $generated_toml
  } else {
    let current = current-settings $live
    let preserved = $paths
      | reduce --fold { } {|path, acc|
          let key = $path | into cell-path
          let value = try { $current | get --optional $key } catch { null }
          if $value == null { $acc } else { $acc | upsert $key $value }
        }

    open --raw $generated_json
    | from json
    | merge deep --strategy=overwrite $preserved
    | to toml
  }

  if ($live | path exists) and (open --raw $live) == $settings { return }

  let source = mktemp --tmpdir omniwm-settings.XXXXXX
  $settings | save --force $source
  run-or-print $dry_run [mkdir -p ($live | path dirname)]
  # install unlinks the destination first, so a symlinked .bak never has its target overwritten.
  if ($live | path exists) {
    run-or-print $dry_run [install -T -m 644 $live $"($live).bak"]
  }
  # OmniWM reloads on every change without debounce, so replace the file atomically.
  run-or-print $dry_run [install -T -m 644 $source $"($live).tmp"]
  run-or-print $dry_run [mv -fT $"($live).tmp" $live]
  rm $source
}
