#!/bin/sh
# Builds SCDesktop.app against the macOS 26 SDK (needed for Liquid Glass).
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build -c release --product SCDesktop
APP=build/SCDesktop.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SCDesktop "$APP/Contents/MacOS/SCDesktop"
swift Scripts/make-icon.swift "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SCDesktop</string>
    <key>CFBundleIdentifier</key><string>dev.local.SCDesktop</string>
    <key>CFBundleName</key><string>SoundCloud</string>
    <key>CFBundleDisplayName</key><string>SoundCloud</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>UIDesignRequiresCompatibility</key><false/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
