#!/usr/bin/env bash
# 本地复现 GitHub Actions 的构建流程（不含推送）。
# 用法：
#   bash scripts/build.sh            # 使用根目录 VERSION 文件里的版本，默认构建 amd64 + arm64
#   bash scripts/build.sh 0.71.0    # 指定版本
#   ARCH=arm64 bash scripts/build.sh 0.71.0   # 只构建 arm64（可选 amd64|arm64|all）
#   DOCKERHUB_USERNAME=yvvv bash scripts/build.sh 0.71.0   # 仅本地构建并打 tag（不推送）

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(cat VERSION)}"
USER="${DOCKERHUB_USERNAME:-yvvv}"
ARCH="${ARCH:-all}"   # all | amd64 | arm64
echo ">>> 目标版本: $VERSION  架构: $ARCH"

echo ">>> 1/4 克隆 frp 源码"
rm -rf 代码
git clone --depth 1 --branch "v${VERSION}" https://github.com/fatedier/frp.git 代码

echo ">>> 2/4 应用汉化补丁 汉化/manual.patch"
git -C 代码 apply 汉化/manual.patch

echo ">>> 3/4 编译前端 (frps / frpc)"
cd 代码/web
npm install --no-audit --no-fund
(cd frps && npm install --no-audit --no-fund && npm run build-only)
(cd frpc && npm install --no-audit --no-fund && npm run build-only)
cd ../..

build_arch() {
  local arch="$1"
  local suffix=""
  [ "$arch" = "arm64" ] && suffix="-arm64"
  echo ">>> 4/4 构建镜像 (linux/$arch -> ${USER}/frps:${VERSION}${suffix} / ${USER}/frpc:${VERSION}${suffix})"
  docker buildx build --platform "linux/$arch" --file Dockerfile-frps --tag "${USER}/frps:${VERSION}${suffix}" --output type=docker .
  docker buildx build --platform "linux/$arch" --file Dockerfile-frpc --tag "${USER}/frpc:${VERSION}${suffix}" --output type=docker .
  echo ">>> 已构建 ${USER}/frps:${VERSION}${suffix} 与 ${USER}/frpc:${VERSION}${suffix}"
}

if [ "$ARCH" = "all" ] || [ "$ARCH" = "amd64" ]; then
  build_arch amd64
  # amd64 额外打 :latest 标签，与自动构建推送保持一致
  docker tag "${USER}/frps:${VERSION}" "${USER}/frps:latest"
  docker tag "${USER}/frpc:${VERSION}" "${USER}/frpc:latest"
fi
if [ "$ARCH" = "all" ] || [ "$ARCH" = "arm64" ]; then
  build_arch arm64
fi

echo ">>> 完成。需要推送时执行："
[ "$ARCH" = "all" ] || [ "$ARCH" = "amd64" ] && echo "    docker push ${USER}/frps:${VERSION} && docker push ${USER}/frps:latest"
[ "$ARCH" = "all" ] || [ "$ARCH" = "amd64" ] && echo "    docker push ${USER}/frpc:${VERSION} && docker push ${USER}/frpc:latest"
[ "$ARCH" = "all" ] || [ "$ARCH" = "arm64" ] && echo "    docker push ${USER}/frpc:${VERSION}-arm64"
[ "$ARCH" = "all" ] || [ "$ARCH" = "arm64" ] && echo "    docker push ${USER}/frpc:${VERSION}-arm64"

# 若需把当前改动重新生成为补丁（上游升级后刷新汉化用）：
#   cd 代码 && git diff > ../汉化/manual.patch
