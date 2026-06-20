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
UNIVERSAL=0
for arg in "$@"; do
	case "$arg" in
		--release)   CONFIG="release" ;;
		--universal) UNIVERSAL=1 ;;
		*) echo "unknown flag: $arg" >&2; exit 2 ;;
	esac
done

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

if [ "$UNIVERSAL" = "1" ]; then
	# Build each arch with the normal (llbuild) backend and lipo them together. The multi-arch
	# `swift build --arch arm64 --arch x86_64` path routes through XCBuild, which breaks on some
	# toolchains ("SWIFT_VERSION '' is unsupported", "Unexpected duplicate tasks") — notably the
	# Xcode on GitHub's macos runners.
	echo "==> Building universal ($CONFIG) v$VERSION ($BUILD)"
	swift build -c "$CONFIG" --arch arm64
	swift build -c "$CONFIG" --arch x86_64
	PRODUCTS_DIR="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"
	X86_DIR="$(swift build -c "$CONFIG" --arch x86_64 --show-bin-path)"
	BIN_PATH="$PRODUCTS_DIR/escctrl.universal"
	lipo -create -output "$BIN_PATH" "$PRODUCTS_DIR/escctrl" "$X86_DIR/escctrl"
else
	echo "==> Building ($CONFIG) v$VERSION ($BUILD)"
	swift build -c "$CONFIG"
	PRODUCTS_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
	BIN_PATH="$PRODUCTS_DIR/escctrl"
fi

APP="$ROOT/dist/escctrl.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"

cp "$BIN_PATH" "$APP/Contents/MacOS/escctrl"
cp -R "$PRODUCTS_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
cp "$ROOT/Resources/escctrl.icns" "$APP/Contents/Resources/escctrl.icns"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" \
	"$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"

# Resolve the embedded Sparkle.framework via @rpath. (The build also leaves a toolchain rpath in
# the binary; it's harmless dead weight since macOS 13+ resolves the Swift runtime from the OS via
# the /usr/lib/swift rpath, so we leave it rather than fight install_name_tool on a fat binary.)
MAIN_BIN="$APP/Contents/MacOS/escctrl"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MAIN_BIN"

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
