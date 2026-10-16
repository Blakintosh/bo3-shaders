#!/bin/sh
# Compiles every variant of each shader in this repo with fxc (game and tools, mc/ and wc/, OIT), straight from the
# repo: shaders/ plus the shared headers in deps/<set>. No install needed. Run it before linking.
# Each file is compiled for the entry points it has (ls_main as vs_5_0, hs_main, ds_main, vs_main, ps_main); .h files
# are include-only and aren't compiled on their own. Files that read BLEND_RGB_LAYERS / TESS_HEIGHT_BLEND are also
# compiled with the values their techsets give them. A file whose first line starts "// Tools only" skips the game set.
# Usage: ./compile_check.sh [shader relative path, default all]
FXC="${FXC:-/c/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/fxc.exe}"
cd "$(dirname "$0")"
REPO="$(pwd -W 2>/dev/null || pwd)"
fail=0
count=0
for src in ${1:-$(cd shaders && find . -name '*.hlsl' | sed 's|^\./||')}; do
	entries=""
	for e in ls_main hs_main ds_main vs_main ps_main; do
		grep -Eq "^[[:alnum:]_<>]+[[:space:]]+$e[[:space:]]*\(" "shaders/$src" && entries="$entries $e"
	done
	extras="none"
	grep -q "BLEND_RGB_LAYERS" "shaders/$src" && extras="$extras //D_BLEND_RGB_LAYERS=2 //D_BLEND_RGB_LAYERS=3 //D_BLEND_RGB_LAYERS=4"
	grep -q "TESS_HEIGHT_BLEND" "shaders/$src" && extras="$extras //D_TESS_HEIGHT_BLEND=1"
	grep -q "OVERLAY_BLEND" "shaders/$src" && extras="$extras //D_OVERLAY_BLEND=1"
	for e in $entries; do
		case $e in
			ls_main|vs_main) t=vs_5_0 ;;
			hs_main) t=hs_5_0 ;;
			ds_main) t=ds_5_0 ;;
			ps_main) t=ps_5_0 ;;
		esac
		for x in $extras; do
			xd=""
			[ "$x" != none ] && xd=$(echo "$x" | sed 's|//D_|//D |')
			# the RGB blends set TESS_HEIGHT_BLEND too (their shadow pass)
			case "$x" in *RGB*) grep -q "TESS_HEIGHT_BLEND" "shaders/$src" && xd="$xd //D TESS_HEIGHT_BLEND=1" ;; esac
			for skin in "//D USE_GPU_SKIN=1 //D USE_SIEGE_SKINNING=0" "//D USE_GPU_SKIN=0 //D USE_VERTEX_COLOR=1"; do
				for v in "shaders_stable|" "shaders_stable_toolsgfx|//D TOOLSGFX=1 //D USING_HLSL=1" \
					"shaders_stable_toolsgfx|//D TOOLSGFX=1 //D USING_HLSL=1 //D USE_OIT=1"; do
					IFS='|' read -r set d <<V
$v
V
					case "$d" in *USE_OIT*) [ $e = ps_main ] || continue ;; esac
					[ "$set" = shaders_stable ] && grep -q "^// Tools only" "shaders/$src" && continue
					count=$((count + 1))
					out=$("$FXC" //nologo //Zpr //T $t //E $e $d $xd $skin //I "$REPO/deps/$set" //I "$REPO/shaders" "$REPO/shaders/$src" //Fo NUL 2>&1) || { fail=1; echo "FAIL $src $e $set $d $xd $skin"; echo "$out" | grep -E "error" | head -5; }
				done
			done
		done
	done
done
[ $fail = 0 ] && echo "all $count variants compile"
exit $fail
