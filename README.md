# nixport-drivers

glibc Turnip（Mesa freedreno Vulkan，KGSL 后端）驱动构建与发布仓库

## 变体

| variant | 基线 | 适用 GPU | 补丁层 |
|---|---|---|---|
| `main` | mesa main @ `35b085c4` | a6xx / a7xx / a8xx | L1 → L2 → L3 |
| `gen8` | whitebelyash/mesa-unified `turnip/gen8` @ `9c7e022` | a8xx | L0 → L1 → L2 → L3 |

钉版细节见 `pins.yaml`；补丁分层与许可血统见 `patches/series.yaml`。

## 版本机制

- **驱动身份** = Mesa `VERSION`（如 `26.3.0-devel`）+ 基线 commit——写入
  每个 zip 的 `meta.json` 与 release 说明，跨生态可比；
- **发布序号** = tag `vX.Y.Z`：X = 产物格式/兼容破坏；Y = 基线或补丁集
  变更；Z = 重打包/门禁修复。正式 release 仅由 tag push 产生；
- **滚动预发布** = tag `ci`（prerelease）：每次手动 dispatch 触发的构建
  覆盖更新，不占用正式版本号。

## 产物

- **槽位导入 zip**：`turnip-<variant>-<gpu>-<mesa_rev>-<YYYYMMDD>.zip`
  （`libvulkan_freedreno*.so` + `meta.json`），nixport 驱动管理直接导入；
  release 说明标注各变体适配的 Adreno 型号范围；
- **runtime fragment**：`usr/lib/aarch64-linux-gnu/` +
  `usr/share/vulkan/icd.d/` 布局，icd `library_path` 前缀按消费方 rootfs
  传入，可并入任意 trixie arm64 glibc rootfs。

## 构建

```sh
./build.sh main   # 或 gen8
scripts/emit-slot-zip.sh main
scripts/emit-runtime-fragment.sh main /data/data/.../files/rootfs
```

依赖：clang/llvm（含 lld、llvm-ar、llvm-strip）、glslang（Linux 包名
`glslang-tools`；gen8 fork 的 meson 硬性要求）、meson + ninja（自动建
venv）、bison >= 3.8、flex、python3、pkg-config、可选 ccache。sysroot 由
`tools/fetch_arm64_sysroot.py` 自动拉取（Debian trixie arm64）。

构建耗时与门禁实测数据见本文件末尾「构建记录」。

## 许可

仓库 MIT。`patches/series.yaml` 逐条记录补丁来源与许可证；
GPL-3.0 来源（如 Droid-Deck/Drivers）不收编。

## 待办

- CI dry-run 与 release：待建 GitHub 远端后触发（5.3 / 6.1）
- 真机导入验证与 JICA98 `gen8-v5` A/B：待设备（6.2 / 6.3，依赖 `gpu-driver-slots` 完成或手动放置目录）
- watcher CI（追上游 commit，按需另加）
- release 版变体位（26.x / 25.x，pins 表已留扩展位）
- fexdroid 内置驱动消费切换（归 fexdroid 侧后续 change）
- nixport 消费本仓库产物时的光标渲染 rebase（0007 gow 变体无光标合成，见 series.yaml）
- gen8 变体退休判据：mesa main 在 A840 真机验证通过后退役

## 构建记录

- 2026-10-28（macOS, Homebrew clang 23.1.3 / Python 3.14.7, 无 ccache 冷构建）：
  - `gen8`: Mesa `9c7e022` + 9 patches → `libvulkan_freedreno_gen8.so` (15.5 MB)，全部门禁通过，约 40 s
  - `main`: Mesa `35b085c` + 5 patches → `libvulkan_freedreno.so` (15.3 MB)，全部门禁通过，约 40 s
  - 产物: `turnip-gen8-9c7e022-20261028.zip` / `turnip-main-35b085c-20261028.zip`
  - 可复现性: 删除检出与产物后从零重建通过（1:28）；产物哈希逐次不同
    （构建路径/时间戳嵌入），spec 口径为功能等价
  - 真机（Adreno 840）验证: 待做（见待办）
