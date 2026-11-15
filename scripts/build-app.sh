#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Platzwart
binary_dir="$(swift build -c release --show-bin-path)"
# Im temporären Ordner signieren, bevor ein synchronisierter Projektordner Finder-Metadaten anhängen kann.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
bundle="$stage/Platzwart.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
install -m 755 "$binary_dir/Platzwart" "$bundle/Contents/MacOS/Platzwart"
install -m 644 Resources/Info.plist "$bundle/Contents/Info.plist"
install -m 644 Resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" "$bundle"
codesign --verify --strict "$bundle"
mkdir -p dist
rm -rf dist/Platzwart.app
ditto --norsrc --noextattr "$bundle" dist/Platzwart.app
codesign --verify dist/Platzwart.app
echo "Fertig: dist/Platzwart.app"
