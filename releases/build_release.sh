#!/bin/bash
set -e

# RightLayout Release Builder
# Creates .app bundle and .pkg installer for distribution

APP_NAME="RightLayout"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Read version from VERSION file or use argument
if [ -n "$1" ] && [ "$1" != "--publish" ]; then
    VERSION="$1"
else
    VERSION=$(cat "$PROJECT_DIR/VERSION" | tr -d '[:space:]')
fi

BUILD_DIR="$SCRIPT_DIR/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
PKG_PATH="$SCRIPT_DIR/$APP_NAME-$VERSION.pkg"

echo "🚀 Building $APP_NAME v$VERSION"
echo "================================"

# Sync repo-level version metadata used by local runs and bundled builds.
"$PROJECT_DIR/scripts/sync_version.sh" "$VERSION"

# Clean
rm -rf "$BUILD_DIR"
rm -rf "$PROJECT_DIR/.build"
mkdir -p "$BUILD_DIR"

# Build release binary
echo "📦 Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

BINARY_PATH=""
for candidate in \
    "$PROJECT_DIR/.build/release/RightLayoutApp" \
    "$PROJECT_DIR/.build/arm64-apple-macosx/release/RightLayoutApp" \
    "$PROJECT_DIR/.build/release/RightLayout" \
    "$PROJECT_DIR/.build/arm64-apple-macosx/release/RightLayout"
do
    if [ -f "$candidate" ]; then
        BINARY_PATH="$candidate"
        break
    fi
done

if [ -z "$BINARY_PATH" ]; then
    echo "❌ Release binary not found in .build output"
    exit 1
fi

# Create .app bundle structure
echo "📁 Creating app bundle..."
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Copy binary
cp "$BINARY_PATH" "$APP_PATH/Contents/MacOS/$APP_NAME"

# Copy resource bundle (required by Swift Package Manager)
BUNDLE_PATH="$PROJECT_DIR/.build/release/RightLayout_RightLayout.bundle"
if [ -d "$BUNDLE_PATH" ]; then
    cp -r "$BUNDLE_PATH" "$APP_PATH/"
fi

# Copy icon
ICON_SRC="$PROJECT_DIR/RightLayout/Assets.xcassets/AppIcon.appiconset/icon_512.png"
if [ -f "$ICON_SRC" ]; then
    mkdir -p "$BUILD_DIR/icon.iconset"
    sips -z 16 16 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ICON_SRC" --out "$BUILD_DIR/icon.iconset/icon_512x512.png" >/dev/null
    cp "$PROJECT_DIR/RightLayout/Assets.xcassets/AppIcon.appiconset/icon_1024.png" "$BUILD_DIR/icon.iconset/icon_512x512@2x.png"
    iconutil -c icns "$BUILD_DIR/icon.iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
    rm -rf "$BUILD_DIR/icon.iconset"
fi

# Create Info.plist
cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.chernistry.rightlayout</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
EOF

echo "✅ App bundle created: $APP_PATH"

# Create PKG installer
echo "📦 Creating PKG installer..."
rm -f "$PKG_PATH"

# Build pkg - app goes directly to /Applications
pkgbuild \
    --root "$APP_PATH" \
    --identifier "com.chernistry.rightlayout" \
    --version "$VERSION" \
    --install-location "/Applications/RightLayout.app" \
    --scripts "$SCRIPT_DIR/pkg_scripts" \
    "$PKG_PATH"

echo "✅ PKG created: $PKG_PATH"
echo ""
echo "================================"
echo "📦 Release artifacts:"
echo "   App: $APP_PATH"
echo "   PKG: $PKG_PATH"
echo ""
echo "To install: Double-click the PKG file"

# Publish to GitHub releases repo if --publish flag is passed
if [ "$2" = "--publish" ] || [ "$1" = "--publish" ]; then
    echo ""
    echo "🚀 Publishing to GitHub..."
    
    RELEASES_REPO="chernistry/RightLayout"
    TAG="v$VERSION"
    
    # Check if release already exists
    if gh release view "$TAG" --repo "$RELEASES_REPO" >/dev/null 2>&1; then
        echo "⚠️  Release $TAG already exists. Deleting and recreating..."
        gh release delete "$TAG" --repo "$RELEASES_REPO" --yes
    fi
    
    # Create release with PKG
    gh release create "$TAG" "$PKG_PATH" \
        --repo "$RELEASES_REPO" \
        --title "RightLayout $TAG" \
        --notes "## RightLayout $TAG

Download and run the installer.

**Requirements:** macOS 13.0+

**Feedback:** [GitHub Issues](https://github.com/chernistry/RightLayout/issues)"
    
    echo "✅ Published to https://github.com/$RELEASES_REPO/releases/tag/$TAG"
fi
