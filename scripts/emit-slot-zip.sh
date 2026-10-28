#!/usr/bin/env bash
# 打包槽位导入 zip (nixport gpu-driver-slots 直接导入):
#   scripts/emit-slot-zip.sh [main|gen8]
# 产物: dist/turnip-<variant>-<gpu>-<mesa_rev>-<YYYYMMDD>.zip
#   libvulkan_freedreno[_gen8].so + meta.json
#   (variant/gpu/mesa_version/mesa_commit/date/sha256)
# 不内嵌 icd.json: nixport 宿主按所选槽生成 (gpu-driver-slots D1)。
set -euo pipefail
cd "$(dirname "$0")/.."
variant=${1:-}
[[ $variant == main || $variant == gen8 ]] || { echo "usage: emit-slot-zip.sh [main|gen8]" >&2; exit 1; }
dist=dist/$variant
library=libvulkan_freedreno.so; [[ $variant == gen8 ]] && library=libvulkan_freedreno_gen8.so
gpu=a6xx-a8xx; [[ $variant == gen8 ]] && gpu=a8xx
[[ -s $dist/$library ]] || { echo "missing $dist/$library; run ./build.sh $variant first" >&2; exit 1; }

srcrev=src/mesa-main; [[ $variant == gen8 ]] && srcrev=src/mesa-gen8
commit=$(git -C "$srcrev" rev-parse --short HEAD 2>/dev/null || echo unknown)
mesa_version=$(cat "$dist/mesa_version" 2>/dev/null || echo unknown)
datestamp=$(date +%Y%m%d)
zipname="turnip-$variant-$gpu-$commit-$datestamp.zip"
sha=$(shasum -a 256 "$dist/$library" | cut -d' ' -f1)

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp "$dist/$library" "$stage/"
cat > "$stage/meta.json" <<EOF
{
  "name": "Nixport Turnip $variant ($gpu)",
  "variant": "$variant",
  "gpu": "$gpu",
  "mesa_version": "$mesa_version",
  "mesa_commit": "$commit",
  "build_date": "$datestamp",
  "library": "$library",
  "library_sha256": "$sha",
  "libc": "glibc",
  "arch": "aarch64"
}
EOF
# aarch64 ELF + glibc 标记自检 (与 nixport 槽位校验对称)
file -b "$stage/$library" | grep -q "aarch64" || { echo "gate: not an aarch64 ELF" >&2; exit 1; }
grep -aq "libc.so.6" "$stage/$library" || { echo "gate: glibc marker missing" >&2; exit 1; }
( cd "$stage" && zip -q "$OLDPWD/dist/$zipname" "$library" meta.json )
cp "$stage/meta.json" "$dist/meta.json"
echo "slot zip: dist/$zipname"
