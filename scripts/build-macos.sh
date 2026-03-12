#!/bin/bash
# Build TenBox for macOS (arm64 + x86_64).
#
# This script builds both architectures in a single run, producing:
#   build/TenBox-arm64.app   + TenBox_{ver}_arm64.zip
#   build/TenBox-x86_64.app  + TenBox_{ver}_x86_64.zip
#
# Usage:
#   ./build-macos.sh [--release|--debug]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
BUILD_TYPE="${1:---release}"
CPU_COUNT=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

case "$BUILD_TYPE" in
    --release)
        CMAKE_BUILD_TYPE="Release"
        SWIFT_CONFIG="release"
        ;;
    --debug)
        CMAKE_BUILD_TYPE="Debug"
        SWIFT_CONFIG="debug"
        ;;
    *)
        echo "Usage: $0 [--release|--debug]"
        exit 1
        ;;
esac

VERSION=$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")
if [ -z "$VERSION" ]; then
    echo "Error: Could not read version from $ROOT_DIR/VERSION"
    exit 1
fi

BUILD_DIR="$ROOT_DIR/build"
MANAGER_SRC="$ROOT_DIR/src/manager-macos"
PLIST="$MANAGER_SRC/Resources/Info.plist"
ENTITLEMENTS="$MANAGER_SRC/Resources/TenBox.entitlements"
TARGET_ARCHS="arm64 x86_64"

echo "===================================="
echo " TenBox macOS Build v$VERSION ($CMAKE_BUILD_TYPE)"
echo " Architectures: $TARGET_ARCHS"
echo "===================================="
echo ""

# Stamp the version into Info.plist before building
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"
echo "Version $VERSION written to Info.plist"
echo ""

# Pre-generate AppIcon.icns once (shared across both architectures)
ICNS_PATH=""
if [ -f "$MANAGER_SRC/Resources/icon.png" ]; then
    ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
    ICNS_PATH="$BUILD_DIR/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    sips -z 16 16     "$MANAGER_SRC/Resources/icon.png" --out "$ICONSET_DIR/icon_16x16.png"      >/dev/null
    sips -z 32 32     "$MANAGER_SRC/Resources/icon.png" --out "$ICONSET_DIR/icon_16x16@2x.png"   >/dev/null
    sips -z 32 32     "$MANAGER_SRC/Resources/icon.png" --out "$ICONSET_DIR/icon_32x32.png"      >/dev/null
    sips -z 64 64     "$MANAGER_SRC/Resources/icon.png" --out "$ICONSET_DIR/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128   "$MANAGER_SRC/Resources/icon.png" --out "$ICONSET_DIR/icon_128x128.png"    >/dev/null
    sips -z 256 256   "$MANAGER_SRC/Resources/icon.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$MANAGER_SRC/Resources/icon.png" --out "$ICONSET_DIR/icon_256x256.png"    >/dev/null
    sips -z 512 512   "$MANAGER_SRC/Resources/icon.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$MANAGER_SRC/Resources/icon.png" --out "$ICONSET_DIR/icon_512x512.png"    >/dev/null
    cp "$MANAGER_SRC/Resources/icon.png"                       "$ICONSET_DIR/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
    rm -rf "$ICONSET_DIR"
    echo "Generated AppIcon.icns from icon.png"
    echo ""
fi

# Pre-compile Metal shaders once (GPU code, architecture-independent)
METALLIB_PATH=""
METAL_SRC="$MANAGER_SRC/Resources/Shaders.metal"
if [ -f "$METAL_SRC" ]; then
    echo "Compiling Metal shaders..."
    mkdir -p "$BUILD_DIR"
    if xcrun metal -c "$METAL_SRC" -o "$BUILD_DIR/Shaders.air" 2>/dev/null && \
       xcrun metallib "$BUILD_DIR/Shaders.air" -o "$BUILD_DIR/default.metallib" 2>/dev/null; then
        METALLIB_PATH="$BUILD_DIR/default.metallib"
        rm -f "$BUILD_DIR/Shaders.air"
        echo "  -> $METALLIB_PATH"
    else
        rm -f "$BUILD_DIR/Shaders.air"
        echo "WARNING: Metal shader compilation failed, will copy .metal source as fallback"
    fi
    echo ""
fi

# Locate Sparkle sign_update tool (available after first SPM resolve)
SIGN_TOOL=""

# Detect codesign identity once
CODESIGN_IDENTITY="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID"; then
    CODESIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID" | head -1 | awk -F'"' '{print $2}')
fi

# ── Build loop: one iteration per architecture ───────────────────────────────
for ARCH in $TARGET_ARCHS; do

echo "####################################################################"
echo "# Building for $ARCH"
echo "####################################################################"
echo ""

CMAKE_DIR="$BUILD_DIR/cmake-$ARCH"
APP_DIR="$BUILD_DIR/TenBox-$ARCH.app"

# ── Step 1: Build tenbox-vm-runtime (C++ via CMake) ──────────────────────
echo "[$ARCH 1/3] Building tenbox-vm-runtime..."
mkdir -p "$CMAKE_DIR"
cd "$CMAKE_DIR"

cmake "$ROOT_DIR" \
    -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_SYSTEM_PROCESSOR="$ARCH"

cmake --build . --target tenbox-vm-runtime -j"$CPU_COUNT"

if [ ! -f "$CMAKE_DIR/tenbox-vm-runtime" ]; then
    echo "Error: tenbox-vm-runtime binary not found after build."
    exit 1
fi
echo "  -> $CMAKE_DIR/tenbox-vm-runtime"

codesign --force --sign - --entitlements "$ENTITLEMENTS" "$CMAKE_DIR/tenbox-vm-runtime"
echo "  -> codesign applied (ad-hoc + Hypervisor entitlement)"

# ── Step 2: Build TenBoxManager (Swift/Obj-C++ via SPM) ─────────────────
echo ""
echo "[$ARCH 2/3] Building TenBoxManager via SPM ($SWIFT_CONFIG, $ARCH)..."

cd "$MANAGER_SRC"
swift build -c "$SWIFT_CONFIG" --arch "$ARCH"

SWIFT_BUILD_DIR="$MANAGER_SRC/.build/apple/Products/$SWIFT_CONFIG"
if [ ! -f "$SWIFT_BUILD_DIR/TenBoxManager" ]; then
    echo "Error: TenBoxManager binary not found at $SWIFT_BUILD_DIR/TenBoxManager"
    exit 1
fi
echo "  -> $SWIFT_BUILD_DIR/TenBoxManager"

# ── Step 3: Assemble TenBox.app bundle ───────────────────────────────────
echo ""
echo "[$ARCH 3/3] Assembling TenBox-$ARCH.app..."

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$PLIST" "$APP_DIR/Contents/Info.plist"

cp "$SWIFT_BUILD_DIR/TenBoxManager" "$APP_DIR/Contents/MacOS/TenBoxManager"
cp "$CMAKE_DIR/tenbox-vm-runtime" "$APP_DIR/Contents/MacOS/tenbox-vm-runtime"

# Copy SPM resource bundles (icon, etc.)
BUNDLE_PATH=$(find -L "$SWIFT_BUILD_DIR" -name "TenBoxManager_TenBoxManager.bundle" -type d 2>/dev/null | head -1)
if [ -n "$BUNDLE_PATH" ] && [ -d "$BUNDLE_PATH" ]; then
    cp -R "$BUNDLE_PATH" "$APP_DIR/Contents/Resources/"
    echo "  -> Copied resource bundle"
else
    echo "WARNING: TenBoxManager_TenBoxManager.bundle not found!"
fi

# Copy pre-built icon
if [ -n "$ICNS_PATH" ] && [ -f "$ICNS_PATH" ]; then
    cp "$ICNS_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "  -> Copied AppIcon.icns"
fi

# Copy pre-compiled Metal shaders (or fallback)
if [ -n "$METALLIB_PATH" ] && [ -f "$METALLIB_PATH" ]; then
    cp "$METALLIB_PATH" "$APP_DIR/Contents/Resources/default.metallib"
    echo "  -> Copied default.metallib"
elif [ -f "$METAL_SRC" ]; then
    cp "$METAL_SRC" "$APP_DIR/Contents/Resources/"
    echo "  -> Copied Shaders.metal (fallback)"
fi

# Copy Sparkle framework from SPM build artifacts
SPARKLE_FRAMEWORK=$(find -L "$MANAGER_SRC/.build/artifacts" -name "Sparkle.framework" -type d 2>/dev/null | head -1)
if [ -n "$SPARKLE_FRAMEWORK" ] && [ -d "$SPARKLE_FRAMEWORK" ]; then
    mkdir -p "$APP_DIR/Contents/Frameworks"
    cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/"
    echo "  -> Copied Sparkle.framework"
fi

install_name_tool -add_rpath "@loader_path/../Frameworks" \
    "$APP_DIR/Contents/MacOS/TenBoxManager" 2>/dev/null || true

# Sign the app bundle
echo "  -> Signing TenBox-$ARCH.app..."
if [ "$CODESIGN_IDENTITY" != "-" ]; then
    echo "     Using: $CODESIGN_IDENTITY"
    codesign --deep --force --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$CODESIGN_IDENTITY" "$APP_DIR"
else
    echo "     Using: ad-hoc (no Developer ID found)"
    codesign --deep --force --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign - "$APP_DIR"
fi

echo ""
echo "  -> $APP_DIR"

# ── Create ZIP for Sparkle updates + EdDSA signature ────────────────────
echo ""
ZIP_PATH="$BUILD_DIR/TenBox_${VERSION}_${ARCH}.zip"
SIGNATURE_PATH="${ZIP_PATH%.zip}.signature"
echo "Creating Sparkle update ZIP ($ARCH)..."
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
echo "  -> $ZIP_PATH"

if [ -z "$SIGN_TOOL" ]; then
    SIGN_TOOL=$(find -L "$MANAGER_SRC/.build/artifacts" -name "sign_update" -type f 2>/dev/null | head -1)
fi
if [ -n "$SIGN_TOOL" ] && [ -x "$SIGN_TOOL" ]; then
    echo ""
    echo "Signing ZIP with Sparkle EdDSA key..."
    ED_SIGNATURE=$("$SIGN_TOOL" "$ZIP_PATH" 2>&1) || true
    echo "$ED_SIGNATURE"
    ED_SIGNATURE_VALUE=$(printf '%s\n' "$ED_SIGNATURE" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' | head -1)
    if [ -n "$ED_SIGNATURE_VALUE" ]; then
        printf '%s\n' "$ED_SIGNATURE_VALUE" > "$SIGNATURE_PATH"
        echo "  -> Signature saved to $SIGNATURE_PATH"
    else
        printf '%s\n' "$ED_SIGNATURE" > "$SIGNATURE_PATH"
        echo "  -> Saved raw sign_update output to $SIGNATURE_PATH"
    fi
    echo ""
    echo "Copy the sparkle:edSignature value above into publish.py when releasing."
else
    echo ""
    echo "WARNING: Sparkle sign_update tool not found."
    echo "  Run 'swift build' once in src/manager-macos to fetch Sparkle artifacts,"
    echo "  then sign manually: sign_update $ZIP_PATH"
fi

echo ""
done
# ── End of build loop ────────────────────────────────────────────────────────

echo "===================================="
echo " Build complete!"
echo "===================================="
echo ""
echo "Artifacts:"
for ARCH in $TARGET_ARCHS; do
    echo "  App:  $BUILD_DIR/TenBox-$ARCH.app"
    echo "  ZIP:  $BUILD_DIR/TenBox_${VERSION}_${ARCH}.zip"
    SIG="$BUILD_DIR/TenBox_${VERSION}_${ARCH}.signature"
    if [ -f "$SIG" ]; then
        echo "  Sig:  $SIG"
    fi
    echo ""
done
echo "To create a DMG for distribution:"
for ARCH in $TARGET_ARCHS; do
    echo "  $SCRIPT_DIR/make-dmg.sh $BUILD_DIR/TenBox-$ARCH.app"
done
echo ""
