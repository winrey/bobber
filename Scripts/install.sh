#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Bobber"
INSTALL_DIR="/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"
REPO="winrey/bobber"
BRANCH="main"

echo "=== Bobber Installer ==="

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: Bobber only runs on macOS"
    exit 1
fi

# Check for swift
if ! command -v swift &>/dev/null; then
    echo "Error: Swift not found. Install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

# Clone or update
TMPDIR_BUILD="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BUILD"' EXIT

echo "Downloading Bobber..."
git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$TMPDIR_BUILD/bobber" 2>&1 | tail -1

echo "Building (release)..."
cd "$TMPDIR_BUILD/bobber"
swift build -c release 2>&1 | tail -3

# Assemble .app bundle
echo "Installing to $APP_PATH..."
RELEASE_BINARY="$TMPDIR_BUILD/bobber/.build/arm64-apple-macosx/release/$APP_NAME"
BUNDLE_DIR="$TMPDIR_BUILD/bobber/.build/$APP_NAME.app"

mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"
cp "$RELEASE_BINARY" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"
cp "$TMPDIR_BUILD/bobber/Resources/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"

# Info.plist
cat > "$BUNDLE_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Bobber</string>
    <key>CFBundleIdentifier</key>
    <string>com.weightwave.bobber</string>
    <key>CFBundleName</key>
    <string>Bobber</string>
    <key>CFBundleVersion</key>
    <string>0.1.3</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.3</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST

# Ad-hoc sign
codesign --force --deep -s - "$BUNDLE_DIR" 2>/dev/null || true

# Remove old install, copy new
if [ -d "$APP_PATH" ]; then
    pkill -f "MacOS/Bobber" 2>/dev/null || true
    sleep 1
    rm -rf "$APP_PATH"
fi
cp -R "$BUNDLE_DIR" "$APP_PATH"

# Remove quarantine
xattr -cr "$APP_PATH" 2>/dev/null || true

echo ""
echo "=== Bobber installed to $APP_PATH ==="
echo ""
echo "Launching..."
open "$APP_PATH"
echo "Done! Open Bobber settings to install the Claude Code plugin."