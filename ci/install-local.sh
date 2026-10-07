#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root from script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
DERIVED_DATA="${GATHERAPPS_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/GatherApps-local}"
INSTALL_PATH="/Applications/GatherApps.app"
TEMP_INSTALL_PATH="/Applications/.GatherApps.app.installing"
BACKUP_PATH="/Applications/.GatherApps.app.previous"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
MAIN_BUNDLE_ID="com.minepacu.GatherApps"
HELPER_BUNDLE_ID="com.minepacu.GatherApps.WindowHelper"
EXPECTED_TEAM_ID="8648BH462V"
LAUNCH_APP=true

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-launch)
      LAUNCH_APP=false
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Build the app
echo "Building GatherApps..."
xcodebuild \
  -project "$REPO_ROOT/GatherApps.xcodeproj" \
  -scheme GatherApps \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet \
  build

# Locate built app
BUILT_APP="$DERIVED_DATA/Build/Products/Debug/GatherApps.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "Error: Built app not found at $BUILT_APP" >&2
  exit 1
fi

# Locate helper
HELPER_APP="$BUILT_APP/Contents/Library/LoginItems/GatherAppsWindowHelper.app"
if [[ ! -d "$HELPER_APP" ]]; then
  echo "Error: Helper app not found at $HELPER_APP" >&2
  exit 1
fi

# Verify signing: main app
echo "Verifying main app signature..."
MAIN_SIGN_OUTPUT=$(codesign -dv "$BUILT_APP" 2>&1) || {
  echo "Error: Failed to verify main app signature" >&2
  echo "$MAIN_SIGN_OUTPUT" >&2
  exit 1
}

if ! echo "$MAIN_SIGN_OUTPUT" | grep -q "TeamIdentifier=$EXPECTED_TEAM_ID"; then
  echo "Error: Main app TeamIdentifier is not $EXPECTED_TEAM_ID" >&2
  echo "$MAIN_SIGN_OUTPUT" >&2
  exit 1
fi

if echo "$MAIN_SIGN_OUTPUT" | grep -q "adhoc"; then
  echo "Error: Main app has adhoc signature" >&2
  exit 1
fi

codesign --verify --deep --strict "$BUILT_APP" > /dev/null 2>&1 || {
  echo "Error: Main app failed deep/strict verification" >&2
  exit 1
}

# Verify signing: helper
echo "Verifying helper app signature..."
HELPER_SIGN_OUTPUT=$(codesign -dvvv "$HELPER_APP" 2>&1) || {
  echo "Error: Failed to verify helper app signature" >&2
  echo "$HELPER_SIGN_OUTPUT" >&2
  exit 1
}

if ! echo "$HELPER_SIGN_OUTPUT" | grep -q "TeamIdentifier=$EXPECTED_TEAM_ID"; then
  echo "Error: Helper TeamIdentifier is not $EXPECTED_TEAM_ID" >&2
  echo "$HELPER_SIGN_OUTPUT" >&2
  exit 1
fi

if echo "$HELPER_SIGN_OUTPUT" | grep -q "adhoc"; then
  echo "Error: Helper has adhoc signature" >&2
  exit 1
fi

codesign --verify --deep --strict "$HELPER_APP" > /dev/null 2>&1 || {
  echo "Error: Helper failed deep/strict verification" >&2
  exit 1
}

# Extract helper CDHash for summary
HELPER_CDHASH=$(echo "$HELPER_SIGN_OUTPUT" | grep "CDHash=" | sed 's/.*CDHash=//' | cut -d' ' -f1)

# Quit running copies
# Usage: wait_for_exit <pgrep pattern> <attempts of 0.1s>
wait_for_exit() {
  local pattern="$1"
  local attempts="$2"
  local i
  for ((i = 0; i < attempts; i++)); do
    if ! pgrep -f "$pattern" > /dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  ! pgrep -f "$pattern" > /dev/null 2>&1
}

# Usage: stop_process <pgrep pattern> <bundle id>
# Quit -> SIGTERM -> SIGKILL; exits the script if the process survives.
stop_process() {
  local pattern="$1"
  local bundle_id="$2"

  osascript -e "tell application id \"$bundle_id\" to quit" 2>/dev/null || true
  if wait_for_exit "$pattern" 50; then
    return 0
  fi

  pkill -TERM -f "$pattern" 2>/dev/null || true
  if wait_for_exit "$pattern" 30; then
    return 0
  fi

  pkill -KILL -f "$pattern" 2>/dev/null || true
  if wait_for_exit "$pattern" 20; then
    return 0
  fi

  echo "Error: $bundle_id is still running (pattern: $pattern); not replacing the installed app" >&2
  exit 1
}

echo "Quitting running instances..."
stop_process "/GatherApps.app/Contents/MacOS/GatherApps" "$MAIN_BUNDLE_ID"
stop_process "GatherAppsWindowHelper.app/Contents/MacOS/GatherAppsWindowHelper" "$HELPER_BUNDLE_ID"

# Install atomically
echo "Installing to $INSTALL_PATH..."

# Remove temp path if it exists
if [[ -e "$TEMP_INSTALL_PATH" ]]; then
  rm -rf "$TEMP_INSTALL_PATH"
fi

# Ditto to temp location
ditto "$BUILT_APP" "$TEMP_INSTALL_PATH"

# Move old installation aside if it exists and is ours
HAS_BACKUP=false
if [[ -d "$INSTALL_PATH" ]]; then
  OLD_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INSTALL_PATH/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$OLD_BUNDLE_ID" != "$MAIN_BUNDLE_ID" ]]; then
    echo "Error: $INSTALL_PATH exists but is not $MAIN_BUNDLE_ID (found $OLD_BUNDLE_ID)" >&2
    rm -rf "$TEMP_INSTALL_PATH"
    exit 1
  fi

  if [[ -e "$BACKUP_PATH" ]]; then
    rm -rf "$BACKUP_PATH"
  fi

  if ! mv "$INSTALL_PATH" "$BACKUP_PATH"; then
    echo "Error: Failed to move existing $INSTALL_PATH aside" >&2
    rm -rf "$TEMP_INSTALL_PATH"
    exit 1
  fi
  HAS_BACKUP=true
fi

# Move into place
if ! mv "$TEMP_INSTALL_PATH" "$INSTALL_PATH"; then
  echo "Error: Failed to move new app into $INSTALL_PATH" >&2
  if [[ "$HAS_BACKUP" == true ]]; then
    if mv "$BACKUP_PATH" "$INSTALL_PATH"; then
      echo "Restored previous installation" >&2
    else
      echo "Error: Failed to restore previous installation from $BACKUP_PATH" >&2
    fi
  fi
  rm -rf "$TEMP_INSTALL_PATH"
  exit 1
fi

if [[ "$HAS_BACKUP" == true ]]; then
  rm -rf "$BACKUP_PATH"
fi

# Register and launch
echo "Registering with LaunchServices..."
"$LSREGISTER" -f "$INSTALL_PATH"

if [[ "$LAUNCH_APP" == true ]]; then
  echo "Launching app..."
  open "$INSTALL_PATH"
fi

# Summary
echo ""
echo "✓ Installation complete"
echo "  Installed: $INSTALL_PATH"
echo "  Helper TeamIdentifier: $EXPECTED_TEAM_ID"
echo "  Helper CDHash: $HELPER_CDHASH"
