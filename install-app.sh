#!/bin/bash
# Build the release app, install it to ~/Applications, and point the Dock at
# the installed copy so the Dock never launches a stale build from the repo.
set -euo pipefail
cd "$(dirname "$0")"

./make-app.sh
DEST="$HOME/Applications/Trackpad Studio.app"
pkill -x TrackpadStudio || true
mkdir -p "$HOME/Applications"
ditto TrackpadStudio.app "$DEST"

# Replace any Dock tile that points at a repo build (TrackpadStudio*.app under
# this checkout or an older path) with the installed app, keeping its slot.
python3 - "$DEST" <<'PY'
import plistlib, subprocess, sys, urllib.parse, os
dest = sys.argv[1]
raw = subprocess.check_output(["defaults", "export", "com.apple.dock", "-"])
dock = plistlib.loads(raw)
apps = dock.get("persistent-apps", [])
want = "file://" + urllib.parse.quote(dest) + "/"
tile = {"tile-data": {"file-data": {"_CFURLString": want, "_CFURLStringType": 15},
                      "file-label": "Trackpad Studio"}, "tile-type": "file-tile"}
idx = [i for i, a in enumerate(apps)
       if "trackpadstudio" in a.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "").lower()
       or "trackpad%20studio" in a.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "").lower()]
if idx:
    apps[idx[0]] = tile
    for i in reversed(idx[1:]): apps.pop(i)
else:
    apps.append(tile)
dock["persistent-apps"] = apps
subprocess.run(["defaults", "import", "com.apple.dock", "-"], input=plistlib.dumps(dock), check=True)
PY
killall Dock
echo "Installed $DEST and pointed the Dock at it."
