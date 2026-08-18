#!/bin/sh
set -eu

: "${DSH_AUTH_USERNAME:?DSH_AUTH_USERNAME is required}"
: "${DSH_AUTH_PASSWORD:?DSH_AUTH_PASSWORD is required}"
: "${HTTPS_ACCESS_HOST:?HTTPS_ACCESS_HOST is required}"

if [ "${#DSH_AUTH_PASSWORD}" -lt 12 ]; then
  echo "DSH_AUTH_PASSWORD must contain at least 12 characters" >&2
  exit 1
fi

# 可选：容器内 git clone GitHub 加速（设置 GH_PROXY 即启用）
if [ -n "${GH_PROXY:-}" ]; then
  git config --system url."${GH_PROXY}https://github.com/".insteadOf "https://github.com/" 2>/dev/null || true
  echo "[dsh-entrypoint] GitHub 加速已启用: ${GH_PROXY}"
fi

# 可选：容器内 npm 全局镜像源（默认已内置 npmmirror，可通过 NPM_REGISTRY 覆盖）
if [ -n "${NPM_REGISTRY:-}" ]; then
  npm config set registry "${NPM_REGISTRY}" --location=global 2>/dev/null || true
fi

DSH_AUTH_PASSWORD_HASH="$(caddy hash-password --plaintext "$DSH_AUTH_PASSWORD")"
export DSH_AUTH_PASSWORD_HASH

dsh web &
dsh_pid=$!

caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
caddy_pid=$!

terminate() {
  kill "$dsh_pid" "$caddy_pid" 2>/dev/null || true
}

trap terminate INT TERM EXIT

while kill -0 "$dsh_pid" 2>/dev/null && kill -0 "$caddy_pid" 2>/dev/null; do
  sleep 2
done

if ! kill -0 "$dsh_pid" 2>/dev/null; then
  wait "$dsh_pid"
else
  wait "$caddy_pid"
fi
