#!/bin/sh
# Copies this repo's shaders and techsets into the BO3 install, game and tools sets alike, and installs the shared
# headers they include (deps/<set>/Include) where the install doesn't have them yet. An existing header that differs
# is left alone with a warning, since other shaders in the install may depend on it.
# Usage: ./sync.sh [bo3 root]   (default: $BO3_ROOT or the Steam install on I:)
set -e
ROOT="${1:-${BO3_ROOT:-/i/SteamLibrary/steamapps/common/Call of Duty Black Ops III}}"
RAW="$ROOT/share/raw"
cd "$(dirname "$0")"
for set in shaders_stable shaders_stable_toolsgfx; do
	(cd "deps/$set" && find . -type f) | while read -r f; do
		dst="$RAW/$set/$f"
		if [ ! -f "$dst" ]; then
			mkdir -p "$(dirname "$dst")"; cp "deps/$set/$f" "$dst"; echo "$set/$f (installed)"
		elif ! diff -q --strip-trailing-cr "deps/$set/$f" "$dst" >/dev/null; then
			echo "WARNING: $set/$f differs from this repo's copy; left as is"
		fi
	done
	(cd shaders && find . -name '*.hlsl' -o -name '*.h') | while read -r f; do
		mkdir -p "$RAW/$set/$(dirname "$f")"; cp "shaders/$f" "$RAW/$set/$f"; echo "$set/$f"
	done
done
for set in techsetdefs_stable techsetdefs_stable_toolsgfx; do
	(cd techsets && find . -name '*.techsetdef') | while read -r f; do
		mkdir -p "$RAW/$set/$(dirname "$f")"; cp "techsets/$f" "$RAW/$set/$f"; echo "$set/$f"
	done
done
