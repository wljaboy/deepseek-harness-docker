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
SETUP_PROXY_PID=""

if [ -f "${AUTH_FILE}" ]; then
  # 模式 1：已有持久化配置（重启后自动沿用）
  DSH_AUTH_USERNAME="$(sed -n 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${AUTH_FILE}" | head -1)"
  export DSH_AUTH_USERNAME
  DSH_AUTH_PASSWORD_HASH="$(sed -n 's/.*"hash"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${AUTH_FILE}" | head -1)"
  export DSH_AUTH_PASSWORD_HASH
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

# ---------- 公网域名（可选）：让局域网 IP 与公网域名同时可访问 ----------
# HTTPS_ACCESS_HOST 仍是局域网 IP；若你有公网域名（经 Cloudflare Tunnel 等转发到本机），
# 设置 DSH_PUBLIC_HOST 即可让 Caddy 同时接受该域名 Host，局域网与公网都能访问。
# Caddyfile 用 DSH_EXTRA_HOSTS 拼出多 host 站点地址；留空则精确保持单 host（仅局域网 IP）。
DSH_EXTRA_HOSTS=""
if [ -n "${DSH_PUBLIC_HOST:-}" ]; then
  DSH_EXTRA_HOSTS=", https://${DSH_PUBLIC_HOST}:8443"
fi
export DSH_EXTRA_HOSTS

# ---------- 可选加速配置 ----------
# 容器内 git clone GitHub 加速（设置 GH_PROXY 即启用，如 https://ghfast.top/；
# 设为空则移除镜像内烘焙的代理规则，恢复直连——私有仓库 push 不受第三方代理影响）
if [ -n "${GH_PROXY:-}" ]; then
  git config --system url."${GH_PROXY}https://github.com/".insteadOf "https://github.com/" 2>/dev/null || true
  echo "[entrypoint] GitHub 代理已启用: ${GH_PROXY}"
else
  # 清除镜像构建期烘焙的 insteadOf 规则（Dockerfile GH_PROXY 默认值写入的 /etc/gitconfig）
  git config --system --get-regexp '^url\..*\.insteadOf$' 2>/dev/null | while IFS= read -r line; do
    key="${line%% *}"
    git config --system --unset "${key}" 2>/dev/null || true
  done
  echo "[entrypoint] GitHub 代理已关闭（直连 github.com）"
fi

# 覆盖容器内 npm 镜像源（默认镜像已内置 npmmirror）
if [ -n "${NPM_REGISTRY:-}" ]; then
  npm config set registry "${NPM_REGISTRY}" --location=global 2>/dev/null || true
  echo "[entrypoint] npm 镜像源: ${NPM_REGISTRY}"
fi

# ---------- 可选：安装插件市场 dshmarket ----------
# 官方安装命令：dsh plugin --profile web add dshmarket（需要 pnpm，镜像已内置）。
# 默认自动安装一次（写入 /data/dsh 持久目录，用标记文件避免重复），失败不阻塞启动。
# 设置 DSH_INSTALL_MARKET=0 关闭。
MARKET_FLAG="/data/dsh/.dshmarket-installed"
if [ "${DSH_INSTALL_MARKET:-1}" != "0" ] && [ ! -f "${MARKET_FLAG}" ]; then
  echo "[entrypoint] 正在安装插件市场 dshmarket..."
  if dsh plugin --profile web add dshmarket >/tmp/dshmarket-install.log 2>&1; then
    touch "${MARKET_FLAG}"
    echo "[entrypoint] 插件市场 dshmarket 已安装（浏览器打开 设置 → 插件市场 即用）"
  else
    echo "[entrypoint] 插件市场安装失败（不影响启动，详见 /tmp/dshmarket-install.log）"
  fi
fi

# ---------- 启动服务 ----------
dsh web &
dsh_pid=$!

caddy run --config "${CADDY_CONFIG}" --adapter caddyfile &
caddy_pid=$!

# ---------- 可选：回环设置代理 ----------
# DSH web 被官方限制只能绑定 127.0.0.1，且设置页仅在浏览器以回环 hostname 打开时
# 可用（客户端 isLoopback 判定）。设置 DSH_SETUP_PORT（如 18080）后，本代理把容器内
# 0.0.0.0:<port> 透明转发到 127.0.0.1:3080（DSH web）；配合 docker 把该端口仅发布到
# 宿主机回环 127.0.0.1:<port>，再用 SSH 隧道在本机打开 http://127.0.0.1:<port>，
# 浏览器地址栏 hostname 即为回环，设置页（含 API Key）可用。
# 注意：请勿将该端口发布到 0.0.0.0 / 公网，否则等于绕过 DSH 的回环安全约束。
if [ -n "${DSH_SETUP_PORT:-}" ] && [ "${DSH_SETUP_PORT}" != "0" ]; then
  node /usr/local/bin/dsh-loopback-proxy.js &
  SETUP_PROXY_PID=$!
  echo "[entrypoint] 回环设置代理已启动（端口 ${DSH_SETUP_PORT}）"
  echo "[entrypoint]   本机 SSH 隧道: ssh -L ${DSH_SETUP_PORT}:127.0.0.1:${DSH_SETUP_PORT} <你的NAS>"
  echo "[entrypoint]   回环 URL:      http://127.0.0.1:${DSH_SETUP_PORT}"
fi

# ---------- 首次设置：等待用户完成并切换到正常模式 ----------
if [ -n "${SETUP_PID}" ]; then
  echo "[entrypoint] 等待用户在网页完成首次设置..."
  while [ ! -f "${AUTH_FILE}" ]; do
    sleep 2
  done
  echo "[entrypoint] 认证配置已保存，切换到正常模式..."
  # 读取新配置
  DSH_AUTH_USERNAME="$(sed -n 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${AUTH_FILE}" | head -1)"
  export DSH_AUTH_USERNAME
  DSH_AUTH_PASSWORD_HASH="$(sed -n 's/.*"hash"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${AUTH_FILE}" | head -1)"
  export DSH_AUTH_PASSWORD_HASH
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
  [ -n "${SETUP_PROXY_PID}" ] && kill "${SETUP_PROXY_PID}" 2>/dev/null || true
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
