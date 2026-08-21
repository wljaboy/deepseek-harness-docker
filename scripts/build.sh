#!/usr/bin/env bash
# ============================================================
# DeepSeek Harness NAS —— 中国大陆一键构建脚本
#
# 用法:
#   ./scripts/build.sh                     # 默认构建 0.1.0-rc.7-cn
#   DSH_VERSION=0.1.0-rc.7 ./scripts/build.sh   # 跟随官方新版本
#   ./scripts/build.sh --save              # 构建后同时导出 .tar.gz 镜像包
#
# 环境变量（均可覆盖）:
#   DSH_VERSION   官方 npm 包版本号（默认：自动检测最新；离线则回退到 .last-built-version 或脚本默认值）
#   IMAGE_NAME    镜像名称（默认 wljaboy/deepseek-harness-nas）
#   TAG           镜像标签（默认 <DSH_VERSION>-cn）
#   APT_MIRROR    apt 镜像源（默认阿里云 mirrors.aliyun.com）
#   NPM_REGISTRY  npm 镜像源（默认 https://registry.npmmirror.com）
#   PIP_MIRROR    pip 镜像源（默认清华 PyPI）
#   GH_PROXY      GitHub 代理前缀（默认 https://ghfast.top/，设为空可关闭）
# ============================================================
set -euo pipefail

# ---------- 参数 ----------
DEFAULT_DSH_VERSION="0.1.0-rc.7"
IMAGE_NAME="${IMAGE_NAME:-wljaboy/deepseek-harness-nas}"
APT_MIRROR="${APT_MIRROR:-mirrors.aliyun.com}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
PIP_MIRROR="${PIP_MIRROR:-https://pypi.tuna.tsinghua.edu.cn/simple}"
GH_PROXY="${GH_PROXY:-https://ghfast.top/}"
SAVE=0
NODE_IMAGE="node:22-bookworm"

# Docker Hub 国内镜像源候选（按顺序尝试）
HUB_MIRRORS=(
  "docker.m.daocloud.io"
  "docker.1ms.run"
  "docker.xuanyuan.me"
  "hub.rat.dev"
)

for arg in "$@"; do
  case "$arg" in
    --save) SAVE=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0 ;;
  esac
done

# ---------- 工具函数 ----------
info()  { echo -e "\033[1;36m[INFO]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
die()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

detect_latest_dsh_version() {
  # 优先官方源，避免镜像同步延迟；同时不依赖 dist-tag=latest（rc 有时不会指向 latest）
  curl -fsSL 'https://registry.npmjs.org/@deepseek-ai/dsh' | python3 - <<'PY'
import json, sys, re

data = json.load(sys.stdin)
versions = list((data.get("versions") or {}).keys())
if not versions:
  raise SystemExit(1)

rx = re.compile(r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$')

def key(v: str):
  m = rx.match(v)
  if not m:
    return (-1, -1, -1, 1, "", -1, v)
  major, minor, patch = map(int, m.group(1, 2, 3))
  pre = m.group(4) or ""
  if not pre:
    return (major, minor, patch, 1, "", 0, v)
  mrc = re.match(r'^(rc)\.(\d+)$', pre)
  if mrc:
    return (major, minor, patch, 0, "rc", int(mrc.group(2)), v)
  return (major, minor, patch, 0, pre, 0, v)

print(max(versions, key=key))
PY
}

resolve_dsh_version() {
  if [ -n "${DSH_VERSION:-}" ]; then
    echo "${DSH_VERSION}"
    return
  fi

  local detected=""
  if detected="$(detect_latest_dsh_version 2>/dev/null)"; then
    echo "${detected}"
    return
  fi

  if [ -f ".last-built-version" ]; then
    cat ".last-built-version"
    return
  fi

  echo "${DEFAULT_DSH_VERSION}"
}

DSH_VERSION="$(resolve_dsh_version)"
TAG="${TAG:-${DSH_VERSION}-cn}"

docker_cmd() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  elif sudo -n docker info >/dev/null 2>&1; then
    sudo docker "$@"
  else
    die "无法访问 Docker。请把当前用户加入 docker 组（sudo usermod -aG docker $USER 后重新登录），或使用有权限的账号执行。"
  fi
}

# ---------- 1. 准备基础镜像 node:22-bookworm ----------
ensure_base_image() {
  if docker_cmd image inspect "${NODE_IMAGE}" >/dev/null 2>&1; then
    ok "基础镜像 ${NODE_IMAGE} 已存在，直接使用"
    return
  fi
  info "拉取基础镜像 ${NODE_IMAGE}（自动尝试国内镜像源）..."
  for M in "${HUB_MIRRORS[@]}"; do
    info "  尝试 ${M} ..."
    if docker_cmd pull "${M}/library/node:22-bookworm"; then
      docker_cmd tag "${M}/library/node:22-bookworm" "${NODE_IMAGE}"
      ok "基础镜像就绪（来源: ${M}）"
      return
    fi
    warn "  ${M} 拉取失败，尝试下一个镜像源..."
  done
  die "所有国内镜像源均无法拉取基础镜像，请检查网络后重试。"
}

# ---------- 2. 准备 caddy 二进制（官方渠道下载 + sha256 校验） ----------
ensure_caddy() {
  local EXPECT="${CADDY_SHA256:-4ef1f68c70219536b2711fd16547a79841a2dec2d6b4e56b1e3e5e9da76028e6}"
  if [ -x "docker/caddy/caddy" ] && [ "$(sha256sum docker/caddy/caddy | awk '{print $1}')" = "$EXPECT" ]; then
    ok "caddy 二进制已存在且校验通过: docker/caddy/caddy"
    return
  fi
  info "从官方渠道下载 caddy 二进制（caddyserver.com + sha256 校验）..."
  bash scripts/fetch-caddy.sh
  ok "caddy 就绪: $(./docker/caddy/caddy version | head -1)"
}

# ---------- 3. 构建 ----------
build() {
  local build_args=(
    --build-arg "DSH_VERSION=${DSH_VERSION}"
    --build-arg "APT_MIRROR=${APT_MIRROR}"
    --build-arg "NPM_REGISTRY=${NPM_REGISTRY}"
    --build-arg "PIP_MIRROR=${PIP_MIRROR}"
    --build-arg "GH_PROXY=${GH_PROXY}"
  )
  info "构建镜像 ${IMAGE_NAME}:${TAG} (DSH ${DSH_VERSION}) ..."
  # SOURCE_DATE_EPOCH: 整秒时间戳，兼容旧版 Docker/Dockerman 显示
  SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date +%s)}" docker_cmd build -t "${IMAGE_NAME}:${TAG}" "${build_args[@]}" .
  docker_cmd tag "${IMAGE_NAME}:${TAG}" "${IMAGE_NAME}:latest-cn" 2>/dev/null || true
  ok "构建完成: ${IMAGE_NAME}:${TAG}"
}

# ---------- 4. 导出（可选） ----------
save_image() {
  local out="deepseek-harness-nas-${TAG}.tar.gz"
  info "导出镜像包 ${out}（可直接拷贝到 NAS 上 docker load 使用）..."
  docker_cmd save "${IMAGE_NAME}:${TAG}" | gzip -9 > "${out}"
  ok "导出完成: ${out}"
  echo
  echo "  在 NAS 上导入:"
  echo "    docker load -i ${out}"
  echo "  启动:"
  echo "    docker compose up -d   （或按 README 配置后 docker run）"
}

# ---------- 主流程 ----------
ensure_base_image
ensure_caddy
build
[ "${SAVE}" = "1" ] && save_image

echo
ok "全部完成！"
echo "  镜像: ${IMAGE_NAME}:${TAG}"
echo "  使用: 参考 README.md 配置 .env 后 docker compose up -d"
echo "  更新: 官方发布新版后，执行 DSH_VERSION=<新版本号> ./scripts/build.sh --save"
