#!/bin/bash
# Builds the kodierer GUI as a double-clickable macOS app: build/KodiererApp.app
# (SwiftPM executables run fine via `swift run KodiererApp`, but an .app bundle
# gets a dock icon, proper activation and the local-network permission prompt.)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> building KodiererApp (release)…"
swift build -c release --product KodiererApp
BIN_DIR="$(swift build -c release --product KodiererApp --show-bin-path)"

APP="build/KodiererApp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/KodiererApp" "$APP/Contents/MacOS/KodiererApp"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>KodiererApp</string>
	<key>CFBundleIdentifier</key>
	<string>com.kdekorte.kodierer</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>kodierer</string>
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
