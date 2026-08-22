# DeepSeek Harness Docker 快速部署版

> **通用安装说明。** 用最简单的方式，把 DeepSeek Harness 装到你的 **x86_64（Intel/AMD）** 设备上——NAS、Linux 服务器、云主机、普通电脑、Windows/WSL 都可以；**ARM 设备暂不支持**。
> **非官方项目**：本镜像是社区独立构建，与 DeepSeek（深度求索）官方没有隶属、合作或背书关系。

## 这是什么

DeepSeek Harness 是 DeepSeek 的一个**智能助手（AI Agent）**。你在浏览器里和它对话，它能在你的设备上替你**办事**——整理文件、查资料、写代码、跑脚本等。

本项目把它打包成一个**现成的 Docker 镜像**，你只需要：**拿镜像 → 填几行配置 → 启动 → 浏览器打开**。镜像名里的「**NAS**」只是作者的命名习惯，**不是只能用 NAS**。

装好后自带：

- **加密访问**：自签名 HTTPS 证书，流量加密
- **登录保护**：需要账号密码才能使用
- **数据保存**：升级 / 重启 / 迁移都不丢账号和数据
- **国内加速**：下载、更新走国内镜像源，更快

## 运行环境要求（重要）

| 判定 | 说明 |
| --- | --- |
| ✅ 支持 | **x86_64（Intel/AMD）** 架构的 Docker 设备：NAS、Linux 服务器、云主机、桌面 Linux、Windows/WSL 都可以 |
| ❌ 暂不支持 | **ARM 架构**：M 系列 Mac 的 Docker、ARM 版 NAS、树莓派等 |
| 配置 | 建议 2 核、4G 内存以上 |

## 开始前，你需要准备

| 需要 | 说明 |
| --- | --- |
| 一台设备 | 见上方「运行环境要求」，NAS 或普通电脑都行 |
| DeepSeek API Key | 到 [platform.deepseek.com](https://platform.deepseek.com) 注册，在「API Keys」页创建一个，复制这串 `sk-` 开头的密钥。它相当于 AI 干活的通行证 |
| 一点点耐心 | 全程约 5 分钟 |

> **还没有 API Key？** 点上面的链接去注册、充值（按量计费）后创建，复制保存。

## 目录

**新手必读**

- [获取镜像](#获取镜像)
- [快速安装](#快速安装)
- [首次使用](#首次使用)
- [常见问题](#常见问题)

**进阶可选**

- [环境变量速查](#环境变量速查)
- [局域网与公网访问](#局域网与公网访问)
- [设置页本机打开配置 API Key](#设置页本机打开配置-api-key)
- [公网访问（Cloudflare Tunnel）](#公网访问cloudflare-tunnel)
- [安全建议](#安全建议)
- [一键本地构建](#一键本地构建)
- [技术细节与许可证](#技术细节与许可证)

## 获取镜像

镜像已发布到 GitHub 容器仓库，任选一条命令拉取：

- **大陆推荐（南大镜像加速，速度快）**：

  ```bash
  docker pull ghcr.nju.edu.cn/wljaboy/deepseek-harness-nas:latest
  ```

- **GitHub 直连**：

  ```bash
  docker pull ghcr.io/wljaboy/deepseek-harness-nas:latest
  ```

> **也可以不手动拉**：下面的 `docker compose up -d` 会自动拉取镜像，效果一样。

## 快速安装

两种方式，结果一样。**方式一适合会一点点命令行的**；**方式二适合用 NAS 图形界面的**。

### 方式一（推荐）：直接用镜像

**不需要 git clone、不需要下载源码**，只要 3 个小文件。

#### 第 1 步：新建一个文件夹

随便在哪，新建一个文件夹（比如 `deepseek-harness`），进去。

#### 第 2 步：新建 `docker-compose.yml`

在里面新建一个文件，命名为 `docker-compose.yml`，粘贴下面的内容：

```yaml
services:
  deepseek-harness:
    image: ghcr.nju.edu.cn/wljaboy/deepseek-harness-nas:latest
    container_name: deepseek-harness
    restart: unless-stopped
    shm_size: 1gb
    ports:
      - "8443:8443"
      # 回环设置端口（可选，见文末「设置页本机打开」）；只绑定本机，不暴露公网
      - "127.0.0.1:${DSH_SETUP_PORT:-18080}:${DSH_SETUP_PORT:-18080}"
    environment:
      HTTPS_ACCESS_HOST: "${HTTPS_ACCESS_HOST}"
      DSH_PUBLIC_HOST: "${DSH_PUBLIC_HOST:-}"
      DSH_SETUP_PORT: "${DSH_SETUP_PORT:-}"
      DSH_AUTH_USERNAME: "${DSH_AUTH_USERNAME:-}"
      DSH_AUTH_PASSWORD: "${DSH_AUTH_PASSWORD:-}"
      DEEPSEEK_API_KEY: "${DEEPSEEK_API_KEY:-}"
      DSH_TELEMETRY_DISABLED: "1"
    volumes:
      - "${DSH_DATA_PATH}:/data/dsh"
      - "${WORKSPACE_PATH}:/workspace"
```

#### 第 3 步：新建 `.env`

再新建一个文件，命名为 `.env`，粘贴下面内容，并把 `你的IP` `你的密码` `你的密钥` 改成自己的：

```ini
# 你的设备局域网 IP（如 192.168.1.100；不知道怎么查，见下方小贴士）
HTTPS_ACCESS_HOST=192.168.1.100

# 可选：公网域名（配合 Cloudflare Tunnel，让局域网和公网都能访问）
# DSH_PUBLIC_HOST=your.domain.com

# 登录用户名（随便取，如 admin）
DSH_AUTH_USERNAME=admin

# 登录密码（至少 12 位，请设独立强密码）
DSH_AUTH_PASSWORD=请改成你的强密码

# DeepSeek 的 API Key（必填）
DEEPSEEK_API_KEY=sk-你的密钥

# 数据保存目录（改成你设备上的真实绝对路径）
DSH_DATA_PATH=/volume1/docker/deepseek-harness/data
WORKSPACE_PATH=/volume1/docker/deepseek-harness/workspace

# 可选：回环设置端口（想用网页配置 API Key 时用，见文末）
# DSH_SETUP_PORT=18080
```

> **小贴士：怎么查局域网 IP？** 在设备上打开终端，Linux 输 `ip addr`、Windows 输 `ipconfig`，找 `192.168.x.x` 那行。

#### 第 4 步：启动

```bash
docker compose up -d
```

第一次会自动拉取镜像并启动，等 1～3 分钟。

#### 第 5 步：访问

浏览器打开：**`https://你的局域网IP:8443`**（例如 `https://192.168.1.100:8443`）

- 第一次会提示「证书不受信任」——**正常**（自签名证书）。点「高级 → 继续前往你的 IP」即可。
- 用你 `.env` 里设置的账号密码登录。
- 进入后即可使用。

### 方式二：NAS 图形界面（群晖 / 威联通）

1. 把方式一第 2 步的 `docker-compose.yml` 内容复制下来。
2. 打开群晖 **Container Manager → 项目 → 新增**，或威联通 **Container Station → 应用程序 → 创建**，粘贴这份「Compose / YAML」。
3. 在界面里把 `HTTPS_ACCESS_HOST`、`DSH_AUTH_USERNAME`、`DSH_AUTH_PASSWORD`、`DEEPSEEK_API_KEY` 等填成你的值（或用 `.env`）。
4. 点「应用 / 创建」，等它启动。
5. 浏览器打开 `https://局域网IP:8443` 使用（同上）。

> 不同机型菜单名不同；找不到就找「导入 Compose / 导入 YAML」。

### 可选：用 git clone 拿项目副本（普通用户不需要）

「快速安装」已经不需要 clone。`git clone` 仅供**想本地构建镜像、改默认配置、拿全部脚本**的进阶用户：

```bash
git clone https://github.com/wljaboy/deepseek-harness-docker.git
cd deepseek-harness-docker
```

> 之后可用里面的 `scripts/build.sh` 自己构建（见文末「一键本地构建」）。

## 首次使用

### 登录账号

第一次打开网页，如果之前没在 `.env` 填用户名密码，页面会显示「首次设置」。填写：

- 用户名
- 密码（至少 12 位）

保存后自动启用登录保护，之后每次都用它登录。

### 配置模型 API Key

**如果你已按上面方式在 `.env` 里填了 `DEEPSEEK_API_KEY`，这一步已完成，直接跳过。**

如果从局域网 IP（如 `https://192.168.1.100:8443`）访问网页，可能会看到设置页提示：

> **settings are unavailable in this browser**

**这不是坏了**，而是 DeepSeek Harness 的规定：设置页只能在「本机打开」时使用（官方安全限制，远程访问时关闭设置，防止密钥被远程读取）。

**最简单的解决办法**：不通过网页，改用环境变量。在 `.env` 里加一行：

```ini
DEEPSEEK_API_KEY=sk-你的密钥
```

然后重启容器：

```bash
docker compose up -d
```

AI 就能用了。以后换模型也可以这样填（比如 `OPENAI_API_KEY=...`）。

> 想**在网页里**配置 API Key（更高级）？见[设置页本机打开配置 API Key](#设置页本机打开配置-api-key)，需要会用 SSH 端口转发，新手可以跳过。

## 局域网与公网访问

- **局域网**：浏览器访问 `https://你的局域网IP:8443` 即可。
- **同时支持公网**：在 `.env` 里多设一个 `DSH_PUBLIC_HOST=你的公网域名`（配合 Cloudflare Tunnel），局域网 IP 与公网域名就能**同时访问**。详见[公网访问（Cloudflare Tunnel）](#公网访问cloudflare-tunnel)。

## 常见问题

### 1. 打开显示「证书不受信任」？

正常。这是设备自签名的加密证书。点「高级 → 继续前往你的 IP/域名」即可。

### 2. 页面空白或 502？

- 确认你在**局域网内**（或已连 VPN）访问 `https://局域网IP:8443`。
- 确认 `.env` 里的 `HTTPS_ACCESS_HOST` 填的就是这个 IP。

### 3. 设置页提示 settings are unavailable in this browser？

官方限制：设置页只能本机打开。按[首次使用](#首次使用)的方式，在 `.env` 里填 `DEEPSEEK_API_KEY` 即可，不用进设置页。

### 4. 网页一直没有反应 / 很慢？

先看日志（`docker logs -f deepseek-harness`），正常应出现 `dsh web: http://127.0.0.1:3080`。如果没出现，稍等或重启容器。

### 5. API Key 填了还是不能用？

- 检查 `DEEPSEEK_API_KEY` 是否以 `sk-` 开头、复制是否完整。
- 检查 DeepSeek 账户是否已充值（按量计费）。
- 确认 `.env` 保存后执行过 `docker compose up -d` 重启。

### 6. 换了 DeepSeek 之外的模型？

在 `.env` 里补上对应 Key（如 `OPENAI_API_KEY=...`）并重启。

## 环境变量速查

| 变量 | 必填 | 说明 |
| --- | --- | --- |
| `HTTPS_ACCESS_HOST` | 是 | 设备局域网 IP（或公网域名，纯域名，不带协议和端口） |
| `DSH_PUBLIC_HOST` | 否 | 可选公网域名（纯域名）；设置后局域网 IP 与公网域名同时可访问，配合 Cloudflare Tunnel 使用 |
| `DEEPSEEK_API_KEY` | 否 | DeepSeek 的 API Key；填了即可直接用，无需进设置页 |
| `DSH_AUTH_USERNAME` | 否 | 登录用户名（留空则首次访问时在网页上设置） |
| `DSH_AUTH_PASSWORD` | 否 | 登录密码（留空则首次访问时在网页上设置，至少 12 位） |
| `DSH_TELEMETRY_DISABLED` | 否 | 设为 `1` 关闭遥测上报 |
| `DSH_INSTALL_MARKET` | 否 | 是否自动安装插件市场 dshmarket（默认 `1`=装；`0`=关闭） |
| `DSH_SETUP_PORT` | 否 | 回环设置代理端口（如 `18080`）；留空=关闭，用于本机打开设置页 |
| `GH_PROXY` | 否 | 容器内 git 下载 GitHub 的代理前缀（默认已内置国内加速，设为空可关闭） |
| `NPM_REGISTRY` | 否 | 覆盖容器内 npm 镜像源（默认已内置 npmmirror） |

## 设置页本机打开配置 API Key

> **适用范围**：你确实想用 DSH 网页设置页（添加/更换模型、API Key），或网页提示 `settings are unavailable` 时。

**为什么设置页打不开**：DeepSeek Harness 官方规定 DSH web 只能绑定 `127.0.0.1`，且设置/凭据等接口只在浏览器以**本机地址**（`127.0.0.1` / `localhost` / `[::1]`）打开时才开放（防止远程读取密钥）。所以我们从局域网 IP 访问时，设置页不开放。

**解决办法**：本镜像内置一个「回环设置代理」，开辟一条只在本机可用的通道。需要会用一点 SSH，步骤如下：

1. 在 `.env` 里启用端口：

   ```ini
   DSH_SETUP_PORT=18080
   ```

2. 重启容器：`docker compose up -d`

3. 在你自己的电脑上打开终端，建一条 SSH 隧道（把本地 18080 连到你设备的回环 18080）：

   ```bash
   ssh -L 18080:127.0.0.1:18080 用户名@你的设备IP
   ```

4. 浏览器打开：`http://127.0.0.1:18080`（此时是「本机」打开，设置页就能用了）。

5. 进入「设置 → 模型」添加提供方并粘贴 API Key。

6. 配好后关闭 SSH 隧道窗口即可。之后正常用 `https://设备IP:8443` 对话即可（远程下设置页仍属官方行为而关闭）。

> ⚠️ 安全：这个端口在 docker 里已固定只绑定宿主机 `127.0.0.1`，请**不要**改成 `0.0.0.0` 或映射到公网，否则等于绕过 DSH 的回环安全限制。

## 公网访问（Cloudflare Tunnel）

无公网 IP 或不想开放端口时，推荐用 Cloudflare Tunnel 免费内网穿透。

**前置条件**：一个托管在 Cloudflare 的域名。

### 1. 加一个 cloudflared 容器

在你的 `docker-compose.yml` 里，`services:` 下追加：

```yaml
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    command: tunnel --no-autoupdate run --token <你的隧道Token>
    networks:
      - default
```

### 2. 修改配置

保持 `HTTPS_ACCESS_HOST` 为你的局域网 IP，再新增公网域名（纯域名，不带协议端口）：

```ini
HTTPS_ACCESS_HOST=192.168.1.100
DSH_PUBLIC_HOST=harness.yourdomain.com
```

### 3. 重启

```bash
docker compose up -d
```

### 4. Cloudflare 面板配置

进 Cloudflare → Zero Trust → Networks → Tunnels → 你的隧道 → Public Hostname → Add a public hostname：

| 配置项 | 值 |
| --- | --- |
| Subdomain / Domain | 例如 `harness` / `yourdomain.com` |
| Service Type | **HTTPS** |
| URL | **你的局域网访问地址**，如 `https://192.168.1.100:8443`（端口写你实际映射的） |
| No TLS Verify | **开启**（容器内为自签名证书） |

### 5. 访问

浏览器打开 `https://harness.yourdomain.com`，证书由 Cloudflare 提供，无自签名提示。

**效果**：局域网直接用 `https://局域网IP:8443`，公网用 `https://harness.yourdomain.com`，两者同时可用。因为 Caddy 已直接接受该域名 Host，**无需在 Cloudflare 面板覆盖 Host header**。

> 若你之前是「把 `HTTPS_ACCESS_HOST` 改成域名、靠面板覆盖 Host」的老用法，现在改用 `HTTPS_ACCESS_HOST=局域网IP + DSH_PUBLIC_HOST=域名` 即可，更简单，且两者都通。

## 安全建议

- 首次部署务必设置 ≥12 位强密码，不要用默认密码。
- **公网访问优先用 Cloudflare Tunnel**，不要在路由器上直接开放端口到公网。
- 不要把容器内部端口（如 3080）映射到公网。
- 回环设置端口 `DSH_SETUP_PORT` 请保持仅绑定宿主机 `127.0.0.1`，勿映射到公网。
- 保持镜像更新到最新版。

## 一键本地构建

适合离线环境或想自己构建某个版本。构建时已默认启用国内加速（apt 阿里云、npm npmmirror、pip 清华、GitHub 代理、Caddy 双向校验）。

```bash
git clone https://github.com/wljaboy/deepseek-harness-docker.git
cd deepseek-harness-docker
./scripts/build.sh --save   # 构建并导出 tar.gz；默认自动检测最新 DSH 版本，也可 DSH_VERSION=... 指定

docker load -i deepseek-harness-nas-<DSH_VERSION>-cn.tar.gz
docker compose up -d        # compose 中 image 改为本地 tag
```

## 技术细节与许可证

### 镜像组成

| 组件 | 来源 | 许可证 |
| --- | --- | --- |
| DeepSeek Harness | 官方 npm 包 `@deepseek-ai/dsh`（[deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)） | MIT |
| Node.js 22 | 官方 `node:22-bookworm` 镜像 | MIT / BSD |
| Caddy | 官方 GitHub Release（官方 checksums 双重校验） | Apache-2.0 |
| 部署壳（HTTPS/登录/持久化） | 本仓库原创实现 | 见 LICENSE |

### 数据保存目录

- `${DSH_DATA_PATH}/data`：认证配置（`.dsh-auth.json`）与 DSH 数据
- `${WORKSPACE_PATH}`：工作区

### 更新镜像

```bash
docker compose pull
docker compose up -d
```

### 许可证与免责

- **上游许可证**：本镜像基于 `deepseek-harness`（MIT License，Copyright (c) 2026 DeepSeek）按 MIT 条款再分发；Caddy 按 Apache-2.0；Node.js 按 MIT/BSD。
- **本仓库原创代码**（入口脚本、Caddyfile、构建脚本、文档）版权归作者所有，许可见 LICENSE 文件。
- **商标声明**：「DeepSeek」为深度求索公司商标，本镜像为**独立社区项目**，与官方无隶属/合作/背书关系，不使用官方 Logo。
- 使用本镜像即表示同意遵守上述开源许可证；调用模型服务产生的费用与合规问题由最终用户自行承担。
- 作者不对因使用本镜像造成的任何直接或间接损失负责。
