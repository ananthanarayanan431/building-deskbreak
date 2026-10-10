#!/usr/bin/env bash
# Builds DeskBreak.app from source and signs it ad hoc.
#
# Usage: scripts/build-app.sh [--output DIR]
#   --output DIR   where to place DeskBreak.app (default: ./build)
#
# Environment:
#   SWIFT_BUILD_FLAGS  extra flags for `swift build` (the Homebrew formula passes --disable-sandbox)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DeskBreak"
OUTPUT_DIR="$ROOT/build"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 && -n "$2" ]] || { echo "error: --output needs a directory" >&2; exit 64; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,9p' "$0"
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: VERSION must look like 1.2.3, got '$VERSION'" >&2
  exit 65
fi

# shellcheck disable=SC2206 # intentional word splitting of extra flags
EXTRA_FLAGS=(${SWIFT_BUILD_FLAGS:-})

echo "==> Building $APP_NAME $VERSION (release)"
swift build --package-path "$ROOT" -c release --product "$APP_NAME" ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"}
BIN_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"})"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
APP="$OUTPUT_DIR/$APP_NAME.app"

echo "==> Assembling $APP"
# Only ever removes the bundle this script itself produces.
if [[ -d "$APP" ]]; then
  rm -rf -- "$APP"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
chmod 755 "$APP/Contents/MacOS/$APP_NAME"
sed "s/__VERSION__/$VERSION/g" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing ad hoc"
# Hardened runtime adds protection at no cost; no entitlements are requested.
codesign --force --sign - --options runtime --timestamp=none "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo "==> Built $APP"
