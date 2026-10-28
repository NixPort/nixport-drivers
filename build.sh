#!/usr/bin/env bash
# nixport-drivers: Turnip (Mesa freedreno Vulkan, KGSL) aarch64 glibc builds.
# One variant per invocation, baselines pinned in pins.yaml:
#   main: mesa main   -> dist/main/  (libvulkan_freedreno.so, freedreno_icd.aarch64.json, drirc.d/)
#   gen8: turnip/gen8 -> dist/gen8/  (libvulkan_freedreno_gen8.so, freedreno_gen8_icd.aarch64.json)
# Patches replay layer-ordered per patches/series.yaml; every run starts from a
# pristine checkout of the pinned commit.meson prefix is /usr: the ICD ships a
# generic absolute library_path, consumers rewrite it (scripts/emit-*).
set -euo pipefail
cd "$(dirname "$0")"
die() { echo "build: $*" >&2; exit 1; }

# ---- toolchain discovery (macOS hosts ship bison 2.3; prefer Homebrew kegs) ----
for tool in bison flex; do
  for prefix in /opt/homebrew/opt/$tool /usr/local/opt/$tool; do
    [[ -d $prefix/bin ]] && { export PATH="$prefix/bin:$PATH"; break; }
  done
done
[[ -n ${LLVM_PREFIX:-} && -d $LLVM_PREFIX/bin ]] && export PATH="$LLVM_PREFIX/bin:$PATH"
for tool in clang clang++ llvm-ar llvm-strip pkg-config python3; do
  command -v "$tool" >/dev/null || die "$tool is required"
done
if command -v readelf >/dev/null; then readelf_cmd=readelf; elif command -v llvm-readelf >/dev/null; then readelf_cmd=llvm-readelf; else die 'readelf or llvm-readelf is required'; fi
if ! bison -Wcounterexamples -V >/dev/null 2>&1; then
  die "bison is too old ($(bison --version 2>&1 | head -1)); need >= 3.8 (brew install bison)"
fi

variant=${1:-}
[[ $variant == main || $variant == gen8 ]] || die "usage: build.sh [main|gen8]"

# ---- pins.yaml + series.yaml (no PyYAML dependency; fixed layout) ----
REPO=$(python3 - "$variant" <<'PY'
import re, sys
variant = sys.argv[1]
text = open('pins.yaml').read()
block = re.search(rf'^  {variant}:\n((?:    .*\n)+)', text, re.M)
print(re.search(r'^    repo: (.+)$', block.group(1), re.M).group(1))
PY
)
COMMIT=$(python3 - "$variant" <<'PY'
import re, sys
variant = sys.argv[1]
text = open('pins.yaml').read()
block = re.search(rf'^  {variant}:\n((?:    .*\n)+)', text, re.M)
print(re.search(r'^    commit: (.+)$', block.group(1), re.M).group(1))
PY
)
[[ -n $REPO && -n $COMMIT ]] || die "pins.yaml: repo/commit missing for $variant"
PATCHES=()
while IFS= read -r line; do
  [[ -n $line ]] && PATCHES+=("patches/$line")
done < <(python3 - "$variant" <<'PY'
import re, sys
want = sys.argv[1]
text = open('patches/series.yaml').read()
for m in re.finditer(r'^  - file: (.+)\n((?:    .*\n?)+)', text, re.M):
    variants = re.search(r'variants: \[(.*?)\]', m.group(2))
    names = [v.strip() for v in variants.group(1).split(',')]
    if want in names:
        print(m.group(1))
PY
)
[[ ${#PATCHES[@]} -gt 0 ]] || die "$variant: no patches selected from series.yaml"

# ---- paths ----
suffix=''; [[ $variant == gen8 ]] && suffix=_gen8
src=src/mesa${suffix/_/-}          # src/mesa-main | src/mesa-gen8
build=build/$variant
sysroot=$PWD/mesa-sysroot
out=dist/$variant
mkdir -p src build dist

# ---- sysroot (Debian trixie arm64; the consumers' rootfs is the same release) ----
if [[ ! -f $sysroot/packages.json ]]; then
  python3 tools/fetch_arm64_sysroot.py --out "$sysroot" --packages \
    libc6-dev libstdc++-14-dev libgcc-14-dev linux-libc-dev zlib1g-dev libzstd-dev \
    libexpat1-dev libxcb1-dev libx11-xcb-dev libxcb-xfixes0-dev libxcb-randr0-dev \
    libxcb-dri3-dev libxcb-present-dev libxcb-sync-dev libxcb-shm0-dev libxshmfence-dev \
    libx11-dev libxrandr-dev libdrm-dev
fi
rm -f "$sysroot/usr/lib/aarch64-linux-gnu/pkgconfig/xcb-keysyms.pc"

# ---- meson + mako in a local venv (绝对路径: meson 在 builddir 里执行 find_program) ----
venv=$PWD/build/venv
if [[ ! -x $venv/bin/meson ]]; then
  python3 -m venv "$venv"
  "$venv/bin/python" -m pip install -q meson mako pyyaml packaging
fi
export PATH="$venv/bin:$PATH"

# ---- pristine checkout of the pinned commit ----
if [[ ! -d $src/.git ]]; then
  git init -q "$src"
  git -C "$src" remote add origin "$REPO"
fi
if ! git -C "$src" cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
  git -C "$src" fetch -q --depth 1 origin "$COMMIT" || die "$variant: cannot fetch pinned commit $COMMIT"
fi
git -C "$src" checkout -q --force "$COMMIT"
git -C "$src" clean -q -fdx

# ---- patch replay in series.yaml order ----
for p in "${PATCHES[@]}"; do
  [[ -f $p ]] || die "$variant: missing patch $p"
  git -C "$src" apply --check "$PWD/$p" || die "$variant: patch does not apply: $p"
  git -C "$src" apply "$PWD/$p"
done

# ---- ccache optional ----
if command -v ccache >/dev/null 2>&1; then
  export CCACHE_BASEDIR=${CCACHE_BASEDIR:-$PWD}
  c_entry="['ccache', 'clang', '--target=aarch64-linux-gnu', '--sysroot=$sysroot']"
  cpp_entry="['ccache', 'clang++', '--target=aarch64-linux-gnu', '--sysroot=$sysroot']"
else
  c_entry="['clang', '--target=aarch64-linux-gnu', '--sysroot=$sysroot']"
  cpp_entry="['clang++', '--target=aarch64-linux-gnu', '--sysroot=$sysroot']"
fi

cross=$build.cross
mkdir -p "$(dirname "$cross")"
cat > "$cross" <<EOF
[binaries]
c = $c_entry
cpp = $cpp_entry
c_ld = 'lld'
cpp_ld = 'lld'
ar = 'llvm-ar'
strip = 'llvm-strip'
pkg-config = 'pkg-config'
[built-in options]
c_args = ['-O2']
cpp_args = ['-O2']
[properties]
sys_root = '$sysroot'
pkg_config_libdir = ['$sysroot/usr/lib/aarch64-linux-gnu/pkgconfig', '$sysroot/usr/share/pkgconfig']
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
rm -rf "$build/obj" "$out"

echo "==> meson setup ($variant)"
meson setup "$build/obj" "$src" --cross-file "$cross" --prefix=/usr \
  --libdir=lib/aarch64-linux-gnu --wrap-mode=nofallback --buildtype=release -Db_ndebug=true \
  -Dplatforms=x11 -Dvulkan-drivers=freedreno -Dfreedreno-kmds=kgsl -Dgallium-drivers= \
  -Dopengl=false -Degl=disabled -Dgles1=disabled -Dgles2=disabled -Dglx=disabled -Dgbm=disabled \
  -Dllvm=disabled -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled \
  -Dzstd=enabled -Dexpat=enabled -Dvulkan-layers= -Dtools= -Dbuild-tests=false \
  > "$build.log" 2>&1 || { tail -40 "$build.log" >&2; exit 1; }
echo "==> ninja"
ninja -C "$build/obj" >> "$build.log" 2>&1 || { tail -40 "$build.log" >&2; exit 1; }
echo "==> install"
DESTDIR="$PWD/$build/install" meson install -C "$build/obj" --no-rebuild >> "$build.log" 2>&1

# ---- stage + rename artifacts ----
installed=$build/install/usr
library=libvulkan_freedreno$suffix.so
manifest=freedreno${suffix}_icd.aarch64.json
mkdir -p "$out"
llvm-strip --strip-debug -o "$out/$library" \
  "$installed/lib/aarch64-linux-gnu/libvulkan_freedreno.so"
sed "s|/libvulkan_freedreno.so\"|/$library\"|" \
  "$installed/share/vulkan/icd.d/freedreno_icd.aarch64.json" > "$out/$manifest"
grep -q "/$library\"" "$out/$manifest" || { echo "Manifest does not name $library" >&2; exit 1; }
cp -r "$installed/share/drirc.d" "$out/drirc.d"

# ---- gates (any failure aborts) ----
[[ -s $out/$library ]] || die "$variant: missing driver output"
[[ -s $out/$manifest ]] || die "$variant: missing ICD manifest"
python3 - "$out/$manifest" <<'PY' || exit 1
import json, sys
d = json.load(open(sys.argv[1]))
lp = d['ICD']['library_path']
assert lp.startswith('/'), f'ICD library_path is not absolute: {lp}'
print(f'icd library_path: {lp}')
PY
GEN="$build/obj/src/freedreno/common/freedreno_devices.h"
[[ -f $GEN ]] && grep -qi "0xffff44050a31" "$GEN" \
  || { echo "gate: A840 chip id missing from device table" >&2; exit 1; }
grep -q "Adreno (TM) 840" "$out/$library" \
  || { echo "gate: A840 name string missing from $library" >&2; exit 1; }
if "$readelf_cmd" -d "$out/$library" | grep -q keysyms; then
  die "$library needs libxcb-keysyms, which the consumers' rootfs lacks"
fi

echo "Turnip $variant: $out (Mesa $(git -C "$src" rev-parse --short HEAD) + ${#PATCHES[@]} patches)"
