#!/usr/bin/env nu

const script_dir = path self .
const root = path self ..
const out = $root | path join "settings-defaults.toml"
const repo_url = "https://github.com/BarutSRB/OmniWM"

# Regenerates settings-defaults.toml by building upstream at the packaged tag and running an injected test.
# The output is byte-identical to OmniWM's first-launch settings.toml, plus a version header line.
# Requires macOS with an Xcode matching upstream's swift-tools-version.
def main [] {
  let version = nix eval --raw $"($root)#packages.aarch64-darwin.omniwm.version"
  print $"generating defaults template for OmniWM v($version)"

  let work = mktemp --directory
  let checkout = $work | path join "OmniWM"
  let generated = $work | path join "settings-defaults.toml"

  try {
    git clone --depth 1 --branch $"v($version)" $repo_url $checkout

    # scope cd to this block so the trailing rm can remove $work
    do {
      cd $checkout

      # the GhosttyKit binary target is not committed; it ships as a release asset
      let ghostty_url = $"($repo_url)/releases/download/v($version)/GhosttyKit.xcframework-v($version).zip"
      let ghostty_zip = $work | path join "ghostty.zip"
      http get $ghostty_url | save $ghostty_zip
      mkdir Frameworks
      tar -xf $ghostty_zip -C Frameworks
      ./Scripts/ghostty-preflight.sh verify

      cp ($script_dir | path join "GenerateDefaultsTemplateTests.swift") Tests/OmniWMTests/

      with-env {
        OMNIWM_DEFAULTS_OUT: $generated
        LIBRARY_PATH: (./Scripts/ghostty-preflight.sh print-library-dir)
      } {
        swift test --filter GenerateDefaultsTemplateTests
      }
    }

    [
      $"# Generated from OmniWM v($version) by codegen/generate-defaults.nu"
      (open --raw $generated)
    ] | str join "\n" | save --force $out
    print $"wrote ($out)"
  } catch { |err|
    print --stderr $"error: ($err.rendered)"
    print --stderr $"workdir kept at ($work)"
    exit 1
  }
  rm --recursive --force $work
}
