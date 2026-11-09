#!/usr/bin/env nu

const script_dir = path self .
const root = path self ..
const out = $root | path join "settings-defaults.toml"
const repo_url = "https://github.com/OmniNull/OmniWM"

def swiftly-bin [] {
  $env.SWIFTLY_HOME_DIR? | default ("~/.swiftly" | path expand) | path join "bin"
}

def omniwm-version [] {
  nix eval --raw $"($root)#packages.aarch64-darwin.omniwm.version"
}

# Clones upstream at the packaged tag into <work>/OmniWM and fetches the GhosttyKit binary target.
# Installs upstream's pinned Swift toolchain into ~/.swiftly.
def "main prepare" [work: path] {
  let work = $work | path expand
  let version = omniwm-version
  let checkout = $work | path join "OmniWM"
  print $"preparing OmniWM v($version) in ($checkout)"

  mkdir $work
  git clone --depth 1 --branch $"v($version)" $repo_url $checkout
  cd $checkout

  # the GhosttyKit binary target is not committed; it ships as a release asset
  let ghostty_url = $"($repo_url)/releases/download/v($version)/GhosttyKit.xcframework-v($version).zip"
  let ghostty_zip = $work | path join "ghostty.zip"
  http get $ghostty_url | save --force $ghostty_zip
  mkdir Frameworks
  tar -xf $ghostty_zip -C Frameworks
  ./Scripts/ghostty-preflight.sh verify

  ./Scripts/swift-toolchain.sh
}

# Runs the injected test against a checkout made by `prepare` and writes settings-defaults.toml.
def "main build" [work: path] {
  let work = $work | path expand
  let version = omniwm-version
  let checkout = $work | path join "OmniWM"
  let generated = $work | path join "settings-defaults.toml"
  print $"generating defaults template for OmniWM v($version)"

  cd $checkout
  # `swift test --filter` still compiles every test, so remove upstream's.
  # Fixtures must stay because Package.swift declares it as a resource.
  rm Tests/OmniWMTests/**/*.swift
  cp ($script_dir | path join "GenerateDefaultsTemplateTests.swift") Tests/OmniWMTests/

  # ~/.swiftly/bin/swift is a proxy that picks the toolchain from .swift-version in the checkout
  with-env {
    PATH: ($env.PATH | prepend (swiftly-bin))
    OMNIWM_DEFAULTS_OUT: $generated
    LIBRARY_PATH: (./Scripts/ghostty-preflight.sh print-library-dir)
  } {
    swift --version
    swift test --filter GenerateDefaultsTemplateTests
  }

  [
    $"# Generated from OmniWM v($version) by codegen/generate-defaults.nu"
    (open --raw $generated)
  ]
  | str join "\n"
  | save --force $out

  print $"wrote ($out)"
}

# Regenerates settings-defaults.toml by building upstream at the packaged tag and running an injected test.
# The output is byte-identical to OmniWM's first-launch settings.toml, plus a version header line.
# Runs `prepare` and `build` in a temporary directory; CI calls them as separate steps.
def main [] {
  let work = mktemp --directory

  try {
    main prepare $work
    main build $work
  } catch {|err|
    print --stderr $"error: ($err.rendered)"
    print --stderr $"workdir kept at ($work)"
    exit 1
  }
  rm --recursive --force $work
}
