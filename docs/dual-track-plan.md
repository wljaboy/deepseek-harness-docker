# 双轨版本跟随改造方案（备忘）

> **触发条件**：DeepSeek Harness 官方发布**正式版**（npm `dist-tags.latest` 不再是 rc 版本）后实施。
> 当前状态（0.1.0-rc.8）：只有预发布，维持单轨，`:latest` 指向最高预发布版本。
> 本文件为未来改造的操作手册，由 2026-08-21 的对话约定留存。

## 目标标签语义

| 官方 npm dist-tag | 镜像 tag（ghcr.io/wljaboy/deepseek-harness-nas） | 轨 |
| --- | --- | --- |
| `latest`（正式版，如 1.0.0） | `:latest` + `:1.0.0` | 稳定轨 |
| `next`（预发布，如 1.1.0-rc.1） | `:next` + `:1.1.0-rc.1` | 预发布轨 |

## 规则

1. **两者都存在** → 双轨各构建各的
2. **只有预发布**（现状） → `:latest` 仍指向最高预发布（保持老用户 `docker pull :latest` 不中断），同时新增 `:next`
3. **只有正式版** → 只出稳定轨

## 改动清单

1. **scripts/detect-latest-dsh-version.sh**
   - 改为同时输出两个值：最高正式版 + 最高预发布（或新增 `detect-stable` / `detect-next` 两个入口）
   - 现有"正式版优先"的排序逻辑拆成两种：stable = 非预发布中最高；next = 预发布中最高（rc 序号）
2. **.github/workflows/auto-rebuild.yml**
   - 拆成双轨构建（或 matrix：`latest` 轨 + `next` 轨），每轨独立判断"是否需要构建"（各自对比自己的记录文件）
   - 保持每天的北京时间 01:00 / 07:30 双定时
3. **版本记录**
   - `.last-built-version` 拆成 `.last-built-stable` / `.last-built-next`（避免无变化时重复构建）
4. **README.md**
   - 环境变量/拉取章节补充 `latest` / `next` 标签语义说明
5. **build.sh**（可选）
   - 本地构建默认跟 `latest` 轨（正式版优先），`DSH_VERSION` 仍可手动指定任意版本

## 注意事项

- 双版本并存时 CI 需构建 2 次，运行时间约翻倍
- 镜像命名/路径不变，只增 tag
- 保持 `:latest` 的向后兼容（老用户不断流）
- 触发信号：npm `dist-tags.latest` 出现非 rc 版本，或 GitHub Releases 出现正式版
