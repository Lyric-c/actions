# ffmpeg-rockchip 编译 & 使用指南

[nyanmisaka/ffmpeg-rockchip](https://github.com/nyanmisaka/ffmpeg-rockchip) 是 FFmpeg 的 fork，为 Rockchip 平台提供基于 **MPP**（硬件编解码）和 **RGA**（2D 图像加速）的完整硬件转码 pipeline，适用于 RK3566 / RK3568 / RK3588 等芯片，可脱离 Jellyfin 独立使用。

---

## 1. 依赖与分支对照

| 组件 | 仓库 | 稳定分支 | 较新分支（Jellyfin 镜像实际用） | 编译系统 |
|---|---|---|---|---|
| **ffmpeg-rockchip** | [nyanmisaka/ffmpeg-rockchip](https://github.com/nyanmisaka/ffmpeg-rockchip) | `master` | `master`（无 tag/release） | `./configure && make` |
| **MPP** | [nyanmisaka/rk-mirrors](https://github.com/nyanmisaka/rk-mirrors) | `jellyfin-mpp` | `jellyfin-mpp-next` | cmake |
| **RGA** | [nyanmisaka/rk-mirrors](https://github.com/nyanmisaka/rk-mirrors) | `jellyfin-rga` | `jellyfin-rga-next` | meson + ninja |

> **没有预编译 releases**（GitHub Releases 页为空），必须自行编译。但不必在板子上编译——可以交叉编译（x86_64 → arm64，Jellyfin 镜像就是这么做的）或走 GitHub Actions，产出的 arm64 二进制在 3566/3588 之间通用。

### 编译时依赖（configure 硬性检测，实测自源码）

```
rkmpp:  pkg-config "rockchip_mpp >= 1.3.9"（.pc 中 Version 为硬编码 1.3.9）
        头文件 rockchip/rk_mpi.h、rockchip/mpp_buffer.h
        必须同时 --enable-libdrm，否则报错 "rkmpp requires --enable-libdrm"
rkrga:  pkg-config "librga"
        头文件 rga/RgaApi.h、rga/im2d.h
        必须同时 --enable-rkmpp，否则报错 "rkrga requires --enable-rkmpp"
```

---

## 2. 运行时要求（由板子系统决定，无需自选版本）

- **内核**：Rockchip BSP/Vendor 内核 5.10 或 6.1（带 rockchip 后缀）
- **设备节点**：
  ```bash
  ls -la /dev/mpp_service /dev/rga /dev/dri /dev/dma_heap
  ```
- **userspace 库**：`librockchip_mpp.so`、`librga.so`（系统已装则直接用，不要用自行编译的库覆盖系统库——版本须与内核驱动配套，错配会 segfault）
- **设备节点权限**：实测 `/dev/mpp_service`、`/dev/rga` 为 `crw------- root`（仅 root）；`/dev/dri` 为 `crw-rw---- root:video`。Jellyfin 容器默认 root 运行，`--device` 映射后即可访问，**无需 chmod**；若容器以非 root 运行，用 udev 规则把设备加入 video/render 组，而不是 `chmod 666`
- **检查命令**：
  ```bash
  uname -r                                        # 内核版本
  ldconfig -p | grep -E 'rockchip_mpp|librga'     # 运行时库及 soname
  ```

**版本匹配原则**：运行时库由系统决定（查 `ldconfig -p` 的 soname，如 `librockchip_mpp.so.1`、`librga.so.2`）；编译期用的是头文件 + `.pc`，注意"编译环境版本 ≥ 板子运行时版本"的 ABI 匹配。

### 确认宿主机驱动版本

硬件加速栈分两层：**内核驱动**（宿主机，必须）+ **userspace 库**（容器自带给 Jellyfin 用，宿主机可有可无）。

```bash
uname -r                                                     # 内核版本，须带 rockchip 后缀
ls -la /dev/mpp_service /dev/rga /dev/dri /dev/dma_heap      # 设备节点
dmesg | grep -iE 'mpp|rga|vpu|rkvdec|rkvenc' | head -20       # 驱动加载日志
mount | grep debugfs && cat /sys/kernel/debug/mpp/version     # 内核 MPP 驱动版本（路径因内核而异）
lsmod | grep -iE 'rockchip|mpp|rga|vpu'                       # 内核模块
modinfo rockchip_vdec 2>/dev/null | grep -E 'version|vermagic'
```

用户态库版本（容器内查）：

```bash
strings /usr/lib/jellyfin-ffmpeg/lib/librockchip_mpp.so.1 | grep -iE 'version|commit'
strings /usr/lib/jellyfin-ffmpeg/lib/librga.so.2 | grep -iE 'version|commit'
```

**兼容性判断**：用户态库 ≤ 内核驱动版本安全；用户态库 > 内核驱动版本可能 segfault（ioctl 接口向后兼容，新接口不被旧驱动支持）。BSP 内核 6.1-rockchip 与 jellyfin-mpp-next/rga-next 完美匹配；5.10-rockchip 大概率可用（部分新特性如 AV1 解码可能不支持）；4.19 及更老很可能不兼容。

---

## 3. 编译步骤

### 3.1 系统已有 MPP/RGA 库（推荐，只编 ffmpeg）

```bash
sudo apt install -y build-essential git meson cmake pkg-config libdrm-dev

# 确认系统已有 MPP/RGA 开发头文件
pkg-config --exists rockchip_mpp && echo "MPP OK"
pkg-config --exists librga && echo "RGA OK"

git clone --depth=1 https://github.com/nyanmisaka/ffmpeg-rockchip.git
cd ffmpeg-rockchip
./configure --prefix=/usr/local \
    --enable-gpl --enable-version3 \
    --enable-libdrm --enable-rkmpp --enable-rkrga
make -j$(nproc)
sudo make install
```

### 3.2 系统缺少 MPP/RGA（先编库，装到 /usr/local）

```bash
# --- MPP ---
git clone -b jellyfin-mpp --depth=1 https://github.com/nyanmisaka/rk-mirrors.git rkmpp
cd rkmpp && mkdir build && cd build
cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON -DBUILD_TEST=OFF ..
make -j$(nproc) && sudo make install

# --- RGA ---
git clone -b jellyfin-rga --depth=1 https://github.com/nyanmisaka/rk-mirrors.git rkrga
meson setup rkrga_build --prefix=/usr/local --libdir=lib --buildtype=release \
    --default-library=shared \
    -Dcpp_args=-fpermissive -Dlibdrm=false -Dlibrga_demo=false
ninja -C rkrga_build install

# --- 再按 3.1 编译 ffmpeg-rockchip ---
```

### 3.3 交叉编译（x86_64 → arm64）或 GitHub Actions

参照 [nyanmisaka/jellyfin-ffmpeg 的 docker-build.sh](https://github.com/nyanmisaka/jellyfin-ffmpeg/blob/jellyfin/docker-build.sh) 的 `prepare_crossbuild_env_arm64` / `prepare_extra_arm`：

```bash
dpkg --add-architecture arm64
apt install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libc6-dev:arm64
# MPP 加 -DCMAKE_TOOLCHAIN_FILE=toolchain-arm64.cmake
# RGA 加 --cross-file=cross-arm64.meson
# ffmpeg 加 --arch=arm64 --cross-prefix=aarch64-linux-gnu- --enable-cross-compile
```

关键点：交叉编译环境里的 MPP/RGA 头文件版本要与板子运行时库匹配（或直接交叉编译与板子同版本的 MPP/RGA）。

### 3.4 一键方案：GitHub Actions（推荐）

本仓库已内置完整可用的交叉编译流水线，**fork 后手动触发即可**，产物可直接部署到 3566/3588：

```
.github/workflows/build-ffmpeg-rockchip.yml    # 主流水线（MPP+RGA+FFmpeg 三件套）
ffmpeg-rockchip/ci/toolchain-arm64.cmake       # cmake 交叉编译配置（aarch64）
ffmpeg-rockchip/ci/cross-arm64.meson           # meson 交叉编译配置（aarch64）
ffmpeg-rockchip/ci/Dockerfile                  # docker 部署镜像（纯 COPY，无 RUN）
```

**使用步骤**：
1. fork 本仓库 → Actions → "Build ffmpeg-rockchip (arm64)" → **Run workflow**
2. 手动触发时可选 MPP/RGA 分支：`jellyfin-mpp`（稳定，推荐）/ `jellyfin-mpp-next`（激进，Jellyfin 镜像同款）
3. 构建完成后在 run 页面下载 artifact，含两个包：
   - `ffmpeg-rockchip-arm64.tar.gz`（裸机部署）
   - `ffmpeg-rockchip-arm64-docker.tar.gz`（docker 镜像）

**裸机部署**（解压即用，RPATH 已内置无需 LD_LIBRARY_PATH，但仍建议加上双保险）：

```bash
tar -xzf ffmpeg-rockchip-arm64.tar.gz -C /opt
export LD_LIBRARY_PATH=/opt/ffmpeg-rockchip/lib   # 双保险
/opt/ffmpeg-rockchip/bin/ffmpeg -decoders | grep rkmpp
```

非 root 用户跑需先放开设备权限（udev 规则，见第 2 节）。

**docker 部署**：

```bash
docker load < ffmpeg-rockchip-arm64-docker.tar.gz
docker run --rm \
  --device=/dev/mpp_service:/dev/mpp_service \
  --device=/dev/rga:/dev/rga \
  --device=/dev/dri:/dev/dri \
  ffmpeg-rockchip:arm64 -hwaccel rkmpp -c:v hevc_rkmpp -i input.mkv -c:v h264_rkmpp out.mp4
```

> 流水线内置 qemu-aarch64 验证步骤：产物在 CI 上先跑一遍 `ffmpeg -version` / 统计 rkmpp/rkrga 数量，失败即中止，保证下载到的包可用。

---

## 4. 验证

```bash
ffmpeg -decoders | grep rkmpp   # h264_rkmpp, hevc_rkmpp, av1_rkmpp, mjpeg_rkmpp...
ffmpeg -encoders | grep rkmpp   # h264_rkmpp, hevc_rkmpp, mjpeg_rkmpp...
ffmpeg -filters  | grep rkrga   # scale_rkrga, vpp_rkrga, overlay_rkrga...
```

---

## 5. 备选：从 Jellyfin 镜像直接提取（零编译）

镜像 `nyanmisaka/jellyfin:latest-rockchip` 内置的 ffmpeg 即带完整 MPP/RGA 的交叉编译产物（实测 `ffmpeg 7.1.3-Jellyfin`，configure 含 `--enable-rkmpp --enable-rkrga --enable-libdrm --enable-cross-compile`）。**注意实际路径没有 `bin/` 子目录**：

```bash
docker create --name jf-extract nyanmisaka/jellyfin:latest-rockchip
docker cp jf-extract:/usr/lib/jellyfin-ffmpeg ./jellyfin-ffmpeg
docker rm jf-extract

# 整个目录（ffmpeg + ffprobe + lib/）scp 到板子，然后：
export LD_LIBRARY_PATH=/path/to/jellyfin-ffmpeg/lib
./jellyfin-ffmpeg/ffmpeg -decoders | grep rkmpp
```

依赖是自包含的：`ffmpeg`/`ffprobe` 只依赖目录内 libav* + 系统 glibc；`librockchip_mpp.so.1`、`librga.so.2`、`libOpenCL.so.1` 等全在 `lib/` 里。

用 Docker 跑的话，基于镜像包一层：

```dockerfile
FROM nyanmisaka/jellyfin:latest-rockchip
ENTRYPOINT ["/usr/lib/jellyfin-ffmpeg/ffmpeg"]
```

```bash
docker run --rm \
  --device=/dev/dri --device=/dev/mpp_service --device=/dev/rga \
  my-ffmpeg-rockchip -hwaccel rkmpp -c:v hevc_rkmpp -i input.mkv ...
```

---

## 6. RK3566 vs RK3588

同一套 arm64 二进制通用，但硬件能力有差异：

| 能力 | RK3566 | RK3588 |
|---|---|---|
| 最大解码 | 4K | 8K |
| AV1 解码 | ❌ | ✅ |
| AV1 编码 | ❌ | ❌ |
| H.264 / H.265 编解码 | ✅ | ✅ |

实际可用编码器以板子上 `ffmpeg -decoders | grep rkmpp` 实测为准。

---

## 7. 常见问题

**Q: 宿主机/容器里 `ldconfig -p` 找不到 mpp/rga 库，但硬件加速正常？**
A: 正常。Jellyfin 容器把库放在私有目录 `/usr/lib/jellyfin-ffmpeg/lib/`（不在 ldconfig 搜索路径），ffmpeg 通过 RPATH/LD_LIBRARY_PATH 直接加载；宿主机只需要内核驱动 + 设备节点，不需要用户态库。用 `find /usr/lib/jellyfin-ffmpeg -name '*rockchip_mpp*' -o -name '*rga*'` 或 `ldd /usr/lib/jellyfin-ffmpeg/ffmpeg | grep -E 'rockchip_mpp|rga'` 确认。

**Q: `./configure` 报找不到 rockchip_mpp？**
A: 先编译 MPP 并安装，再 `export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH`；或确认系统已装 dev 包。

**Q: 运行时 Segmentation fault？**
A: 大概率是 MPP userspace 库版本与内核驱动不匹配。用板子系统自带的库（BSP 镜像配套），不要用自行编译的新版库覆盖。

**Q: 如何确认内核是 Rockchip BSP？**
A: `uname -r` 看是否带 rockchip 后缀；`ls /dev/mpp_service` 看设备节点是否存在。

**Q: 一定要在板子上编译吗？**
A: 不必。x86_64 交叉编译或 GitHub Actions 产出的 arm64 二进制可直接拷到板子运行（Jellyfin 镜像本身就是 x86_64 容器里交叉编译的）。唯一要求是板子内核驱动与 MPP/RGA 库匹配。
