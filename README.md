# DeepSeek Harness Docker 镜像（中国大陆网络加速版）

> **非官方项目**：本镜像为社区独立构建，与 DeepSeek（深度求索）官方无隶属、合作或背书关系。镜像内所有组件均来自官方发布渠道，部署壳为本仓库原创实现。

将官方 **DeepSeek Harness** 打包为 x86_64 NAS 可用的 Docker 镜像，内置中国大陆网络加速，部署后无需任何额外配置。

## 目录

- [特性](#特性)
- [镜像组成与许可证](#镜像组成与许可证)
- [拉取镜像](#拉取镜像)
- [快速开始](#快速开始)
- [公网访问（Cloudflare Tunnel）](#公网访问cloudflare-tunnel)
- [环境变量说明](#环境变量说明)
- [数据持久化](#数据持久化)
- [安全建议](#安全建议)
- [升级与维护](#升级与维护)
- [一键本地构建](#一键本地构建可选)
- [常见问题](#常见问题)
- [许可证与免责声明](#许可证与免责声明)

## 特性

- **100% 官方组件**：DeepSeek Harness 官方 npm 包、官方 Node.js 22、官方 Caddy 二进制（SHA-512/256 双重校验）
- **开箱即用**：HTTPS（自签名证书）+ 登录保护 + 数据持久化，零配置
- **国内加速**：apt / npm / pip 源已内置，下载重试策略已内置
- **两种访问方式**：局域网直接访问；公网通过 Cloudflare Tunnel 内网穿透
- **认证持久化**：账号密码保存于数据目录，重启自动沿用

## 镜像组成与许可证

| 组件 | 来源 | 许可证 |
| --- | --- | --- |
| DeepSeek Harness | 官方 npm 包 `@deepseek-ai/dsh`（[deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)） | MIT |
| Node.js 22 | 官方 `node:22-bookworm` 镜像 | MIT / BSD |
| Caddy | 官方 GitHub Release（官方 checksums 双重校验） | Apache-2.0 |
| 部署壳（HTTPS/登录/持久化） | 本仓库原创实现 | 见[许可证与免责声明](#许可证与免责声明) |

> 上游 deepseek-harness 采用 MIT 许可证（Copyright (c) 2026 DeepSeek），明确允许免费再分发、修改与商用，仅需保留版权声明。本镜像即按该许可条款进行再分发。

## 拉取镜像

镜像已发布到 GitHub 容器仓库（ghcr.io），两种拉取方式任选其一：

### 中国大陆推荐（南大镜像加速，实测 5MB/s）

```bash
docker pull ghcr.nju.edu.cn/wljaboy/deepseek-harness-nas:latest
```

### GitHub 直连

```bash
docker pull ghcr.io/wljaboy/deepseek-harness-nas:latest
```

## 快速开始

### 1. 创建部署目录

```bash
mkdir -p /volume1/docker/deepseek-harness
cd /volume1/docker/deepseek-harness
```

### 2. 创建 docker-compose.yml

```yaml
services:
  deepseek-harness:
    image: ghcr.nju.edu.cn/wljaboy/deepseek-harness-nas:latest
    container_name: deepseek-harness
    restart: unless-stopped
    shm_size: 1gb
    ports:
      - "8443:8443"
    environment:
      HTTPS_ACCESS_HOST: "${HTTPS_ACCESS_HOST}"
      DSH_AUTH_USERNAME: "${DSH_AUTH_USERNAME}"
      DSH_AUTH_PASSWORD: "${DSH_AUTH_PASSWORD}"
      DSH_TELEMETRY_DISABLED: "1"
    volumes:
      - "${DSH_DATA_PATH}:/data/dsh"
      - "${WORKSPACE_PATH}:/workspace"
```

> 使用 GitHub 直连拉取的用户，把 `image` 换成 `ghcr.io/wljaboy/deepseek-harness-nas:latest` 即可。
> 端口可自定义：例如改为 `8773:8443`，局域网访问地址随之变为 `https://NAS局域网IP:8773`。

### 3. 创建 .env 环境变量文件

```bash
cat > .env << 'EOF'
# 你的 NAS 局域网 IP（如 192.168.1.111），或公网域名（纯域名，不带协议和端口）
HTTPS_ACCESS_HOST=192.168.1.111

# 登录用户名和密码（可选：不设置则首次访问时在网页上自行设置）
# DSH_AUTH_USERNAME=admin
# DSH_AUTH_PASSWORD=请修改为至少12位的强密码

# 持久化目录（改为你 NAS 上的实际绝对路径）
DSH_DATA_PATH=/volume1/docker/deepseek-harness/data
WORKSPACE_PATH=/volume1/docker/deepseek-harness/workspace
EOF
```

### 4. 启动

```bash
docker compose up -d
```

### 5. 访问

浏览器打开：`https://NAS局域网IP:8443`

- 首次访问会提示自签名证书不受信任，选择继续访问即可
- **首次部署**：若未在 .env 中设置用户名密码，页面会显示「首次设置」，填写用户名和至少 12 位的密码后自动启用登录保护
- 已设置后：使用设置的账号密码登录
- 查看日志：`docker logs -f deepseek-harness`，正常应出现 `dsh web: http://127.0.0.1:3080`

## 公网访问（Cloudflare Tunnel）

NAS 无公网 IP 或不想开放端口时，推荐用 Cloudflare Tunnel 做免费内网穿透。

**前置条件**：一个托管在 Cloudflare 的域名。

### 1. 运行 cloudflared 容器

在 deepseek-harness 的 compose 文件中追加（token 方式，隧道在 Cloudflare 面板创建），并确保与 deepseek-harness 处于同一 Docker 网络：

```yaml
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    command: tunnel --no-autoupdate run --token <你的隧道Token>
    networks:
      - default
```

### 2. 修改 .env

```bash
HTTPS_ACCESS_HOST=harness.yourdomain.com   # 改为你的域名，纯域名，不带协议和端口
```

### 3. 重启

```bash
docker compose up -d
```

### 4. Cloudflare 面板配置

Zero Trust → Networks → Tunnels → 你的隧道 → Public Hostname → Add a public hostname：

| 配置项 | 值 |
| --- | --- |
| Subdomain / Domain | 例如 `harness` / `yourdomain.com` |
| Service Type | **HTTPS** |
| URL | **局域网访问地址**，如 `https://192.168.1.123:8443`（端口写你实际映射的端口） |
| No TLS Verify | **开启**（容器内为自签名证书） |

### 5. 访问

浏览器打开 `https://harness.yourdomain.com`，证书由 Cloudflare 边缘提供，无自签名警告。

### 原理与注意事项

- 容器内 Caddy 只监听 `HTTPS_ACCESS_HOST` 这一个站点，公网请求的 Host 必须与之一致，否则返回空白页
- URL 填写**局域网 IP 而非容器服务名**：IP 字面量不触发 SNI，Caddy 通过 `default_sni` 回退完成握手
- 必须开启 **No TLS Verify**：否则 cloudflared 会因自签名证书拒绝连接（502）
- HTTPS_ACCESS_HOST 改为域名后，局域网 IP 直接访问会白屏（属正常现象）；如需两者同时可用，见[常见问题](#常见问题)

## 环境变量说明

| 变量 | 必填 | 说明 |
| --- | --- | --- |
| HTTPS_ACCESS_HOST | 是 | NAS 局域网 IP 或公网域名（纯域名，不带协议/端口） |
| DSH_AUTH_USERNAME | 否 | 登录用户名（留空则首次访问时在网页上设置） |
| DSH_AUTH_PASSWORD | 否 | 登录密码（留空则首次访问时在网页上设置，**至少 12 字符**） |
| DSH_TELEMETRY_DISABLED | 否 | 设为 1 关闭遥测 |
| GH_PROXY | 否 | 容器内 git clone 的 GitHub 代理前缀，如 `https://ghfast.top/` |
| NPM_REGISTRY | 否 | 覆盖容器内 npm 镜像源（默认已内置 npmmirror） |

## 数据持久化

- `${DSH_DATA_PATH}:/data/dsh`：认证配置（`.dsh-auth.json`）与 DSH 数据
- `${WORKSPACE_PATH}:/workspace`：工作区

升级、重建、迁移容器均不会丢失认证与数据。

## 安全建议

- 首次部署务必设置 ≥12 位强密码
- 不要把容器内部端口（如 3080）映射到公网
- 公网访问优先使用 Cloudflare Tunnel；可选在 Cloudflare Access 中为域名添加二次认证
- 保持镜像更新（见下）

## 升级与维护

```bash
docker pull ghcr.nju.edu.cn/wljaboy/deepseek-harness-nas:latest
docker compose up -d
```

## 一键本地构建（可选）

适合离线环境或自定义版本：

```bash
git clone https://github.com/wljaboy/deepseek-harness-docker.git
cd deepseek-harness-docker
./scripts/build.sh --save   # 构建并导出 tar.gz

docker load -i deepseek-harness-nas-0.1.0-rc.7-cn.tar.gz
docker compose up -d        # compose 中 image 改为本地 tag
```

## 常见问题

### docker pull 提示镜像不存在（manifest unknown）？

说明 GitHub Actions 尚未构建推送，请稍后再试；或使用 `./scripts/build.sh --save` 本地构建。

### 页面空白 / 502 Bad Gateway？

- 页面空白：请求的 Host 与 HTTPS_ACCESS_HOST 不一致，检查反代/回源 Host 配置
- 502：DSH web 未监听 3080，查看日志应出现 `dsh web: http://127.0.0.1:3080`

### 公网通过隧道打不开 / 502？

- 确认面板 URL 填的是**局域网访问地址**，且端口与实际映射一致
- 确认 **No TLS Verify** 已开启
- 确认 `HTTPS_ACCESS_HOST` 与访问域名一致（访问域名、Caddy 站点、Host 三者需匹配）

### 局域网 IP 直接访问白屏？

HTTPS_ACCESS_HOST 为域名时属正常现象（Caddy 只认该域名站点）。若需局域网 IP 与公网域名同时可用：保持 HTTPS_ACCESS_HOST 为局域网 IP，并在隧道面板的 HTTP 设置中将 Host header 覆盖为 `HTTPS_ACCESS_HOST` 的值。

### 镜像里装的软件还需要手动配置国内源吗？

不需要。apt 源、npm 源、pip 源、下载重试策略全部已内置，容器内直接使用即走国内加速。

### 为什么用完整版 node:22-bookworm 而不是 slim？

DSH 插件可能需要编译原生模块（node-gyp），完整版自带编译工具链。

## 许可证与免责声明

- **上游许可证**：本镜像基于 `deepseek-harness`（MIT License，Copyright (c) 2026 DeepSeek）构建并按 MIT 许可条款再分发；Caddy 按 Apache-2.0 再分发；Node.js 按 MIT/BSD 再分发
- **本仓库原创代码**（入口脚本、Caddyfile、构建脚本、文档）版权归作者所有，许可见 LICENSE 文件
- **商标声明**："DeepSeek" 为深度求索公司的商标。本镜像为**独立社区项目**，与 DeepSeek 官方无隶属、合作或背书关系，不使用官方 Logo
- 使用本镜像即表示你同意遵守上述开源许可证；调用模型服务产生的费用与合规问题由最终用户自行承担
- 作者不对因使用本镜像造成的任何直接或间接损失负责
