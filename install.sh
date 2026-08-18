#!/usr/bin/env bash
# Symlink the quadlet units into the systemd user generator directory.
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNITS="$HOME/.config/containers/systemd"

if [[ ! -f "$BASE/secrets.env" ]]; then
    echo "error: $BASE/secrets.env is missing - copy secrets.env.example first" >&2
    exit 1
fi

mkdir -p "$BASE/consume" "$BASE/export" "$UNITS"
ln -sfn "$BASE"/quadlet/* "$UNITS"/
systemctl --user daemon-reload

echo "units installed:"
ls -l "$UNITS"
echo
echo "now run: systemctl --user start paperless-webserver"
