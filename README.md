# DeepSeek Harness NAS Docker 镜像（中国大陆网络加速版）

将官方 **DeepSeek Harness** 打包为 x86_64 NAS 可用的 Docker 镜像。
**全部组件来自官方渠道**，部署壳为本仓库原创实现，内置中国大陆网络加速，部署后无需任何额外配置。

## 镜像组成（100% 官方来源）

| 组件 | 来源 | 说明 |
| --- | --- | --- |
| DeepSeek Harness | 官方 npm 包 @deepseek-ai/dsh | 官方项目 [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) 的正式发布物，构建时 npm install -g（走国内 npmmirror 镜像） |
| Node.js 22 | 官方 node:22-bookworm 镜像 | Docker 官方镜像，国内构建时自动走可用镜像源 |
| Caddy | 官方 GitHub Release 下载 | 下载后以官方 caddy_<版本>_checksums.txt 的 SHA-512 校验 + 二进制 SHA-256 双保险 |
| 部署壳（HTTPS/登录/持久化） | **本仓库原创实现** | 入口脚本 + Caddyfile，不依赖任何第三方镜像 |

> 官方项目 deepseek-ai/deepseek-harness 只发布源码和 npm 包，没有官方 Docker 镜像。
> 本镜像的 Docker 部署方案（Node + Caddy HTTPS 反向代理 + 登录保护）为本仓库自行编写。

## 镜像发布位置

本仓库通过 GitHub Actions 自动构建镜像并推送到 GitHub 容器仓库（ghcr.io）：

```text
ghcr.io/wljaboy/deepseek-harness-nas:0.1.0-rc.7   （跟随官方 npm 包版本号）
ghcr.io/wljaboy/deepseek-harness-nas:latest       （最新版）
```

## 快速开始

### 方式一：直接拉取镜像（推荐）

在中国大陆网络下，使用南大镜像站加速拉取（实测 5MB/s），无需访问 Docker Hub：

```bash
# 1. 拉取镜像（国内加速）
docker pull ghcr.nju.edu.cn/wljaboy/deepseek-harness-nas:latest

# 2. 创建持久化目录
mkdir -p /volume1/docker/deepseek-harness/{data,workspace}

# 3. 复制 .env.example 为 .env 并填写
cp .env.example .env

# 4. 启动
docker compose up -d
```

不使用 compose 的话，也可以直接运行：

```bash
docker run -d \
  --name deepseek-harness \
  --restart unless-stopped \
  --shm-size 1gb \
  -p 8443:8443 \
  -e HTTPS_ACCESS_HOST=192.168.1.111 \
  -e DSH_AUTH_USERNAME=admin \
  -e DSH_AUTH_PASSWORD=你的至少12位密码 \
  -e DSH_TELEMETRY_DISABLED=1 \
  -v /volume1/docker/deepseek-harness/data:/data/dsh \
  -v /volume1/docker/deepseek-harness/workspace:/workspace \
  ghcr.nju.edu.cn/wljaboy/deepseek-harness-nas:latest
```

启动后访问：`https://NAS局域网IP:8443`（用户名密码见 .env）。

> 注意：镜像由 GitHub Actions 自动构建推送，**首次使用前请先到仓库 Actions 页面手动运行一次**
> `auto-rebuild` 工作流（之后每天自动检查官方新版本）。如果 Actions 尚未运行，镜像可能还不存在。

### 方式二：本地构建 / 导入镜像包

```bash
git clone https://github.com/wljaboy/deepseek-harness-docker.git
cd deepseek-harness-docker
./scripts/build.sh --save    # 构建并导出 deepseek-harness-nas-0.1.0-rc.7-cn.tar.gz

# 把 tar.gz 拷到 NAS 后：
docker load -i deepseek-harness-nas-0.1.0-rc.7-cn.tar.gz
docker compose up -d          # 记得把 compose 里的 image 改为本地 tag
```

## 一键构建（在国内 NAS / 服务器上执行）

```bash
git clone https://github.com/wljaboy/deepseek-harness-docker.git
cd deepseek-harness-docker
./scripts/build.sh --save
```

构建脚本会自动完成：

1. 从国内镜像源拉取基础镜像 node:22-bookworm（候选：daocloud / 1ms.run / hub.rat.dev）
2. 通过国内代理下载官方 Caddy 二进制，并用官方 checksums.txt 的 SHA-512 + 二进制 SHA-256 双重校验
3. 使用清华 apt 源 + npmmirror 构建
4. 导出 deepseek-harness-nas-<版本>.tar.gz

### 常用参数

```bash
DSH_VERSION=0.1.0-rc.7 ./scripts/build.sh --save   # 指定版本（默认已是最新 0.1.0-rc.7）
GH_PROXY=https://ghfast.top/ ./scripts/build.sh     # 构建期启用 GitHub 代理
```

## 官方 DeepSeek Harness 更新后，我的镜像如何同步？

可以同步，有两种方式：

### 方式一：GitHub Actions 全自动（推荐）

本仓库包含 .github/workflows/auto-rebuild.yml：

- **每天自动检查**官方 npm 包（@deepseek-ai/dsh）是否有新版本
- 有新版本时自动构建并推送到 ghcr.io/wljaboy/deepseek-harness-nas:<新版本> 和 :latest
- 也可以到 GitHub 仓库的 **Actions → auto-rebuild → Run workflow** 手动触发

> 拉取新镜像：docker pull ghcr.nju.edu.cn/wljaboy/deepseek-harness-nas:latest

### 方式二：手动一行命令

```bash
DSH_VERSION=<官方新版本号> ./scripts/build.sh --save
```

## ghcr.io 与 Docker Hub 有什么区别？选哪个？

| | ghcr.io（GitHub 容器仓库） | Docker Hub |
| --- | --- | --- |
| 归属 | GitHub 官方 | Docker 官方 |
| 与 GitHub 账号绑定 | 登录 GitHub 即可推送 | 需单独注册账号 |
| 中国大陆直连 | 慢（blob 约 20KB/s） | **基本被墙** |
| 国内加速方案 | ghcr.nju.edu.cn 等镜像（实测 5MB/s） | daocloud / 1ms.run 等镜像 |

**结论**：镜像发布在 ghcr.io（GitHub 账号免注册），拉取时使用国内镜像前缀 ghcr.nju.edu.cn/ 加速。
如果你已有 Docker Hub 账号，也可以把 IMAGE_NAME 环境变量改为你的 Docker Hub 账号再发一份。

## 环境变量说明

| 变量 | 必填 | 说明 |
| --- | --- | --- |
| HTTPS_ACCESS_HOST | 是 | NAS 局域网 IP 或公网域名（纯域名，不带协议/端口） |
| DSH_AUTH_USERNAME | 是 | 登录用户名 |
| DSH_AUTH_PASSWORD | 是 | 登录密码，**至少 12 字符** |
| DSH_TELEMETRY_DISABLED | 否 | 设为 1 关闭遥测 |
| GH_PROXY | 否 | 容器内 git clone 的 GitHub 代理前缀，如 https://ghfast.top/ |
| NPM_REGISTRY | 否 | 覆盖容器内 npm 镜像源（默认已内置 npmmirror） |

## 常见问题

### 页面空白 / 502 Bad Gateway

- 页面空白：请求的 Host 与 HTTPS_ACCESS_HOST 不一致，检查回源 Host 配置。
- 502：DSH web 未监听 3080，查看日志应出现 dsh web: http://127.0.0.1:3080。

### docker pull 提示镜像不存在（manifest unknown）？

说明 GitHub Actions 尚未构建推送。请到仓库 **Actions** 页面手动运行一次 auto-rebuild 工作流，
或在本地执行 ./scripts/build.sh --save 自行构建。

### 镜像里装的软件还需要我手动配置国内源吗？

不需要。apt 源、npm 源、pip 源、重试策略全部已内置，容器内直接使用即走国内加速。

### 为什么基础镜像要用完整版（node:22-bookworm）而不是 slim？

DSH 插件可能需要编译原生模块（node-gyp），完整版自带编译工具链，与官方镜像一致。

### Caddy 二进制怎么保证是官方的？

从官方 GitHub Release（caddyserver/caddy）下载，下载后：
1. 用官方 caddy_<版本>_checksums.txt 中的 SHA-512 校验压缩包
2. 解压后二进制再与期望 SHA-256 比对（双保险）
3. 校验不通过立即中止，不进入镜像
