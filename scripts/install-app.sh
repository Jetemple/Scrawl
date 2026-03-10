#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [install-dir]"
    echo "Example: $0 \"$HOME/Applications\""
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_DISPLAY_NAME="Scrawl"
APP_BUNDLE_NAME="${APP_DISPLAY_NAME}.app"
EXECUTABLE_TARGET="ScrawlApp"
EXECUTABLE_NAME="Scrawl"

BUILD_CONFIGURATION="${SCRAWL_BUILD_CONFIGURATION:-release}"
APP_VERSION="${SCRAWL_APP_VERSION:-0.0.3}"
INSTALL_DIR="${1:-$HOME/Applications}"
CODESIGN_IDENTITY="${SCRAWL_CODESIGN_IDENTITY:-}"
KEEP_ACCESSIBILITY_GRANT=0

BUILD_OUTPUT_DIR="$REPO_ROOT/.build/$BUILD_CONFIGURATION"
BUILT_EXECUTABLE="$BUILD_OUTPUT_DIR/$EXECUTABLE_TARGET"

STAGING_DIR="$REPO_ROOT/.build/install"
STAGED_APP_PATH="$STAGING_DIR/$APP_BUNDLE_NAME"
STAGED_CONTENTS_DIR="$STAGED_APP_PATH/Contents"
STAGED_MACOS_DIR="$STAGED_CONTENTS_DIR/MacOS"
STAGED_INFO_PLIST="$STAGED_CONTENTS_DIR/Info.plist"

TEMPLATE_INFO_PLIST="$REPO_ROOT/Config/ScrawlApp-Info.plist"

ensure_plist_key() {
    local key="$1"
    local type="$2"
    local value="$3"

    if /usr/libexec/PlistBuddy -c "Print :$key" "$STAGED_INFO_PLIST" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Set :$key $value" "$STAGED_INFO_PLIST"
    else
        /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$STAGED_INFO_PLIST"
    fi
}

if [[ "${SCRAWL_SKIP_BUILD:-0}" != "1" ]]; then
    echo "Building $EXECUTABLE_TARGET ($BUILD_CONFIGURATION)..."
    swift build -c "$BUILD_CONFIGURATION" --product "$EXECUTABLE_TARGET"
fi

if [[ ! -x "$BUILT_EXECUTABLE" ]]; then
    ALT_EXECUTABLE="$(find "$REPO_ROOT/.build" -type f -path "*/$BUILD_CONFIGURATION/$EXECUTABLE_TARGET" -perm -111 | head -n 1 || true)"
    if [[ -n "$ALT_EXECUTABLE" ]]; then
        BUILT_EXECUTABLE="$ALT_EXECUTABLE"
    fi
fi

if [[ ! -x "$BUILT_EXECUTABLE" ]]; then
    echo "Build succeeded but executable was not found at:"
    echo "  $BUILT_EXECUTABLE"
    exit 1
fi

rm -rf "$STAGED_APP_PATH"
mkdir -p "$STAGED_MACOS_DIR"

cp "$BUILT_EXECUTABLE" "$STAGED_MACOS_DIR/$EXECUTABLE_NAME"

if [[ -f "$TEMPLATE_INFO_PLIST" ]]; then
    cp "$TEMPLATE_INFO_PLIST" "$STAGED_INFO_PLIST"
else
    cat > "$STAGED_INFO_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict></dict></plist>
EOF
fi

ensure_plist_key "CFBundleName" string "$APP_DISPLAY_NAME"
ensure_plist_key "CFBundleDisplayName" string "$APP_DISPLAY_NAME"
ensure_plist_key "CFBundleExecutable" string "$EXECUTABLE_NAME"
ensure_plist_key "CFBundleIdentifier" string "com.jetemple.scrawl"
ensure_plist_key "CFBundlePackageType" string "APPL"
ensure_plist_key "CFBundleVersion" string "$APP_VERSION"
ensure_plist_key "CFBundleShortVersionString" string "$APP_VERSION"
ensure_plist_key "LSMinimumSystemVersion" string "14.0"
ensure_plist_key "LSUIElement" bool "true"

if [[ -n "$CODESIGN_IDENTITY" ]]; then
    if ! command -v codesign >/dev/null 2>&1; then
        echo "codesign is not available, but SCRAWL_CODESIGN_IDENTITY was set."
        exit 1
    fi
    echo "Signing app bundle with identity: $CODESIGN_IDENTITY"
    codesign --force --deep --sign "$CODESIGN_IDENTITY" "$STAGED_APP_PATH"
    KEEP_ACCESSIBILITY_GRANT=1
elif [[ "${SCRAWL_ADHOC_SIGN:-0}" == "1" ]]; then
    if ! command -v codesign >/dev/null 2>&1; then
        echo "codesign is not available, but SCRAWL_ADHOC_SIGN=1 was requested."
        exit 1
    fi
    echo "Ad-hoc signing app bundle..."
    codesign --force --deep --sign - "$STAGED_APP_PATH"
else
    echo "Skipping code signing (local dev mode)."
    echo "Tip: set SCRAWL_CODESIGN_IDENTITY for more stable permission identity across updates."
fi

mkdir -p "$INSTALL_DIR"
FINAL_APP_PATH="$INSTALL_DIR/$APP_BUNDLE_NAME"

# Quit running instance before replacing
if pgrep -f "$FINAL_APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" >/dev/null 2>&1; then
    echo "Stopping running Scrawl..."
    pkill -f "$FINAL_APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" 2>/dev/null || true
    sleep 0.5
fi

if [[ "$KEEP_ACCESSIBILITY_GRANT" == "1" ]]; then
    echo "Keeping existing Accessibility permission (stable code signature)."
else
    # Unsigned and ad-hoc signed builds frequently get a new identity after rebuild.
    tccutil reset Accessibility com.jetemple.scrawl 2>/dev/null || true
    echo "Accessibility permission was reset for this install."
fi

if [[ -e "$FINAL_APP_PATH" ]] && ! rm -rf "$FINAL_APP_PATH" 2>/dev/null; then
    echo "Permission denied: cannot replace $FINAL_APP_PATH"
    echo "Try: sudo make install PREFIX=$INSTALL_DIR"
    exit 1
fi

cp -R "$STAGED_APP_PATH" "$FINAL_APP_PATH"

echo "Installed: $FINAL_APP_PATH"
echo "Launching Scrawl..."
open "$FINAL_APP_PATH"
