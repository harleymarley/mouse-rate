#!/bin/bash
# Builds "Mouse Rate.app" (Apple silicon + Intel) and MouseRate.dmg.
# Needs a Mac with the Xcode Command Line Tools (xcode-select --install). No Xcode project needed.
#
#   ./scripts/build.sh                 # version 1.0.1
#   VERSION=1.2.0 ./scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.1}"
REPO_URL="${REPO_URL:-https://github.com/harleymarley/mouse-rate}"
SITE_URL="${SITE_URL:-https://mouse.almostperfecttech.com}"
# The mouse video. Until it's published this points at the channel; put the video link here when it's live.
VIDEO_URL="${VIDEO_URL:-https://www.youtube.com/@AlmostPerfectReviews}"
APP_NAME="Mouse Rate"
EXE="MouseRate"
OUT="build"
# Assemble and sign in a temporary folder outside Desktop/Documents. iCloud Drive and Finder
# add hidden file attributes there, and codesign refuses to sign files that carry them.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mouserate.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/$APP_NAME.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$OUT"; mkdir -p "$OUT" "$WORK/src"
cp Sources/*.swift "$WORK/src/"
# stamp version and links into the build copy only
sed -i '' -e "s|static let version = \".*\"|static let version = \"$VERSION\"|" \
          -e "s|static let repoURL = \".*\"|static let repoURL = \"$REPO_URL\"|" \
          -e "s|static let siteURL = \".*\"|static let siteURL = \"$SITE_URL\"|" \
          -e "s|static let videoURL = \".*\"|static let videoURL = \"$VIDEO_URL\"|" \
          -e "s|static let built = \".*\"|static let built = \"$(date '+%b %-d, %-I:%M %p')\"|" "$WORK/src/AppConfig.swift"

for ARCH in arm64 x86_64; do
  echo "Compiling for $ARCH"
  swiftc -O -parse-as-library -sdk "$SDK" -target "$ARCH-apple-macos13.0" \
    "$WORK"/src/*.swift -o "$WORK/$EXE-$ARCH"
done
lipo -create "$WORK/$EXE-arm64" "$WORK/$EXE-x86_64" -output "$WORK/$EXE"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$WORK/$EXE" "$APP/Contents/MacOS/$EXE"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Strip hidden attributes (Finder info, quarantine, iCloud) so codesign accepts the bundle.
xattr -cr "$APP"

# Ad-hoc signature (free). Apple silicon needs at least this to run the app.
# To sign with a Developer ID later, set SIGN_ID="Developer ID Application: ..." and notarize.
codesign --force --options runtime --timestamp=none --sign "${SIGN_ID:--}" "$APP"
codesign --verify --verbose "$APP"

# Quit any running copy, then eject any Mouse Rate disk image that's still mounted,
# so an old one can't be opened by mistake.
if [ "${CI:-}" != "true" ]; then
  osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
  pkill -x "$EXE" >/dev/null 2>&1 || true
fi
for VOL in /Volumes/"$APP_NAME"*; do
  [ -d "$VOL" ] && hdiutil detach "$VOL" -force >/dev/null 2>&1 || true
done

# Disk image with a shortcut to Applications, so people can drag the app in.
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$OUT/MouseRate.dmg"
shasum -a 256 "$OUT/MouseRate.dmg" | tee "$OUT/MouseRate.dmg.sha256"
cp -R "$APP" "$OUT/"
echo "Done: $OUT/MouseRate.dmg"

# Local builds: replace the copy in Applications with this one and open it.
# (CI sets CI=true and skips this.)
if [ "${CI:-}" != "true" ] && [ "${INSTALL:-1}" = "1" ]; then
  echo "Installing to /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  ditto "$APP" "/Applications/$APP_NAME.app"
  # Tell macOS to forget any older copies so Spotlight and the Dock open this one.
  LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSREG" -f "/Applications/$APP_NAME.app" >/dev/null 2>&1 || true
  # A rebuilt app has a new signature, so the old Input Monitoring entry no longer matches it.
  tccutil reset ListenEvent com.almostperfecttech.mouserate >/dev/null 2>&1 || true
  open "/Applications/$APP_NAME.app"
  echo "Opened /Applications/$APP_NAME.app"
fi
