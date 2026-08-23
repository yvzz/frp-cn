#!/usr/bin/env bash
# 按宿主机架构自动选择 frps 镜像标签并启动：
#   x86_64 / amd64  -> yvvv/frps:0.71.0
#   aarch64 / arm64 -> yvvv/frps:0.71.0-arm64
# 也可手动覆盖：FRP_IMAGE=yvvv/frps:0.71.0-arm64 ./run-frps.sh
set -euo pipefail
cd "$(dirname "$0")"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)  TAG="yvvv/frps:0.71.0" ;;
  aarch64|arm64) TAG="yvvv/frps:0.71.0-arm64" ;;
  *) echo "未知架构 $ARCH，默认使用 amd64 镜像"; TAG="yvvv/frps:0.71.0" ;;
esac

# 允许环境变量手动覆盖
export FRP_IMAGE="${FRP_IMAGE:-$TAG}"
echo "检测到架构 $ARCH，使用镜像 $FRP_IMAGE"
docker compose -f frps-docker-compose.yml up -d
docker compose -f frps-docker-compose.yml ps
