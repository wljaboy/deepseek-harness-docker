# DeepSeek Harness NAS（中国大陆网络加速版）

面向 **x86_64 NAS** 的 DeepSeek Harness Docker 镜像，基于官方
[ghcr.io/kanzuori197/deepseek-harness-nas](https://github.com/kanzuori197/deepseek-harness-nas)
改造，**行为与官方完全一致**，同时针对中国大陆网络做了全套加速，部署后无需任何额外配置。

## 本版相比官方的改进

| 问题 | 本版的解决方案 |
| --- | --- |
| GitHub / Docker Hub / git clone 网络不畅 | 基础镜像自动走国内镜像源；构建产物直接导出为 `.tar.gz`，NAS 上 `docker load` 导入，**完全不需要访问 Docker Hub** |
| `apt install` 下载中断、龟速 | 内置清华 apt 镜像源 + 下载失败自动重试 5 次、超时 60 秒 |
| npm / npx 下载慢 | 内置 npmmirror（淘宝）npm 镜像源，容器内安装 DSH 插件也自动加速 |
| pip 下载慢 | 内置清华 PyPI 镜像源 |
| git clone 慢（容器内） | 可选 `GH_PROXY` 环境变量一键开启 GitHub 代理加速 |
| 官方更新后镜像无法同步 | 提供 GitHub Actions 自动重建工作流 + 一行命令手动重建 |

## 快速开始（推荐：直接用构建好的镜像包）

本仓库的 `scripts/build.sh` 可在国内网络一键构建；构建后自动导出
`deepseek-harness-nas-<版本>.tar.gz`，把该文件拷到 NAS 上：

```bash
# 1. 导入镜像（无需外网）
docker load -i deepseek-harness-nas-0.1.0-rc.6-cn.tar.gz

# 2. 创建持久化目录
mkdir -p /volume1/docker/deepseek-harness/{data,workspace}

# 3. 复制 .env.example 为 .env 并填写
cp .env.example .env

# 4. 启动
docker compose up -d
```

启动后访问：`https://NAS局域网IP:8443`（用户名密码见 .env）。

## 一键构建（在国内 NAS / 服务器上执行）

```bash
git clone https://github.com/kanzuori197/deepseek-harness-nas.git
cd deepseek-harness-nas
./scripts/build.sh --save
```

构建脚本会自动完成：

1. 从国内镜像源拉取基础镜像 `node:22-bookworm`（候选：daocloud / 1ms.run / hub.rat.dev）
2. 从南大 ghcr 镜像（`ghcr.nju.edu.cn`，实测 5MB/s）提取官方 Caddy 二进制
3. 使用清华 apt 源 + npmmirror 构建
4. 导出 `deepseek-harness-nas-<版本>.tar.gz`

### 常用参数

```bash
DSH_VERSION=0.1.0-rc.7 ./scripts/build.sh --save   # 跟随官方新版本
GH_PROXY=https://ghfast.top/ ./scripts/build.sh     # 构建期启用 GitHub 代理
```

## 官方 DeepSeek Harness 更新后，我的镜像如何同步？

可以同步，有两种方式：

### 方式一：GitHub Actions 全自动（推荐）

本仓库包含 `.github/workflows/auto-rebuild.yml`，推送到你的 GitHub 仓库后：

- **每天自动检查**官方 npm 包（`@deepseek-ai/dsh`）是否有新版本
- 有新版本时自动构建并推送到 `ghcr.io/<你的账号>/deepseek-harness-nas:<新版本>` 和 `:latest`
- 也可以到 GitHub 仓库的 **Actions → Run workflow** 手动触发

> 拉取新镜像：`docker pull ghcr.nju.edu.cn/<你的账号>/deepseek-harness-nas:latest`

### 方式二：手动一行命令

官方发布新版本后（例如 `0.1.0-rc.8`）：

```bash
DSH_VERSION=0.1.0-rc.8 ./scripts/build.sh --save
```

## ghcr.io 与 Docker Hub 有什么区别？选哪个？

| | ghcr.io（GitHub 容器仓库） | Docker Hub |
| --- | --- | --- |
| 归属 | GitHub 官方 | Docker 官方 |
| 与 GitHub 账号绑定 | ✅ 登录 GitHub 即可推送 | ❌ 需单独注册账号 |
| 中国大陆直连 | 慢（blob 约 20KB/s） | **基本被墙** |
| 国内加速方案 | `ghcr.nju.edu.cn` 等镜像（实测 5MB/s） | daocloud / 1ms.run 等镜像 |

**结论**：本仓库继续发布在 ghcr.io（与原项目一致、无需额外注册账号），但拉取时
使用国内镜像前缀 `ghcr.nju.edu.cn/` 加速。如果你已经有 Docker Hub 账号，
也可以在 Docker Hub 上再发一份（把 `IMAGE_NAME` 环境变量改为你的 Docker Hub 账号即可）。

## 环境变量说明

| 变量 | 必填 | 说明 |
| --- | --- | --- |
| `HTTPS_ACCESS_HOST` | ✅ | NAS 局域网 IP 或公网域名（纯域名，不带协议/端口） |
| `DSH_AUTH_USERNAME` | ✅ | 登录用户名 |
| `DSH_AUTH_PASSWORD` | ✅ | 登录密码，**至少 12 字符** |
| `DSH_TELEMETRY_DISABLED` | 否 | 设为 `1` 关闭遥测 |
| `GH_PROXY` | 否 | 容器内 git clone 的 GitHub 代理前缀，如 `https://ghfast.top/` |
| `NPM_REGISTRY` | 否 | 覆盖容器内 npm 镜像源（默认已内置 npmmirror） |

## 常见问题

### 页面空白 / 502 Bad Gateway

- 页面空白：请求的 Host 与 `HTTPS_ACCESS_HOST` 不一致，检查回源 Host 配置。
- 502：DSH web 未监听 3080，查看日志应出现 `dsh web: http://127.0.0.1:3080`。

### 镜像里装的软件还需要我手动配置国内源吗？

不需要。apt 源、npm 源、pip 源、重试策略全部已内置，容器内直接使用即走国内加速。

### 为什么基础镜像要用完整版（node:22-bookworm）而不是 slim？

DSH 插件可能需要编译原生模块（node-gyp），完整版自带编译工具链，与官方镜像一致。

## 构建来源

镜像从 npm 官方包 `@deepseek-ai/dsh` 构建，基础镜像为官方 `node:22-bookworm`，
Caddy 二进制与官方镜像完全一致（v2.10.2），不依赖第三方封装镜像。
