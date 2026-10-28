#!/usr/bin/env bash
# 对每个变体按层序真实重放补丁到 src/ 工作树 (顺序重放, 校验+应用一体),
# 结束后 git checkout -f 还原。任一失败立即报错退出, exit 1。
set -uo pipefail
cd "$(dirname "$0")/.."
fail_total=0
replay() {
  local n=$#; local wt=$1; shift
  git -C "$wt" checkout -q -f -- . 2>/dev/null
  for p in "$@"; do
    [[ $p == /* ]] && pp=$p || pp=$PWD/$p
    if ! git -C "$wt" apply --check "$pp" 2>/tmp/applycheck.err; then
      fail_total=$((fail_total+1))
      echo "  FAIL [$wt] $p"
      head -3 /tmp/applycheck.err | sed 's/^/    /'
      return
    fi
    git -C "$wt" apply "$pp" || { echo "  APPLY-ERR [$wt] $p"; fail_total=$((fail_total+1)); return; }
  done
  echo "  OK   [$wt] $n patches replayed"
}
L0=(
  patches/L0-backport/gen8/0001-tu-kgsl-Prevent-overflow-in-kgsl-queue-wait-fence.patch
  patches/L0-backport/gen8/0002-tu-kgsl-Distinguish-timestamp-and-sync-wait-errors.patch
  patches/L0-backport/gen8/0003-tu-kgsl-Prevent-indefinite-wait-times-for-0-timeout-waits.patch
  patches/L0-backport/gen8/0004-tu-kgsl-Always-round-up-the-wait-timeout.patch
)
L1=( patches/L1-devicetable/0001-freedreno-a840-kgsl-patchid-wildcard.patch )
L2g=( patches/L2-kgsl/0008-tu-reject-end-rendering-without-state.patch )
L3=( patches/L3-fexdroid/0005-wsi-x11-sw-wait-for-the-gpu-on-the-present-thread.patch
     patches/L3-fexdroid/0006-tu-kgsl-power-constraint-from-the-environment.patch )
# 变体 -> 补丁序列 (26.2.3 专属补丁不入仓库变体, 见 series.yaml)
echo "== gen8 =="
replay src/mesa-gen8 "${L0[@]}" "${L1[@]}" "${L2g[@]}" "${L3[@]}"
echo "== main =="
replay src/mesa-main "${L1[@]}" "${L2g[@]}" "${L3[@]}"
exit $fail_total
