# DeepSeek Harness NAS Docker 镜像（中国大陆网络加速版）

将官方 **DeepSeek Harness** 打包为 x86_64 NAS 可用的 Docker 镜像。
**全部组件来自官方渠道**，部署壳为本仓库原创实现，内置中国大陆网络加速，部署后无需任何额外配置。

## 镜像组成（100% 官方来源）

| 组件 | 来源 | 说明 |
| --- | --- | --- |
| DeepSeek Harness | 官方 npm 包 @deepseek-ai/dsh | 官方项目 [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) 的正式发布物 |
| Node.js 22 | 官方 node:22-bookworm 镜像 | Docker 官方镜像 |
| Caddy | 官方 GitHub Release 下载 | 以官方 checksums.txt 的 SHA-512 + 二进制 SHA-256 双重校验 |
| 部署壳（HTTPS/登录/持久化） | **本仓库原创实现** | 入口脚本 + Caddyfile，不依赖任何第三方镜像 |

> 官方项目只发布源码和 npm 包，没有官方 Docker 镜像；本镜像的 Docker 部署方案为本仓库自行编写。

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

## Docker Compose 部署

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

> 使用 GitHub 直连拉取的用户，把 image 换成 ghcr.io/wljaboy/deepseek-harness-nas:latest 即可。

### 3. 创建 .env 环境变量文件

```bash
cat > .env << 'EOF'
# 你的 NAS 局域网 IP（如 192.168.1.111），或公网域名（纯域名，不带协议和端口）
HTTPS_ACCESS_HOST=192.168.1.111

# 登录用户名
DSH_AUTH_USERNAME=admin

# 登录密码（必须至少 12 个字符）
DSH_AUTH_PASSWORD=请修改为至少12位的强密码

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
- 使用 .env 中设置的 `DSH_AUTH_USERNAME` 和 `DSH_AUTH_PASSWORD` 登录
- 查看日志：`docker logs -f deepseek-harness`，正常应出现 `dsh web: http://127.0.0.1:3080`

## 环境变量说明

| 变量 | 必填 | 说明 |
| --- | --- | --- |
| HTTPS_ACCESS_HOST | 是 | NAS 局域网 IP 或公网域名（纯域名，不带协议/端口） |
| DSH_AUTH_USERNAME | 是 | 登录用户名 |
| DSH_AUTH_PASSWORD | 是 | 登录密码，**至少 12 字符** |
| DSH_TELEMETRY_DISABLED | 否 | 设为 1 关闭遥测 |
| GH_PROXY | 否 | 容器内 git clone 的 GitHub 代理前缀，如 https://ghfast.top/ |
| NPM_REGISTRY | 否 | 覆盖容器内 npm 镜像源（默认已内置 npmmirror） |

## 一键构建（可选，适合离线环境或自定义版本）

```bash
git clone https://github.com/wljaboy/deepseek-harness-docker.git
cd deepseek-harness-docker
./scripts/build.sh --save   # 构建并导出 tar.gz

docker load -i deepseek-harness-nas-0.1.0-rc.7-cn.tar.gz
docker compose up -d        # compose 中 image 改为本地 tag
```

## 常见问题

### docker pull 提示镜像不存在（manifest unknown）？

说明 GitHub Actions 尚未构建推送，请稍后再试；或使用 ./scripts/build.sh --save 本地构建。

### 页面空白 / 502 Bad Gateway？

- 页面空白：请求的 Host 与 HTTPS_ACCESS_HOST 不一致，检查反代/回源 Host 配置。
- 502：DSH web 未监听 3080，查看日志应出现 dsh web: http://127.0.0.1:3080。

### 镜像里装的软件还需要手动配置国内源吗？

不需要。apt 源、npm 源、pip 源、下载重试策略全部已内置，容器内直接使用即走国内加速。

### 为什么用完整版 node:22-bookworm 而不是 slim？

DSH 插件可能需要编译原生模块（node-gyp），完整版自带编译工具链。
