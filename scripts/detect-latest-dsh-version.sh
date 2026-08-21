#!/usr/bin/env bash
# ============================================================
# 查询 DeepSeek Harness 官方 npm 包（@deepseek-ai/dsh）的最新版本
#
# 输出：版本号（如 0.1.0-rc.8）
# 特性：
#   - python 自包含获取官方源 registry.npmjs.org（不依赖 curl 管道/第三方镜像）
#   - 不依赖 dist-tag=latest（官方把 rc 版本打在 next 标签上，latest 会滞后）
#   - 版本排序：正式版优先，其次按 rc 序号取最高
#   - 网络失败自动重试 3 次（3s/6s 退避），单次超时 10 秒
#
# 用法: bash scripts/detect-latest-dsh-version.sh
# 被 CI 工作流（.github/workflows/auto-rebuild.yml）与 scripts/build.sh 共用
# ============================================================
set -euo pipefail

python3 - <<'PY'
import json, re, sys, time, urllib.request

data = None
for attempt in range(3):
    try:
        req = urllib.request.Request("https://registry.npmjs.org/@deepseek-ai/dsh")
        req.add_header("User-Agent", "dsh-version-check")
        data = json.loads(urllib.request.urlopen(req, timeout=10).read().decode())
        break
    except Exception:
        if attempt == 2:
            sys.exit(1)
        time.sleep(3 * (attempt + 1))

versions = list((data.get("versions") or {}).keys())
if not versions:
    sys.exit(1)

rx = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$")
rcx = re.compile(r"^rc\.(\d+)$")

def key(v: str):
    m = rx.match(v)
    if not m:
        return (-1, -1, -1, 1, "", -1, v)
    major, minor, patch = map(int, m.group(1, 2, 3))
    pre = m.group(4) or ""
    if not pre:
        # 正式版：优先级最高
        return (major, minor, patch, 1, "", 0, v)
    mrc = rcx.match(pre)
    if mrc:
        # rc 版本：按 rc 序号比较
        return (major, minor, patch, 0, "rc", int(mrc.group(1)), v)
    # 其他预发布（beta/alpha 等）
    return (major, minor, patch, 0, pre, 0, v)

print(max(versions, key=key))
PY
