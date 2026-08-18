#!/bin/sh
# DeepSeek Harness NAS 入口脚本（本仓库原创实现）
#
# 认证配置优先级：
#   1. 持久化配置 /data/dsh/.dsh-auth.json（重启后自动沿用）
#   2. 环境变量 DSH_AUTH_USERNAME + DSH_AUTH_PASSWORD（向后兼容）
#   3. 首次部署模式：网页设置页（用户浏览器中设置，保存后自动启用登录）
#
# 功能：
#   - 可选启用 GitHub 代理 / npm 镜像源（容器内下载加速）
#   - 并行启动 dsh web（127.0.0.1:3080）与 Caddy（HTTPS 8443）
#   - 任一进程退出时自动终止另一进程

set -eu

# ---------- 必需环境变量 ----------
: "${HTTPS_ACCESS_HOST:?需要设置 HTTPS_ACCESS_HOST（访问域名或局域网 IP）}"

# ---------- 认证配置解析 ----------
AUTH_FILE="/data/dsh/.dsh-auth.json"
CADDY_CONFIG="/etc/caddy/Caddyfile"
SETUP_PID=""

if [ -f "${AUTH_FILE}" ]; then
  # 模式 1：已有持久化配置（重启后自动沿用）
  export DSH_AUTH_USERNAME=$(sed -n 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${AUTH_FILE}" | head -1)
  export DSH_AUTH_PASSWORD_HASH=$(sed -n 's/.*"hash"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${AUTH_FILE}" | head -1)
  if [ -z "${DSH_AUTH_PASSWORD_HASH}" ]; then
    echo "[entrypoint] 错误：认证配置文件无效" >&2
    exit 1
  fi
  echo "[entrypoint] 已读取持久化认证配置（用户: ${DSH_AUTH_USERNAME}）"

elif [ -n "${DSH_AUTH_USERNAME:-}" ] && [ -n "${DSH_AUTH_PASSWORD:-}" ]; then
  # 模式 2：环境变量提供（向后兼容），生成哈希并持久化
  if [ "${#DSH_AUTH_PASSWORD}" -lt 12 ]; then
    echo "[entrypoint] 错误：DSH_AUTH_PASSWORD 至少需要 12 个字符" >&2
    exit 1
  fi
  DSH_AUTH_PASSWORD_HASH="$(caddy hash-password --plaintext "${DSH_AUTH_PASSWORD}")"
  printf '{"username":"%s","hash":"%s"}\n' "${DSH_AUTH_USERNAME}" "${DSH_AUTH_PASSWORD_HASH}" > "${AUTH_FILE}"
  export DSH_AUTH_PASSWORD_HASH
  echo "[entrypoint] 已根据环境变量生成认证配置并持久化"

else
  # 模式 3：首次部署，网页设置
  echo "[entrypoint] 首次部署：请在浏览器打开 https://${HTTPS_ACCESS_HOST}:8443 设置登录账号"
  node /usr/local/bin/dsh-setup-server.js &
  SETUP_PID=$!
  CADDY_CONFIG="/etc/caddy/Caddyfile.setup"
  export DSH_AUTH_PASSWORD_HASH=""
  export DSH_AUTH_USERNAME=""
fi

# ---------- 可选加速配置 ----------
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

# ---------- 启动服务 ----------
dsh web &
dsh_pid=$!

caddy run --config "${CADDY_CONFIG}" --adapter caddyfile &
caddy_pid=$!

# ---------- 首次设置：等待用户完成并切换到正常模式 ----------
if [ -n "${SETUP_PID}" ]; then
  echo "[entrypoint] 等待用户在网页完成首次设置..."
  while [ ! -f "${AUTH_FILE}" ]; do
    sleep 2
  done
  echo "[entrypoint] 认证配置已保存，切换到正常模式..."
  # 读取新配置
  export DSH_AUTH_USERNAME=$(sed -n 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${AUTH_FILE}" | head -1)
  export DSH_AUTH_PASSWORD_HASH=$(sed -n 's/.*"hash"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${AUTH_FILE}" | head -1)
  # 重启 caddy 启用登录保护
  kill "${caddy_pid}" 2>/dev/null || true
  wait "${caddy_pid}" 2>/dev/null || true
  caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
  caddy_pid=$!
  # 停止设置服务
  kill "${SETUP_PID}" 2>/dev/null || true
  echo "[entrypoint] 登录保护已启用（用户: ${DSH_AUTH_USERNAME}），刷新页面即可登录"
fi

# ---------- 退出清理 ----------
cleanup() {
  kill "${dsh_pid}" "${caddy_pid}" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

# ---------- 等待任一进程退出 ----------
while kill -0 "${dsh_pid}" 2>/dev/null && kill -0 "${caddy_pid}" 2>/dev/null; do
  sleep 2
done

if ! kill -0 "${dsh_pid}" 2>/dev/null; then
  wait "${dsh_pid}"
else
  wait "${caddy_pid}"
fi
