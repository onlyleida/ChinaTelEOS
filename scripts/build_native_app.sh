#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/cloudbox-clang-cache"
export SWIFTPM_CUSTOM_CACHE_PATH="${TMPDIR:-/private/tmp}/cloudbox-swiftpm-cache"

CONFIGURATION="${1:-release}"
case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "usage: $0 [debug|release]" >&2
    exit 1
    ;;
esac

swift build -c "$CONFIGURATION"

APP_DIR="build/翼存 CloudBox.app"
CONTENTS="$APP_DIR/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/$CONFIGURATION/CloudBox" "$CONTENTS/MacOS/CloudBox"
cp "NativeCloudBox/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "NativeCloudBox/Resources/CloudBox.icns" "$CONTENTS/Resources/CloudBox.icns"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
