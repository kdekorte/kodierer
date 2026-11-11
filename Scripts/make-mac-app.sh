#!/bin/bash
# Builds the esys GUI as a double-clickable macOS app: build/EsysApp.app
# (SwiftPM executables run fine via `swift run EsysApp`, but an .app bundle
# gets a dock icon, proper activation and the local-network permission prompt.)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> building EsysApp (release)…"
swift build -c release --product EsysApp
BIN_DIR="$(swift build -c release --product EsysApp --show-bin-path)"

APP="build/EsysApp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/EsysApp" "$APP/Contents/MacOS/EsysApp"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>EsysApp</string>
	<key>CFBundleIdentifier</key>
	<string>com.kdekorte.esys</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>esys</string>
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
	<string>esys talks to your BMW's diagnostic gateway over the local network (ENET cable).</string>
</dict>
</plist>
EOF

echo "==> built $APP"
echo "    run it with: open $APP"
