#!/usr/bin/env bash
# 打包 runtime fragment (并入 glibc rootfs 使用):
#   scripts/emit-runtime-fragment.sh [main|gen8] <rootfs前缀>
# 产物: dist/fragment-<variant>/
#   usr/lib/aarch64-linux-gnu/<lib>
#   usr/share/vulkan/icd.d/<manifest>   (library_path = <前缀>/usr/lib/...)
#   usr/share/drirc.d/
set -euo pipefail
cd "$(dirname "$0")/.."
variant=${1:-}; prefix=${2:-}
[[ $variant == main || $variant == gen8 ]] || { echo "usage: emit-runtime-fragment.sh [main|gen8] <rootfs-prefix>" >&2; exit 1; }
[[ -n $prefix && $prefix == /* ]] || { echo "usage: emit-runtime-fragment.sh [main|gen8] <absolute-rootfs-prefix>" >&2; exit 1; }
dist=dist/$variant
library=libvulkan_freedreno.so; [[ $variant == gen8 ]] && library=libvulkan_freedreno_gen8.so
manifest=freedreno_icd.aarch64.json; [[ $variant == gen8 ]] && manifest=freedreno_gen8_icd.aarch64.json
[[ -s $dist/$library ]] || { echo "missing $dist/$library; run ./build.sh $variant first" >&2; exit 1; }

frag=dist/fragment-$variant
rm -rf "$frag"
mkdir -p "$frag/usr/lib/aarch64-linux-gnu" "$frag/usr/share/vulkan/icd.d"
cp "$dist/$library" "$frag/usr/lib/aarch64-linux-gnu/"
sed "s|\"library_path\": \"[^\"]*\"|\"library_path\": \"$prefix/usr/lib/aarch64-linux-gnu/$library\"|" \
  "$dist/$manifest" > "$frag/usr/share/vulkan/icd.d/$manifest"
[[ -d $dist/drirc.d ]] && cp -r "$dist/drirc.d" "$frag/usr/share/drirc.d"
python3 - "$frag/usr/share/vulkan/icd.d/$manifest" "$prefix" <<'PY' || exit 1
import json, sys
d = json.load(open(sys.argv[1]))
lp = d['ICD']['library_path']
assert lp == f"{sys.argv[2]}/usr/lib/aarch64-linux-gnu/" + lp.rsplit('/', 1)[-1], lp
print(f'icd library_path: {lp}')
PY
echo "runtime fragment: $frag"
