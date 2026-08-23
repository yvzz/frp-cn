#!/usr/bin/env bash
# 本地复现 GitHub Actions 的构建流程（不含推送）。
# 用法：
#   bash scripts/build.sh            # 使用根目录 VERSION 文件里的版本
#   bash scripts/build.sh 0.71.0    # 指定版本
#   DOCKERHUB_USERNAME=yvvv bash scripts/build.sh 0.71.0   # 仅本地构建并打 tag（不推送）

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(cat VERSION)}"
USER="${DOCKERHUB_USERNAME:-yvvv}"
echo ">>> 目标版本: $VERSION"

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

echo ">>> 4/4 构建镜像 (linux/amd64)"
docker buildx build --platform linux/amd64 --file Dockerfile-frps --tag "${USER}/frps:${VERSION}" --output type=docker .
docker buildx build --platform linux/amd64 --file Dockerfile-frpc --tag "${USER}/frpc:${VERSION}" --output type=docker .

echo ">>> 完成。需要推送时执行："
echo "    docker push ${USER}/frps:${VERSION}"
echo "    docker push ${USER}/frpc:${VERSION}"

# 若需把当前改动重新生成为补丁（上游升级后刷新汉化用）：
#   cd 代码 && git diff > ../汉化/manual.patch
