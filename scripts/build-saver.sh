#!/bin/bash
# Builds the Folio screen saver into .build/<configuration>/Soprano.saver.
# Usage: build-saver.sh <debug|release>
#
# The saver is one swiftc module (SopranoSaver) linked as an MH_BUNDLE: Saver/*.swift plus
# Soprano's vendored Theme.swift, NSColor+Hex.swift and Chrome.swift (colours and fonts from
# the single source) and Core's SaverClock.swift. Info.plist comes from Saver/Info.plist with
# the version of Support/Info.plist, the app's single source of truth.
#
# Signed ad hoc: Apple's legacyScreenSaver host loads third-party savers without library
# validation, and a saver holds no keychain items or privacy permissions that would need a
# stable designated requirement, so the family identity buys nothing here. The app that
# carries the saver in Contents/Resources is signed with the family identity by sign-app.sh.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <debug|release>" >&2
    exit 2
fi

configuration="$1"
case "$configuration" in
    debug) optimization=(-Onone) ;;
    release) optimization=(-O) ;;
    *)
        echo "Unsupported build configuration: $configuration" >&2
        exit 2
        ;;
esac

export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export PATH="/opt/homebrew/opt/swift/bin:$PATH"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
build_dir="$repo_root/.build/$configuration"
output_saver="$build_dir/Soprano.saver"

info_template="$repo_root/Saver/Info.plist"
app_info_plist="$repo_root/Support/Info.plist"
vendored_dir="$repo_root/Sources/SopranoDesktop/Vendored"
sources=(
    "$repo_root"/Saver/*.swift
    "$vendored_dir/Theme.swift"
    "$vendored_dir/NSColor+Hex.swift"
    "$vendored_dir/Chrome.swift"
    "$repo_root/Sources/SopranoDesktopCore/SaverClock.swift"
)

for required_path in "$info_template" "$app_info_plist" "${sources[@]}"; do
    if [[ ! -e "$required_path" ]]; then
        echo "Missing screen saver input: $required_path" >&2
        exit 1
    fi
done

mkdir -p "$build_dir"
stage_dir="$(mktemp -d "$build_dir/.soprano-saver.XXXXXX")"
cleanup() {
    rm -rf "$stage_dir"
}
trap cleanup EXIT

staged_saver="$stage_dir/Soprano.saver"
mkdir -p "$staged_saver/Contents/MacOS" "$staged_saver/Contents/Resources"

swiftc \
    -module-name SopranoSaver \
    -target arm64-apple-macos14.0 \
    -swift-version 6 \
    "${optimization[@]}" \
    -parse-as-library \
    -emit-library \
    -Xlinker -bundle \
    -framework AppKit \
    -framework ScreenSaver \
    -module-cache-path "$stage_dir/ModuleCache" \
    -o "$staged_saver/Contents/MacOS/Soprano" \
    "${sources[@]}"

staged_plist="$staged_saver/Contents/Info.plist"
cp "$info_template" "$staged_plist"
for key in CFBundleShortVersionString CFBundleVersion; do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$app_info_plist")"
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$staged_plist"
done

/usr/bin/codesign --force --sign - "$staged_saver"
/usr/bin/codesign --verify --strict "$staged_saver"

rm -rf "$output_saver"
mv "$staged_saver" "$output_saver"
echo "Built $output_saver"
