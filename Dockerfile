# ============================================================
# DeepSeek Harness NAS —— 中国大陆网络加速版
# 全部组件来自官方渠道：DSH = 官方 npm 包 @deepseek-ai/dsh，Node = 官方 node:22-bookworm，
# Caddy = 官方 GitHub Release（sha512/256 双重校验）。部署壳（HTTPS+登录）为本仓库原创。
# 内置国内镜像加速，部署后无需额外配置。
#
# 官方项目: https://github.com/deepseek-ai/deepseek-harness（发布为 npm 包 @deepseek-ai/dsh）
# 本镜像额外提供:
#   - apt 国内镜像源 + 下载重试策略（解决 apt 中断/龟速）
#   - npm 国内镜像源（registry.npmmirror.com）
#   - pip 国内镜像源（清华 PyPI）
#   - git clone GitHub 加速（可选，通过 GH_PROXY 环境变量开启）
#   - 构建产物直接 docker load 使用，无需访问 Docker Hub
# ============================================================

# ---- 构建参数（构建时可用 --build-arg 覆盖）----
# DSH 版本号，官方发布新版后改这里即可同步更新
ARG DSH_VERSION=0.1.0-rc.7
# 基础镜像（国内构建时 build.sh 会自动换成可用镜像源）
ARG NODE_IMAGE=node:22-bookworm
# apt 镜像源（国内构建时 build.sh 默认传清华源；海外构建保持官方源）
ARG APT_MIRROR=deb.debian.org
# npm 镜像源（国内构建时 build.sh 默认传 npmmirror）
ARG NPM_REGISTRY=https://registry.npmjs.org
# pip 镜像源
ARG PIP_MIRROR=https://pypi.tuna.tsinghua.edu.cn/simple
# GitHub 代理前缀（构建期 git 加速，默认空=不启用）
ARG GH_PROXY=

FROM ${NODE_IMAGE}

ARG DSH_VERSION
ARG APT_MIRROR
ARG NPM_REGISTRY
ARG PIP_MIRROR
ARG GH_PROXY

# ---- 环境变量（运行时也生效，容器内所有下载自动走国内源）----
ENV HOME=/data/dsh \
    DSH_HOME=/data/dsh \
    DSH_TELEMETRY_DISABLED=1 \
    NPM_CONFIG_REGISTRY=${NPM_REGISTRY} \
    PIP_INDEX_URL=${PIP_MIRROR} \
    PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn

# ---- 1. apt 国内镜像源 + 重试策略（解决 apt 下载中断/龟速）----
RUN set -eux; \
    if [ "${APT_MIRROR}" != "deb.debian.org" ]; then \
      sed -i "s|http://deb.debian.org|http://${APT_MIRROR}|g" /etc/apt/sources.list.d/debian.sources; \
    fi; \
    # 下载中断自动重试 5 次，超时 60 秒
    printf 'Acquire::Retries "5";\nAcquire::http::Timeout "60";\nAcquire::https::Timeout "60";\n' \
      > /etc/apt/apt.conf.d/99-china-mirror; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates git python3 make g++; \
    rm -rf /var/lib/apt/lists/*

# ---- 2. npm 全局配置（构建期与运行期均走国内源，npx 临时安装也加速）----
RUN npm config set registry "${NPM_REGISTRY}" --location=global; \
    npm config set fetch-retries 5 --location=global; \
    npm config set fetch-retry-mintimeout 20000 --location=global; \
    npm config set fetch-retry-maxtimeout 120000 --location=global

# ---- 3. 构建期 git clone GitHub 加速（可选）----
RUN if [ -n "${GH_PROXY}" ]; then \
      git config --system url."${GH_PROXY}https://github.com/".insteadOf "https://github.com/"; \
    fi

# ---- 4. 安装 DeepSeek Harness（从国内 npm 镜像，速度快且不会中断）----
RUN npm install --global --no-audit --no-fund "@deepseek-ai/dsh@${DSH_VERSION}" \
    && dsh --help >/dev/null

# ---- 5. Caddy 反向代理（HTTPS + 登录保护）----
# 优先使用构建上下文 docker/caddy/caddy（官方 2.10.2 静态二进制，由 build.sh 自动提取）
# 若不存在则使用 apt 源安装的 caddy
COPY docker/caddy/caddy /usr/local/bin/caddy
RUN chmod +x /usr/local/bin/caddy && /usr/local/bin/caddy version

# ---- 6. 配置文件与入口脚本 ----
COPY docker/caddy/Caddyfile /etc/caddy/Caddyfile
COPY docker/caddy/Caddyfile.setup /etc/caddy/Caddyfile.setup
COPY docker/entrypoint/entrypoint.sh /usr/local/bin/dsh-entrypoint
COPY docker/entrypoint/dsh-setup-server.js /usr/local/bin/dsh-setup-server.js
RUN sed -i 's/\r$//' /usr/local/bin/dsh-entrypoint \
    && chmod 0755 /usr/local/bin/dsh-entrypoint \
    && mkdir -p /data/dsh /workspace

EXPOSE 8443
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/dsh-entrypoint"]
