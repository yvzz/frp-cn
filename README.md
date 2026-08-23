# frp-cn

基于 frp 官方源码与社区中文汉化补丁，自动跟随上游版本构建的 **frp 汉化 Docker 镜像** 仓库。

> 本项目为衍生作品，所有核心成果均归功于下列原作者。请勿将他人劳动成果据为己有。

## 致谢 · 原作者与源码地址

本仓库的汉化补丁与构建思路均来自社区开源工作，请保留对原作者的尊重：

- **frp 原项目**（服务端 / 客户端本体）
  - 官网：<https://gofrp.org/zh-cn/>
  - GitHub 仓库：<https://github.com/fatedier/frp>
  - 许可证：Apache-2.0

- **frp 中文汉化 & 镜像制作**（本仓库 `patch/manual.patch` 的直接来源）
  - 汉化作者：**秦曱凧**（B 站：<https://space.bilibili.com/17547201>）
  - GitHub 仓库：<https://github.com/Firfr/frp_zh>
  - Gitee 仓库：<https://gitee.com/firfe/frp_zh>
  - DockerHub 镜像：
    - 服务端 <https://hub.docker.com/r/firfe/frps>
    - 客户端 <https://hub.docker.com/r/firfe/frpc>

## 本仓库在原有成果之上做了什么

- 复用上述中文汉化补丁（`patch/manual.patch`，基于 fatedier/frp 的 **v0.71.0** 源码生成）。
- 新增 **GitHub Actions 工作流**（`.github/workflows/build.yml`）：每日自动检测 `fatedier/frp` 上游是否有新 release，若有则 **克隆 → 打补丁 → 编译前端 → 多架构（linux/amd64、linux/arm64）构建并推送 DockerHub → 回写版本号**。
- 汉化补丁失配（上游大版本改动）时，工作流会**自动开 issue 报警**，而非静默发布旧版。
- 按本仓库所有者意愿，移除了编译产物内的「汉化：B站 秦曱凧」**应用内徽标**（仅去掉 UI 标记；原作者署名与贡献在本 README 中完整保留）。

## 目录结构

```
frp-cn/
├── .github/workflows/build.yml   # 自动跟随上游版本构建汉化镜像的工作流
├── patch/manual.patch             # 相对 v0.71.0 的完整汉化补丁
├── scripts/build.sh              # 本地一键复现脚本（克隆+打补丁+编译+构建）
├── Dockerfile-frps               # 基于公共镜像 golang:1.25 / alpine:3.23
├── Dockerfile-frpc
├── VERSION                      # 当前已构建版本
├── .dockerignore
└── .gitignore
```

## 镜像使用

工作流会将镜像推送到你在仓库 Secrets 中配置的目标账号（`DOCKERHUB_USERNAME`）：

```bash
docker pull <你的DockerHub用户名>/frps:<版本>
docker pull <你的DockerHub用户名>/frpc:<版本>
# 同时会打 :latest 标签
```

部署方式与原项目一致，参考 fatedier/frp 官方文档：<https://gofrp.org/zh-cn/docs/>

## 触发构建

- **定时**：每天 UTC 03:00 自动检查上游新版本。
- **手动**：仓库 `Actions → 构建 frp 汉化镜像 → Run workflow`，可填写指定版本（如 `0.71.0`）。

## 刷新汉化补丁（上游大版本更新时）

当上游源码行变动导致 `patch/manual.patch` 无法干净应用时，工作流会开 issue 提醒。刷新方法：

```bash
bash scripts/build.sh <新版本号>          # 克隆 + 打补丁 + 编译 + 构建
cd 代码 && git diff > ../patch/manual.patch   # 重新生成补丁
# 提交后再次手动触发工作流即可
```
