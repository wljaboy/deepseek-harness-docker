#!/usr/bin/env bash
# ============================================================
# 获取 Caddy 二进制（官方 GitHub Release + 官方 checksums.txt 双重校验）
#
# 原理:
#   1. 通过国内代理(gh-proxy.com)下载官方发布物（官方站直连仅 ~26KB/s）
#   2. 下载官方 caddy_<版本>_checksums.txt，用其中的 SHA-512 校验 tar.gz
#   3. 解压后二进制再与期望 SHA-256 比对（双保险）
#
# 用法: ./scripts/fetch-caddy.sh
# 环境变量:
#   CADDY_VERSION  版本（默认 v2.10.2）
#   GH_PROXY       代理前缀（默认 https://gh-proxy.com/，可换 ghfast.top 等）
#   CADDY_BIN_SHA256  解压后二进制的期望 SHA-256（默认官方核对值）
# ============================================================
set -euo pipefail

CADDY_VERSION="${CADDY_VERSION:-v2.10.2}"
VER="${CADDY_VERSION#v}"
GH_PROXY="${GH_PROXY:-https://gh-proxy.com/}"
CADDY_BIN_SHA256="${CADDY_BIN_SHA256:-4ef1f68c70219536b2711fd16547a79841a2dec2d6b4e56b1e3e5e9da76028e6}"
OUT="docker/caddy/caddy"
mkdir -p "$(dirname "$OUT")"

# 已存在且校验通过则复用
if [ -f "$OUT" ]; then
  if [ "$(sha256sum "$OUT" | awk '{print $1}')" = "$CADDY_BIN_SHA256" ]; then
    echo "[OK] caddy 已存在且校验通过，复用"
    chmod +x "$OUT"
    exit 0
  fi
  echo "[WARN] 现有 caddy 校验不通过，重新获取"
  rm -f "$OUT"
fi

BASE="${GH_PROXY}https://github.com/caddyserver/caddy/releases/download/${CADDY_VERSION}"
TARBALL="caddy_${VER}_linux_amd64.tar.gz"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

echo "[INFO] 获取 Caddy ${CADDY_VERSION} linux/amd64（代理: ${GH_PROXY}）..."

# 1. 下载官方 checksums.txt
echo "[INFO] 下载官方 checksums.txt ..."
curl -fsSL --max-time 120 "${BASE}/caddy_${VER}_checksums.txt" -o "$TMPD/checksums.txt" \
  || { echo "[ERROR] checksums.txt 下载失败" >&2; exit 1; }

# 2. 下载官方 tar.gz
echo "[INFO] 下载官方 tar.gz ..."
curl -fsSL --max-time 600 "${BASE}/${TARBALL}" -o "$TMPD/$TARBALL" \
  || { echo "[ERROR] tar.gz 下载失败" >&2; exit 1; }

# 3. 用官方 checksums.txt 的 SHA-512 校验
OFFICIAL_HASH=$(grep "${TARBALL}" "$TMPD/checksums.txt" | awk '{print $1}')
LOCAL_HASH=$(sha512sum "$TMPD/$TARBALL" | awk '{print $1}')
if [ -z "$OFFICIAL_HASH" ] || [ "$OFFICIAL_HASH" != "$LOCAL_HASH" ]; then
  echo "[ERROR] SHA-512 校验失败" >&2
  echo "  官方: $OFFICIAL_HASH" >&2
  echo "  本地: $LOCAL_HASH" >&2
  exit 1
fi
echo "[OK] 官方 SHA-512 校验通过"

# 4. 解压出二进制
tar -xzf "$TMPD/$TARBALL" -C "$TMPD"
BIN="$TMPD/caddy"
[ -f "$BIN" ] || BIN="$TMPD/caddy_linux_amd64"
[ -f "$BIN" ] || { echo "[ERROR] 解压后未找到 caddy 二进制" >&2; exit 1; }

# 5. 二进制 SHA-256 双保险校验
ACTUAL=$(sha256sum "$BIN" | awk '{print $1}')
if [ "$ACTUAL" != "$CADDY_BIN_SHA256" ]; then
  echo "[ERROR] 二进制 SHA-256 校验失败" >&2
  echo "  期望: $CADDY_BIN_SHA256" >&2
  echo "  实际: $ACTUAL" >&2
  exit 1
fi
echo "[OK] 二进制 SHA-256 校验通过"

cp "$BIN" "$OUT"
chmod +x "$OUT"
echo "[OK] caddy 就绪: $(sha256sum "$OUT" | awk '{print $1}')"
"$OUT" version