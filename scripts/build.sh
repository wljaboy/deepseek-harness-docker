#!/usr/bin/env bash
# ============================================================
# DeepSeek Harness NAS —— 中国大陆一键构建脚本
#
# 用法:
#   ./scripts/build.sh                     # 默认构建 0.1.0-rc.6-cn
#   DSH_VERSION=0.1.0-rc.7 ./scripts/build.sh   # 跟随官方新版本
#   ./scripts/build.sh --save              # 构建后同时导出 .tar.gz 镜像包
#
# 环境变量（均可覆盖）:
#   DSH_VERSION   官方 npm 包版本号（默认 0.1.0-rc.6）
#   IMAGE_NAME    镜像名称（默认 kanzuori197/deepseek-harness-nas）
#   TAG           镜像标签（默认 <DSH_VERSION>-cn）
#   APT_MIRROR    apt 镜像源（默认清华 mirrors.tuna.tsinghua.edu.cn）
#   NPM_REGISTRY  npm 镜像源（默认 https://registry.npmmirror.com）
#   GH_PROXY      GitHub 代理前缀（可选，如 https://ghfast.top/）
# ============================================================
set -euo pipefail

# ---------- 参数 ----------
DSH_VERSION="${DSH_VERSION:-0.1.0-rc.6}"
IMAGE_NAME="${IMAGE_NAME:-kanzuori197/deepseek-harness-nas}"
TAG="${TAG:-${DSH_VERSION}-cn}"
APT_MIRROR="${APT_MIRROR:-mirrors.tuna.tsinghua.edu.cn}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
GH_PROXY="${GH_PROXY:-}"
SAVE=0
NODE_IMAGE="node:22-bookworm"

# Docker Hub 国内镜像源候选（按顺序尝试）
HUB_MIRRORS=(
  "docker.m.daocloud.io"
  "docker.1ms.run"
  "hub.rat.dev"
)

# 官方 NAS 镜像源（用于提取 caddy 二进制，国内走南大镜像）
OFFICIAL_IMAGE="ghcr.nju.edu.cn/kanzuori197/deepseek-harness-nas:0.1.0-rc.6"

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

# ---------- 2. 准备 caddy 二进制（从官方镜像提取） ----------
ensure_caddy() {
  if [ -x "docker/caddy/caddy" ]; then
    ok "caddy 二进制已存在: docker/caddy/caddy"
    return
  fi
  info "从官方镜像提取 caddy 二进制（${OFFICIAL_IMAGE}）..."
  CID="$(docker_cmd create "${OFFICIAL_IMAGE}" 2>/dev/null || die "拉取官方镜像失败，请检查网络")"
  docker_cmd cp "${CID}:/usr/local/bin/caddy" docker/caddy/caddy
  docker_cmd rm "${CID}" >/dev/null
  chmod +x docker/caddy/caddy
  ok "caddy 提取完成: $(docker/caddy/caddy version | head -1)"
}

# ---------- 3. 构建 ----------
build() {
  local build_args=(
    --build-arg "DSH_VERSION=${DSH_VERSION}"
    --build-arg "APT_MIRROR=${APT_MIRROR}"
    --build-arg "NPM_REGISTRY=${NPM_REGISTRY}"
  )
  if [ -n "${GH_PROXY}" ]; then
    build_args+=(--build-arg "GH_PROXY=${GH_PROXY}")
  fi
  info "构建镜像 ${IMAGE_NAME}:${TAG} (DSH ${DSH_VERSION}) ..."
  docker_cmd build -t "${IMAGE_NAME}:${TAG}" "${build_args[@]}" .
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
