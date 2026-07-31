# CMake cross-compilation toolchain for aarch64 (arm64)
# 用法: cmake -DCMAKE_TOOLCHAIN_FILE=/path/to/toolchain-arm64.cmake ...
# 基于 nyanmisaka/jellyfin-ffmpeg 的官方 toolchain-arm64.cmake 适配:
#   - 安装前缀统一使用 /opt/ffmpeg-rockchip
#   - 查找路径同时覆盖系统 arm64 库与本项目安装目录

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_RANLIB aarch64-linux-gnu-ranlib)
set(CMAKE_AR aarch64-linux-gnu-ar)

set(CMAKE_FIND_ROOT_PATH /usr/aarch64-linux-gnu /opt/ffmpeg-rockchip)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
