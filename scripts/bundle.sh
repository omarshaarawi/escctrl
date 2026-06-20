#!/usr/bin/env bash
#
# Assembles dist/escctrl.app from the SPM build products and (optionally) code-signs it.
#
# Usage:
#   scripts/bundle.sh [--release] [--universal]
#
# Env:
#   SIGN_IDENTITY  codesign identity. Default "-" (ad-hoc, fine for local use).
#                  Set to a "Developer ID Application: …" identity for distribution.
#   VERSION        marketing version. Default: latest git tag (without leading v), else 0.0.0.
#   BUILD          build number. Default: git commit count, else 1.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="debug"
ARCH_FLAGS=()
for arg in "$@"; do
	case "$arg" in
		--release)   CONFIG="release" ;;
		--universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
		*) echo "unknown flag: $arg" >&2; exit 2 ;;
	esac
done

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

echo "==> Building ($CONFIG${ARCH_FLAGS:+, universal}) v$VERSION ($BUILD)"
swift build "${ARCH_FLAGS[@]}" -c "$CONFIG"
BIN_DIR="$(swift build "${ARCH_FLAGS[@]}" -c "$CONFIG" --show-bin-path)"

APP="$ROOT/dist/escctrl.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"

cp "$BIN_DIR/escctrl" "$APP/Contents/MacOS/escctrl"
cp -R "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
cp "$ROOT/Resources/escctrl.icns" "$APP/Contents/Resources/escctrl.icns"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" \
	"$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"

# Resolve the embedded Sparkle.framework via @rpath, and drop the local toolchain rpath so we
# don't ship a dev path (macOS 13+ has the Swift runtime in the OS, so /usr/lib/swift suffices).
MAIN_BIN="$APP/Contents/MacOS/escctrl"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MAIN_BIN"
for rp in $(otool -l "$MAIN_BIN" | awk '/LC_RPATH/{f=1} f&&/path/{print $2; f=0}' | grep -i Toolchains || true); do
	install_name_tool -delete_rpath "$rp" "$MAIN_BIN"
done

# Code-sign inside-out: nested Sparkle helpers, then the framework, then the app.
echo "==> Signing with identity: $SIGN_IDENTITY"
SIGN_FLAGS=(--force --options runtime --timestamp)
if [ "$SIGN_IDENTITY" = "-" ]; then
	SIGN_FLAGS=(--force)  # ad-hoc: hardened-runtime timestamps need a real identity + network
fi

FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign "${SIGN_FLAGS[@]}" --sign "$SIGN_IDENTITY" "$FW/XPCServices/Downloader.xpc"
codesign "${SIGN_FLAGS[@]}" --sign "$SIGN_IDENTITY" "$FW/XPCServices/Installer.xpc"
codesign "${SIGN_FLAGS[@]}" --sign "$SIGN_IDENTITY" "$FW/Updater.app"
codesign "${SIGN_FLAGS[@]}" --sign "$SIGN_IDENTITY" "$FW/Autoupdate"
codesign "${SIGN_FLAGS[@]}" --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_FLAGS[@]}" --sign "$SIGN_IDENTITY" "$MAIN_BIN"
codesign "${SIGN_FLAGS[@]}" --sign "$SIGN_IDENTITY" "$APP"

echo "==> Verifying"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "==> Done: $APP"
