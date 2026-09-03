# dsh web「免 token 首访」补丁 —— 设计纪要（含事故复盘）

> 本仓库原创补丁。相关代码：`docker/patch/web-tokenless-patch.mjs`
> （构建期由 Dockerfile 自动 apply）；Dockerfile 步骤 4.6。

## 一、背景与目标

dsh web（DeepSeek Harness Web GUI，官方 npm 包 `@deepseek-ai/dsh`）要求每个**新设备**
首次访问首页时，网址必须带启动 token（`?token=...`），否则返回：

```
dsh web authentication required; reopen the URL printed by dsh web.
```

本部署入口已有 **Caddy HTTPS + Basic Auth 登录**（`docker/caddy/Caddyfile` 把 Host/Origin
改写为 `127.0.0.1:3080`），这层"每设备 token"是多余摩擦。补丁目标：**经 Caddy 登录后的
新设备，打开网址即直达 GUI，无需 token**。

## 二、补丁机制

修改官方 `@deepseek-ai/dsh-client-connection` 的 `BrowserAuth.authorizeIndex`：当首页
请求的 Host 为**回环地址**（即经 Caddy 转发进来的请求）且**无有效会话 Cookie** 时，
自动签发与 `?token=` 等价的会话 Cookie，并 303 到干净 `/`。

安全边界保持不变：

- 非回环 Host（直连 / 公网主机名）仍要求 token；
- `/api` 仍校验会话 Cookie（首访自动获得）；
- 静态资源仍公开；Caddy Basic Auth 不变；
- 老设备已存的 Cookie 继续有效（签名密钥持久化，重启不丢）。

## 三、事故复盘（v1 → v2，重要）

**现象**：拉取首批内置补丁的镜像后，浏览器打开站点提示
`ERR_TOO_MANY_REDIRECTS`（"重定向你太多次"），删 Cookie / 无痕模式均无效。

**根因**：v1 版工具用正则整体替换 `authorizeIndex` 尾段时，把官方短路行
`if (this.isAuthenticated(req)) return true;`（"已有有效会话 Cookie 即直接放行"）
一起删掉了。结果每个首页请求都被当作未认证 → 回环分支**反复重签 Cookie + 303 → "/"**
→ 无限重定向。（测试日志特征：`Set-Cookie` 的 `issuedAt` 逐次递增。）

**修复（v2）**：注入自动签发块**之前**显式保留官方短路行——已认证请求直接放行，
仅未认证的回环请求才自动签发。

**教训**：给官方代码打"插入型"补丁时，绝不能破坏原有控制流；必须用
"已有分支保持原样、只新增分支"的写法，并对产物做结构自检（见下）。

## 四、不变式与回归判据（已编码为工具自检）

打补丁后的 `authorizeIndex` 必须满足：

1. 官方短路行 `if (this.isAuthenticated(req)) return true;` **恰好 1 处**；
2. 且位于自动签发块（`// [dsh-nas patch v2] ...` 注释）**之前**。

回归判据（浏览器行为）：

- 第一次 `GET /`（无 Cookie）→ `303` + `Set-Cookie`；
- 带上该 Cookie 的第二次 `GET /` → **`200`**（而非 `303`）；
- 全程重定向次数恰好 1 次。

`apply.mjs` 在写入文件**前**执行该不变式自检，不满足即报错退出（docker build 失败），
防止同类事故复发。

## 五、维护指引（官方 dsh 升级时）

补丁对官方代码结构敏感（fail-loud 设计）：

1. 官方 dsh 出新版（alpha/rc）后，若 `docker build` 在步骤 4.6 失败并提示
   "未命中预期尾段 / 找不到标识符"，说明官方改了 `client-connection` 代码，
   **不要**简单跳过补丁，应按报错更新 `web-tokenless-patch.mjs` 的匹配逻辑；
2. 更新后务必跑一次回归：见下文"本地验证"；
3. `v1` 旧补丁无法被 `v2` 原位升级（会显式报错）：先 `restore` 还原官方原版，
   再重新 `apply`。镜像重建流程每次基于全新 npm 安装，天然不受此限制。

## 六、本地验证（容器内 / 构建前）

```sh
# 状态
node /opt/dsh-web-tokenless/apply.mjs status     # patched / pristine

# 打补丁 / 还原（幂等；还原需先 apply 过，自动留有 .pristine 快照）
node /opt/dsh-web-tokenless/apply.mjs apply
node /opt/dsh-web-tokenless/apply.mjs restore

# 行为回归（curl 等价浏览器两步）：
#   第 1 步：curl -c jar http://127.0.0.1:3080/           → 303 + Set-Cookie
#   第 2 步：curl -b jar -L http://127.0.0.1:3080/        → 200，重定向数 = 1
```

> 对官方新版本做离线预检：`npm pack @deepseek-ai/dsh-client-connection@<版本>`，
> 用 `DSH_NPM_ROOT` 指向一个模拟 npm 全局目录跑 `apply`，再核对短路行与结构。
