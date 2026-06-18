#!/usr/bin/env bash
#
# Build → sign (Developer ID + hardened runtime) → notarize → staple → DMG.
# Distribution channel: Developer ID + notarization (NOT the Mac App Store).
#
# One-time setup on your Mac:
#   1) Join the Apple Developer Program ($99/yr) and create a
#      "Developer ID Application" certificate (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates).
#   2) Make an app-specific password at appleid.apple.com, then store notary credentials once:
#        xcrun notarytool store-credentials AgentStudioNotary \
#          --apple-id "you@example.com" --team-id "YOURTEAMID" --password "abcd-efgh-ijkl-mnop"
#
# Run:
#   SIGN_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)" ./tools/notarize.sh
#
set -euo pipefail

APP_NAME="AgentStudio"
SCHEME="AgentStudio"
CONFIG="Release"
ENTITLEMENTS="AgentStudio/AgentStudio.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-AgentStudioNotary}"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY, e.g. 'Developer ID Application: Your Name (TEAMID)'}"

cd "$(dirname "$0")/.."          # → the app/ directory
BUILD_DIR="build/release"
DIST_DIR="dist"

echo "▸ Regenerating project + building $CONFIG…"
xcodegen generate >/dev/null
xcodebuild -project AgentStudio.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR" -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build >/dev/null

SRC_APP="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"
mkdir -p "$DIST_DIR"
APP="$DIST_DIR/$APP_NAME.app"
rm -rf "$APP"; cp -R "$SRC_APP" "$APP"

echo "▸ Signing with $SIGN_IDENTITY (hardened runtime + secure timestamp)…"
sign() { codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$@"; }
# Sparkle ships nested helpers/XPC services that must be signed from the inside out
# (a single --deep can leave them improperly signed and fail notarization).
FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FW" ]; then
  V="$FW/Versions/B"
  for p in \
    "$V/XPCServices/Installer.xpc" \
    "$V/XPCServices/Downloader.xpc" \
    "$V/Autoupdate" \
    "$V/Updater.app" \
    "$FW"; do
    [ -e "$p" ] && sign "$p"
  done
fi
# Then the app itself (entitlements only apply to the main bundle).
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "▸ Submitting to Apple notary service (this can take a few minutes)…"
ZIP="$DIST_DIR/$APP_NAME-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$ZIP"

echo "▸ Stapling the notarization ticket…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP" || true   # should print: accepted, source=Notarized Developer ID

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
echo "▸ Building $DMG…"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null

# Code-sign the DMG container with Developer ID, so `spctl` and offline Gatekeeper checks pass
# cleanly (not just the notarization ticket).
echo "▸ Signing the DMG…"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

# Notarize + staple the DMG itself too, so the downloaded .dmg passes Gatekeeper without a warning
# (stapling the inner .app isn't enough for the container). Must happen BEFORE generate_appcast,
# since stapling rewrites the DMG and would otherwise invalidate the EdDSA signature in the appcast.
echo "▸ Notarizing + stapling the DMG…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG" || true

# Sparkle: if the tools are available, refresh the appcast (signs the FINAL stapled DMG).
if [ -n "${SPARKLE_BIN:-}" ] && [ -x "$SPARKLE_BIN/generate_appcast" ]; then
  echo "▸ Updating Sparkle appcast…"
  "$SPARKLE_BIN/generate_appcast" "$DIST_DIR"
  echo "   → upload $DIST_DIR/*.dmg and $DIST_DIR/appcast.xml to your SUFeedURL host."
fi

echo "✅ Done. Ship: $DMG"
