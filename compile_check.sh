#!/bin/sh
# Compiles every variant of each shader in this repo with fxc (game and tools, mc/ and wc/, OIT), straight from the
# repo: shaders/ plus the shared headers in deps/<set>. No install needed. Run it before linking.
# Usage: ./compile_check.sh [shader relative path, default all]
FXC="${FXC:-/c/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/fxc.exe}"
cd "$(dirname "$0")"
REPO="$(pwd -W 2>/dev/null || pwd)"
fail=0
for src in ${1:-$(cd shaders && find . -name '*.hlsl' | sed 's|^\./||')}; do
	for skin in "//D USE_GPU_SKIN=1 //D USE_SIEGE_SKINNING=0" "//D USE_GPU_SKIN=0 //D USE_VERTEX_COLOR=1"; do
		for v in "shaders_stable|vs_5_0|vs_main|" "shaders_stable|ps_5_0|ps_main|" \
			"shaders_stable_toolsgfx|vs_5_0|vs_main|//D TOOLSGFX=1 //D USING_HLSL=1" \
			"shaders_stable_toolsgfx|ps_5_0|ps_main|//D TOOLSGFX=1 //D USING_HLSL=1" \
			"shaders_stable_toolsgfx|ps_5_0|ps_main|//D TOOLSGFX=1 //D USING_HLSL=1 //D USE_OIT=1"; do
			IFS='|' read -r set t e d <<V
$v
V
			out=$("$FXC" //nologo //Zpr //T $t //E $e $d $skin //I "$REPO/deps/$set" //I "$REPO/shaders" "$REPO/shaders/$src" //Fo NUL 2>&1) || { fail=1; echo "FAIL $src $set $t $d $skin"; echo "$out" | grep -E "error" | head -5; }
		done
	done
done
[ $fail = 0 ] && echo "all variants compile"
exit $fail
