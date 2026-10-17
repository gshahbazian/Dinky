#!/usr/bin/env bash
# Build, sign, install and launch the current checkout for local development.
# Usage: IDENTITY='Apple Development: Your Name (TEAMID)' scripts/install-local.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${IDENTITY:-}" ]]; then
  echo "Set IDENTITY to your signing identity. List identities with: security find-identity -v -p codesigning" >&2
  exit 1
fi

if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(git describe --tags --abbrev=0)"
  VERSION="${VERSION#v}"
fi
export IDENTITY VERSION
scripts/bundle.sh "$@"

APP=/Applications/dinky.app
if [[ -d "$APP" ]]; then
  BACKUP_DIR="$(mktemp -d "${TMPDIR:-/tmp/}dinky-backup.XXXXXX")"
  ditto "$APP" "$BACKUP_DIR/dinky.app"
  echo "previous app saved to $BACKUP_DIR/dinky.app"
fi

if pgrep -x dinky >/dev/null; then
  pkill -TERM -x dinky
  for attempt in {1..50}; do
    if ! pgrep -x dinky >/dev/null; then break; fi
    sleep 0.1
  done
  if pgrep -x dinky >/dev/null; then
    echo "dinky did not quit; installation stopped" >&2
    exit 1
  fi
fi

ditto build/dinky.app "$APP"
mkdir -p "$HOME/.local/bin"
ln -sfn "$APP/Contents/MacOS/dinky" "$HOME/.local/bin/dinky"
open "$APP"
echo "installed dinky $VERSION from $(git rev-parse --short HEAD)"
