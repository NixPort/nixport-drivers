#!/usr/bin/env bash
# 生成 dist/release-notes.md: 对 dist/<variant>/meta.json 存在的变体逐一标注
# 适配型号、Mesa 版本/commit、补丁层数、校验和。CI 的 release job 以它为 body。
set -euo pipefail
cd "$(dirname "$0")/.."
out=dist/release-notes.md
datestamp=$(date +%Y%m%d)
{
echo "Nixport Turnip driver builds ($datestamp)"
echo
echo "glibc (Debian trixie) aarch64 · KGSL backend · X11 WSI · 仅供 proot/glibc 运行时，非 AdrenoTools bionic 包"
echo
seen=0
for variant in gen8 main; do
  meta=dist/$variant/meta.json
  [[ -f $meta ]] || continue
  seen=$((seen+1))
  variant_j=$(python3 -c "import json;print(json.load(open('$meta'))['variant'])")
  gpu=$(python3 -c "import json;print(json.load(open('$meta'))['gpu'])")
  mesa_version=$(python3 -c "import json;print(json.load(open('$meta'))['mesa_version'])")
  commit=$(python3 -c "import json;print(json.load(open('$meta'))['mesa_commit'])")
  sha=$(python3 -c "import json;print(json.load(open('$meta'))['library_sha256'])")
  library=$(python3 -c "import json;print(json.load(open('$meta'))['library'])")
  patches=$(grep -c "variants: \[.*${variant_j}" patches/series.yaml || echo '?')
  echo "## turnip-$variant_j"
  if [[ $variant_j == gen8 ]]; then
    echo "- 适配: **Adreno A8xx**（Adreno 840 / 830 / 825 / 829 / 810 等以驱动设备表为准）"
  else
    echo "- 适配: **Adreno 6xx / 7xx / 8xx**（mesa main 设备表全集）"
  fi
  echo "- Mesa: \`$mesa_version\` @ \`$commit\`（钉定基线 + series.yaml 补丁 $patches 处）"
  echo "- 库: \`$library\` · sha256 \`$sha\`"
  echo
done
[[ $seen -gt 0 ]] || { echo "(no builds found)"; exit 1; }
} > "$out"
cat "$out"
