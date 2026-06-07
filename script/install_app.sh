#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TodoSticky"
DISPLAY_NAME="轻话"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
TARGET_APP="$INSTALL_DIR/$DISPLAY_NAME.app"

"$ROOT_DIR/script/build_and_run.sh" --verify
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

mkdir -p "$INSTALL_DIR"
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"

/usr/bin/open "$TARGET_APP"

cat <<EOF
Installed $DISPLAY_NAME to:
$TARGET_APP

You can now open it from Finder, Spotlight, Launchpad, or the Dock.
EOF
