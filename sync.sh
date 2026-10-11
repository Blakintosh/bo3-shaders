#!/bin/sh
# Copies this repo's shaders and techsets into the BO3 install, game and tools sets alike.
# Usage: ./sync.sh [bo3 root]   (default: $BO3_ROOT or the Steam install on I:)
set -e
ROOT="${1:-${BO3_ROOT:-/i/SteamLibrary/steamapps/common/Call of Duty Black Ops III}}"
RAW="$ROOT/share/raw"
cd "$(dirname "$0")"
for set in shaders_stable shaders_stable_toolsgfx; do
	(cd shaders && find . -name '*.hlsl' -o -name '*.h') | while read -r f; do
		mkdir -p "$RAW/$set/$(dirname "$f")"; cp "shaders/$f" "$RAW/$set/$f"; echo "$set/$f"
	done
done
for set in techsetdefs_stable techsetdefs_stable_toolsgfx; do
	(cd techsets && find . -name '*.techsetdef') | while read -r f; do
		mkdir -p "$RAW/$set/$(dirname "$f")"; cp "techsets/$f" "$RAW/$set/$f"; echo "$set/$f"
	done
done
