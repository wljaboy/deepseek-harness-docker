#!/bin/sh
# DeepSeek Harness NAS 入口脚本（本仓库原创实现）
#
# 功能：
#   1. 校验必需环境变量（登录账号、访问域名）
#   2. 可选启用 GitHub 代理 / npm 镜像源（容器内下载加速）
#   3. 生成登录密码的 bcrypt 哈希
#   4. 并行启动 dsh web（127.0.0.1:3080）与 Caddy（HTTPS 8443）
#   5. 任一进程退出时自动终止另一进程

set -eu

# ---------- 1. 必需环境变量 ----------
: "${DSH_AUTH_USERNAME:?需要设置 DSH_AUTH_USERNAME（登录用户名）}"
: "${DSH_AUTH_PASSWORD:?需要设置 DSH_AUTH_PASSWORD（登录密码）}"
: "${HTTPS_ACCESS_HOST:?需要设置 HTTPS_ACCESS_HOST（访问域名或局域网 IP）}"

if [ "${#DSH_AUTH_PASSWORD}" -lt 12 ]; then
  echo "[entrypoint] 错误：DSH_AUTH_PASSWORD 至少需要 12 个字符" >&2
  exit 1
fi

# ---------- 2. 可选加速配置 ----------
# 容器内 git clone GitHub 加速（设置 GH_PROXY 即启用，如 https://ghfast.top/）
if [ -n "${GH_PROXY:-}" ]; then
  git config --system url."${GH_PROXY}https://github.com/".insteadOf "https://github.com/" 2>/dev/null || true
  echo "[entrypoint] GitHub 代理已启用: ${GH_PROXY}"
fi

# 覆盖容器内 npm 镜像源（默认镜像已内置 npmmirror）
if [ -n "${NPM_REGISTRY:-}" ]; then
  npm config set registry "${NPM_REGISTRY}" --location=global 2>/dev/null || true
  echo "[entrypoint] npm 镜像源: ${NPM_REGISTRY}"
fi

# ---------- 3. 登录密码哈希 ----------
DSH_AUTH_PASSWORD_HASH="$(caddy hash-password --plaintext "${DSH_AUTH_PASSWORD}")"
export DSH_AUTH_PASSWORD_HASH

# ---------- 4. 启动服务 ----------
dsh web &
dsh_pid=$!

caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
caddy_pid=$!

# ---------- 5. 退出清理 ----------
cleanup() {
  kill "${dsh_pid}" "${caddy_pid}" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

# ---------- 6. 等待任一进程退出 ----------
while kill -0 "${dsh_pid}" 2>/dev/null && kill -0 "${caddy_pid}" 2>/dev/null; do
  sleep 2
done

if ! kill -0 "${dsh_pid}" 2>/dev/null; then
  wait "${dsh_pid}"
else
  wait "${caddy_pid}"
fi
