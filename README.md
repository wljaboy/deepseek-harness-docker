# DeepSeek Harness Docker（NAS 一键安装版）

> **这是给普通用户的安装说明。** 用最简单的方式，把 DeepSeek Harness 装到你的 NAS 或电脑上。
> **非官方项目**：本镜像是社区独立构建，与 DeepSeek（深度求索）官方没有隶属、合作或背书关系。镜像里的组件都来自官方发布渠道，部署壳为本项目原创。

## 这是什么

DeepSeek Harness 是 DeepSeek 的一个**智能助手（AI Agent）**。你在浏览器里和它对话，它能在你的设备上替你**办事**——整理文件、查资料、写代码、跑脚本等。

这个项目把 DeepSeek Harness 打包成一个**现成的 Docker 镜像**，你只需要：**下载 → 填几行配置 → 启动 → 浏览器打开**。

装好后自带：

- **加密访问**：用自签名 HTTPS 证书，流量加密
- **登录保护**：需要账号密码才能使用
- **数据保存**：升级 / 重启 / 迁移都不会丢账号和数据
- **国内加速**：下载、更新都走国内镜像源，速度更快

## 开始前，你需要准备

| 需要 | 说明 |
| --- | --- |
| 设备 | 一台能跑 Docker 的设备（NAS 或 Linux 电脑 / 服务器），建议 2 核 4G 以上 |
| DeepSeek API Key | 到 [platform.deepseek.com](https://platform.deepseek.com) 注册，在「API Keys」页创建一个，复制这串 `sk-` 开头的密钥。它相当于 AI 干活的通行证 |
| 一点点耐心 | 全程大约 5 分钟 |

> **还没有 API Key？** 先点上面的链接去注册。注册、充值（按量服务）后创建密钥，复制保存好。

## 目录

**新手必读**

- [快速安装](#快速安装)
- [首次使用](#首次使用)
- [局域网访问](#局域网访问)
- [更新与关闭](#更新与关闭)
- [常见问题](#常见问题)

**进阶可选**

- [环境变量速查](#环境变量速查)
- [设置页本机打开配置 API Key](#设置页本机打开配置-api-key)
- [公网访问](#公网访问)
- [安全建议](#安全建议)
- [一键本地构建](#一键本地构建)
- [技术细节与许可证](#技术细节与许可证)

## 快速安装

两种方式，结果一样。**方式一适合会一点点命令行的**，**方式二适合用 NAS 图形界面的**。

### 方式一：用命令行（推荐）

#### 第 1 步：下载项目文件

在设备上打开终端。有 git 就运行：

```bash
git clone https://github.com/wljaboy/deepseek-harness-docker.git
cd deepseek-harness-docker
```

没有 git：去仓库页面点 **Code → Download ZIP**，下载后解压到任意目录，然后进入这个目录（`cd deepseek-harness-docker`）。

#### 第 2 步：生成配置文件

```bash
cp .env.example .env
```

> 这会把示例配置复制为 `.env`。下面我们用编辑器打开 `.env` 填自己的信息。

#### 第 3 步：填配置

用记事本 / 文本编辑器打开 `.env`，只需要改这几行：

```ini
# 你的设备局域网 IP（例如 192.168.1.100；不知道怎么查，见下方小贴士）
HTTPS_ACCESS_HOST=192.168.1.100

# 登录用户名（随便取，如 admin）
DSH_AUTH_USERNAME=admin

# 登录密码（至少 12 位，请设置独立强密码）
DSH_AUTH_PASSWORD=请改成你的强密码

# DeepSeek 的 API Key（必填）
DEEPSEEK_API_KEY=sk-你的密钥

# 数据保存目录（改成你设备上的真实路径）
DSH_DATA_PATH=/volume1/docker/deepseek-harness/data
WORKSPACE_PATH=/volume1/docker/deepseek-harness/workspace
```

> **小贴士：怎么查局域网 IP？** 在设备上打开终端，Linux 输 `ip addr`、Windows 输 `ipconfig`，找 `192.168.x.x` 那一行（很多设备也显示为 `192.168.1.x`）。

#### 第 4 步：启动

```bash
docker compose up -d
```

第一次会下载镜像，等 1～3 分钟。看到容器启动成功即可。

#### 第 5 步：访问

浏览器打开：**`https://你的局域网IP:8443`**（例如 `https://192.168.1.100:8443`）

- 第一次会提示「证书不受信任」——**这是正常的**（设备自签名证书）。点「高级 → 继续前往你的IP」即可。
- 用你在 `.env` 里设置的账号密码登录。
- 进入后就可以开始用了。

### 方式二：NAS 图形界面（群晖 / 威联通）

如果你是在群晖（Container Manager）或威联通（Container Station）上，可以**全程点点点**：

1. 按方式一第 1 步下载项目文件，解压得到 `docker-compose.yml` 和 `.env.example`。
2. 把 `.env.example` 复制一份改名为 `.env`，按上面的说明填写内容。
3. 打开群晖 **Container Manager → 项目 → 新增**，或威联通 **Container Station → 应用程序 → 创建**，选择「导入」，选项目目录里的 `docker-compose.yml`。
4. 点「应用 / 创建」，等它启动。
5. 浏览器打开 `https://局域网IP:8443` 使用（同上）。

> 不同机型菜单名称略有不同；找不到就在容器平台的「项目 / 应用程序」里找「导入 Compose / 导入 YAML」，选 `docker-compose.yml` 即可。

## 首次使用

### 登录账号

第一次打开网页，如果之前没在 `.env` 填用户名密码，页面会显示「首次设置」。填写：

- 用户名
- 密码（至少 12 位）

保存后自动启用登录保护，之后每次都用它登录。

### 配置模型 API Key

**如果你已经按上面的方式在 `.env` 里填了 `DEEPSEEK_API_KEY`，这一步已经完成，直接跳过。**

如果你是从局域网 IP（比如 `https://192.168.1.100:8443`）访问网页，可能会看到设置页提示：

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

## 局域网访问

在局域网内，浏览器访问 `https://你的局域网IP:8443` 即可（和上面「访问」一样）。

## 公网访问

想在外面（不在家里）也能访问？需要**一个公网域名**和 Cloudflare 账号，用 Cloudflare Tunnel 做免费内网穿透。步骤稍多，放在[附录](#公网访问)里，新手可先跳过。

## 更新与关闭

### 更新到新版本

```bash
docker compose pull
docker compose up -d
```

### 停止 / 关闭

```bash
docker compose down
```

### 数据会丢吗？

不会。账号密码和配置都保存在你填的 `DSH_DATA_PATH` 目录里，升级、重启、重建都保留。

## 常见问题

### 1. 打开显示「证书不受信任」？

正常。这是设备自签名的加密证书。点「高级 → 继续前往你的IP/域名」即可。

### 2. 页面空白或 502？

- 确认你在**局域网内**（或已连 VPN）访问 `https://局域网IP:8443`。
- 确认 `.env` 里的 `HTTPS_ACCESS_HOST` 填的就是这个 IP。

### 3. 设置页提示 settings are unavailable in this browser？

官方限制：设置页只能本机打开。按[首次使用](#首次使用)的方式，在 `.env` 里填 `DEEPSEEK_API_KEY` 即可，不用进设置页。

### 4. 网页一直没有反应 / 很慢？

先看日志（在终端运行 `docker logs -f deepseek-harness`），正常应出现 `dsh web: http://127.0.0.1:3080`。如果这条没出现，稍等片刻或重启容器。

### 5. API Key 填了还是不能用？

- 检查 `DEEPSEEK_API_KEY` 是否以 `sk-` 开头、复制是否完整。
- 检查 DeepSeek 账户是否已充值（按量计费）。
- 确认 `.env` 保存后执行过 `docker compose up -d` 重启。

### 6. 换了 DeepSeek 之外的模型？

在 `.env` 里补上对应 Key（如 `OPENAI_API_KEY=...`）并重启。

## 环境变量速查

| 变量 | 必填 | 说明 |
| --- | --- | --- |
| `HTTPS_ACCESS_HOST` | 是 | 设备局域网 IP 或公网域名（纯域名，不带协议和端口） |
| `DEEPSEEK_API_KEY` | 否 | DeepSeek 的 API Key；填了即可直接用，无需进设置页 |
| `DSH_AUTH_USERNAME` | 否 | 登录用户名（留空则首次访问时在网页上设置） |
| `DSH_AUTH_PASSWORD` | 否 | 登录密码（留空则首次访问时在网页上设置，至少 12 位） |
| `DSH_TELEMETRY_DISABLED` | 否 | 设为 `1` 关闭遥测上报 |
| `DSH_SETUP_PORT` | 否 | 回环设置代理端口（如 `18080`）；留空=关闭，用于本机打开设置页 |
| `GH_PROXY` | 否 | 容器内 git 下载 GitHub 的代理前缀（默认已内置国内加速，设为空可关闭） |
| `NPM_REGISTRY` | 否 | 覆盖容器内 npm 镜像源（默认已内置 npmmirror） |

## 设置页本机打开配置 API Key

> **适用范围**：你确实想用 DSH 网页设置页（添加/更换模型、API Key），或网页提示 `settings are unavailable` 时。

**为什么设置页打不开**：DeepSeek Harness 官方规定 DSH web 只能绑定 `127.0.0.1`，且设置/凭据等接口只在浏览器以**本机地址**（`127.0.0.1` / `localhost` / `[::1]`）打开时才开放（防止远程读取密钥）。所以我们从局域网 IP 访问时，设置页不开放。

**解决办法**：本镜像内置一个「回环设置代理」，开辟一条只在本机可用的通道。你需要会用一点 SSH，步骤如下：

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

6. 配好后关闭 SSH 隧道窗口即可。之后正常用 `https://设备IP:8443` 对话即可（远程下设置页仍保持关闭，属官方行为）。

> ⚠️ 安全：这个端口在 docker 里已经固定只绑定宿主机 `127.0.0.1`，请**不要**把它改成 `0.0.0.0` 或映射到公网，否则等于绕过 DSH 的回环安全限制。

## 公网访问

无公网 IP 或不想开放端口时，推荐用 Cloudflare Tunnel 免费内网穿透。

**前置条件**：一个托管在 Cloudflare 的域名。

### 1. 加一个 cloudflared 容器

在项目的 `docker-compose.yml` 里，`services:` 下追加：

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

把 `.env` 里的 `HTTPS_ACCESS_HOST` 改成你的域名（纯域名，不带协议端口）：

```ini
HTTPS_ACCESS_HOST=harness.yourdomain.com
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

**注意**：`HTTPS_ACCESS_HOST` 改成域名后，局域网 IP 直接访问可能会白屏（正常）。要局域网和公网同时可用，保持 `HTTPS_ACCESS_HOST` 为局域网 IP，并在隧道面板把 Host header 覆盖为这个 IP 的值。

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

### 拉取镜像

已发布到 GitHub 容器仓库，任选其一：

- 大陆推荐（南大镜像加速）：`docker pull ghcr.nju.edu.cn/wljaboy/deepseek-harness-nas:latest`
- GitHub 直连：`docker pull ghcr.io/wljaboy/deepseek-harness-nas:latest`

### 数据保存目录

- `${DSH_DATA_PATH}/data`：认证配置（`.dsh-auth.json`）与 DSH 数据
- `${WORKSPACE_PATH}`：工作区

### 许可证与免责

- **上游许可证**：本镜像基于 `deepseek-harness`（MIT License，Copyright (c) 2026 DeepSeek）按 MIT 条款再分发；Caddy 按 Apache-2.0；Node.js 按 MIT/BSD。
- **本仓库原创代码**（入口脚本、Caddyfile、构建脚本、文档）版权归作者所有，许可见 LICENSE 文件。
- **商标声明**：「DeepSeek」为深度求索公司商标，本镜像为**独立社区项目**，与官方无隶属/合作/背书关系，不使用官方 Logo。
- 使用本镜像即表示同意遵守上述开源许可证；调用模型服务产生的费用与合规问题由最终用户自行承担。
- 作者不对因使用本镜像造成的任何直接或间接损失负责。
