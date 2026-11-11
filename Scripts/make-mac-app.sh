#!/bin/bash
# Builds the kodierer GUI as a double-clickable macOS app: build/Kodierer.app
# (SwiftPM executables run fine via `swift run Kodierer`, but an .app bundle
# gets a dock icon, proper activation and the local-network permission prompt.)
# The kodierer-cli command line tool is bundled next to the GUI binary, so the
# app package works without a SwiftPM checkout.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> building Kodierer + kodierer-cli (release)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Kodierer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Kodierer" "$APP/Contents/MacOS/Kodierer"
cp "$BIN_DIR/kodierer-cli" "$APP/Contents/MacOS/kodierer-cli"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Kodierer</string>
	<key>CFBundleIdentifier</key>
	<string>com.kdekorte.kodierer</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Kodierer</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSLocalNetworkUsageDescription</key>
	<string>kodierer talks to your BMW's diagnostic gateway over the local network (ENET cable).</string>
</dict>
</plist>
EOF

echo "==> built $APP"
echo "    run it with: open $APP"
echo "    bundled CLI: $APP/Contents/MacOS/kodierer-cli"
