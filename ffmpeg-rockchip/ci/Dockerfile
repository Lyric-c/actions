# ffmpeg-rockchip arm64 部署镜像（无 RUN，纯 COPY，任何架构的构建机都能直接 build）
# 构建: docker buildx build --platform linux/arm64 -t ffmpeg-rockchip:arm64 -f ci/Dockerfile deploy
# 运行: docker run --rm --device=/dev/mpp_service:/dev/mpp_service \
#                    --device=/dev/rga:/dev/rga --device=/dev/dri:/dev/dri \
#       ffmpeg-rockchip:arm64 -hwaccel rkmpp -c:v hevc_rkmpp -i input.mkv ...

FROM ubuntu:22.04

COPY ffmpeg-rockchip/ /opt/ffmpeg-rockchip/

ENV LD_LIBRARY_PATH=/opt/ffmpeg-rockchip/lib

ENTRYPOINT ["/opt/ffmpeg-rockchip/bin/ffmpeg"]
