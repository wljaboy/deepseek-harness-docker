#!/usr/bin/env node
// ============================================================
// DeepSeek Harness NAS —— dsh web「新设备免 token 首访」补丁工具（本仓库原创）
//
// 解决什么问题
//   dsh web 要求每个新设备首次访问首页时必须带启动 token（?token=...），
//   否则返回 401: "dsh web authentication required; reopen the URL printed by dsh web."
//   本部署的入口已有 Caddy HTTPS + Basic Auth 登录（见 docker/caddy/Caddyfile，
//   reverse_proxy 会把 Host/Origin 改写为 127.0.0.1:3080），这层“每设备 token”是多余摩擦。
//
// 补丁做什么
//   修改官方包 @deepseek-ai/dsh-client-connection 的 BrowserAuth.authorizeIndex：
//   当首页请求的 Host 为回环地址（即经 Caddy 转发进来的请求）且无会话 Cookie 时，
//   自动签发与 ?token= 等价的会话 Cookie 并 302 到干净 "/"。
//   - 效果：新设备经 Caddy 登录后直接打开网址即进 GUI，不再需要 token。
//   - 安全边界保留：非回环 Host（直连/公网主机名）仍要求 token；
//     /api 仍需会话 Cookie（首访自动获得）；Caddy Basic Auth 不变。
//   - 老设备已存的 Cookie 仍有效（签名密钥持久化，重启不丢）。
//
// 设计原则：构建期硬校验（fail loud）。
//   dsh 为 npm 预发布（alpha/rc），官方改动代码后本补丁必须同步跟进。
//   匹配失败时本工具以非零退出，docker build 直接失败——绝不静默产出未打补丁的镜像。
//
// 补丁不变式（自动自检，勿删）：
//   apply 写入后必须同时满足：
//     1) 官方短路行 `if (this.isAuthenticated(req)) return true;` 恰好保留 1 处；
//     2) 且其位置在自动签发块（MARKER 注释）之前。
//   历史教训（v1→v2）：v1 用整体替换尾段时误删了该短路行，导致每个已带有效会话
//   Cookie 的首页请求仍被当作未认证，反复重签 Cookie + 303 -> "/"，浏览器报
//   ERR_TOO_MANY_REDIRECTS。回归判据：带 Cookie 的第二次 GET / 必须返回 200
//   （而非 303）。自检在写入前执行，不满足即抛错中止，避免同类事故复发。
//
// 用法（docker build 时由 Dockerfile 调用；容器内亦可手工执行）：
//   node /opt/dsh-web-tokenless/apply.mjs apply     # 打补丁（幂等，失败即退出非零）
//   node /opt/dsh-web-tokenless/apply.mjs status    # patched / pristine / 目标缺失
//   node /opt/dsh-web-tokenless/apply.mjs restore   # 还原官方原版（需先 apply 过生成快照）
//   可选环境变量：
//     DSH_NPM_ROOT   npm 全局安装根（默认由 node 可执行文件位置推导，
//                     即 <prefix>/lib/node_modules，如 /usr/local/lib/node_modules）
// ============================================================

import { readFileSync, writeFileSync, copyFileSync, existsSync, mkdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";

const require = createRequire(import.meta.url);
const MARKER = "// [dsh-nas patch v2] Auto-grant loopback-Host index requests";

// authorizeIndex 无 token 分支的尾段（语义锚点）。命中后在其后插入自动签发块。
// 格式容错：允许任意 [ \t]* 缩进（当前官方包为两个制表符；未来重排为空格也能命中）。
const TAIL_RE = /\n([ \t]*)if \(this\.isAuthenticated\(req\)\) return true;\n[ \t]*this\.writeUnauthorized\(req, res\);\n[ \t]*return false;/u;

// 插入的代码块依赖这些标识符（均在同一 bundle 内定义）。改名/移除则视为官方大改，报错。
const REQUIRED_IDENTIFIERS = [
  "authorizeIndex",
  "requestAuthority",
  "isLoopbackHostname",
  "isAuthenticated",
  "writeUnauthorized",
  "encodeCookie",
  "cookieName",
  "sessionCookie",
  "COOKIE_PAYLOAD_VERSION",
  "maxAgeMilliseconds"
];

function indentBlock(indent) {
  const i = indent; // 尾部 if 所在行的缩进（如两个制表符）
  return (
    `${i}// [dsh-nas patch v2] Auto-grant loopback-Host index requests: clients that\n` +
    `${i}// reach this server through the deployment TLS reverse proxy (Host\n` +
    `${i}// rewritten to 127.0.0.1:3080) get the same authority-bound session\n` +
    `${i}// cookie a valid ?token= exchange would mint, then a redirect to clean\n` +
    `${i}// /. Non-loopback authorities still require the launch token, so the\n` +
    `${i}// browser-session fence is unchanged for direct/public hosts.\n` +
    `${i}// v2 fix: the original patch dropped the isAuthenticated short-circuit,\n` +
    `${i}// causing an endless 303 -> / loop for every index request; the\n` +
    `${i}// authenticated-return-true check is now preserved above this block.\n` +
    `${i}const loopbackAuthority = requestAuthority(req.headers);\n` +
    `${i}const loopbackUrl = loopbackAuthority === void 0 ? void 0 : new URL(\`http://\${loopbackAuthority}\`);\n` +
    `${i}if (loopbackUrl !== void 0 && isLoopbackHostname(loopbackUrl.hostname)) {\n` +
    `${i}\tconst issuedAt = Date.now();\n` +
    `${i}\tconst expiresAt = issuedAt + this.maxAgeMilliseconds;\n` +
    `${i}\tconst value = encodeCookie({\n` +
    `${i}\t\tversion: COOKIE_PAYLOAD_VERSION,\n` +
    `${i}\t\tauthority: loopbackAuthority,\n` +
    `${i}\t\tissuedAt,\n` +
    `${i}\t\texpiresAt\n` +
    `${i}\t}, this.secret);\n` +
    `${i}\tres.writeHead(303, {\n` +
    `${i}\t\t"cache-control": "no-store",\n` +
    `${i}\t\t"location": "/",\n` +
    `${i}\t\t"referrer-policy": "no-referrer",\n` +
    `${i}\t\t"set-cookie": sessionCookie(cookieName(loopbackAuthority), value, expiresAt, Math.floor(this.maxAgeMilliseconds / 1e3))\n` +
    `${i}\t});\n` +
    `${i}\tres.end();\n` +
    `${i}\treturn false;\n` +
    `${i}}\n` +
    `${i}this.writeUnauthorized(req, res);\n` +
    `${i}return false;`
  );
}

function npmRoot() {
  if (process.env.DSH_NPM_ROOT) return process.env.DSH_NPM_ROOT;
  // node 位于 <prefix>/bin/node => 全局模块根 <prefix>/lib/node_modules
  const prefix = dirname(dirname(process.execPath));
  return join(prefix, "lib", "node_modules");
}

function resolveTarget() {
  const root = npmRoot();
  const dshDir = join(root, "@deepseek-ai", "dsh");
  if (!existsSync(join(dshDir, "package.json"))) {
    throw new Error(`找不到 @deepseek-ai/dsh 安装（${dshDir}）。请确认 dsh 已全局安装，或用 DSH_NPM_ROOT 指定 npm 全局根。`);
  }
  let version = "?";
  try {
    version = JSON.parse(readFileSync(join(dshDir, "package.json"), "utf8")).version;
  } catch {
    /* 版本号仅用于诊断 */
  }
  let target;
  try {
    // 从 dsh 包自身解析 client-connection（无论 npm 把它装在其 node_modules 还是提升到全局根）
    target = require.resolve("@deepseek-ai/dsh-client-connection", { paths: [dshDir] });
  } catch {
    throw new Error(`在 dsh@${version} 下解析不到 @deepseek-ai/dsh-client-connection。`);
  }
  return { target, version, dshDir };
}

function checkSyntax(file) {
  const r = spawnSync(process.execPath, ["--check", file], { encoding: "utf8" });
  if (r.status !== 0) {
    throw new Error(`补丁后语法校验失败（node --check ${file}）:\n${(r.stderr || r.stdout || "").trim()}`);
  }
}

function assertIdentifiers(src) {
  const missing = REQUIRED_IDENTIFIERS.filter((id) => !src.includes(id));
  if (missing.length > 0) {
    throw new Error(`dsh-client-connection 代码结构已变化：找不到标识符 ${missing.join(", ")}。\n本补丁需随官方 dsh 版本更新，请对照 docker/patch/web-tokenless-patch.mjs 调整。`);
  }
}

const SHORT_CIRCUIT = "if (this.isAuthenticated(req)) return true;";
const V1_MARKER = "// [dsh-nas patch] Auto-grant loopback-Host index requests";

// 补丁不变式自检（v2.1）：见文件头「补丁不变式」注释。写入前对产物字符串校验，
// 防止未来修改补丁时再次删掉官方短路行（v1 事故）导致无限 303 重定向。
function assertPatchInvariant(patched) {
  const count = patched.split(SHORT_CIRCUIT).length - 1;
  if (count !== 1) {
    throw new Error(
      `补丁不变式校验失败：官方短路行 \`${SHORT_CIRCUIT}\` 出现 ${String(count)} 次（应为恰好 1 次）。\n` +
      `历史教训：v1 版整体替换尾段误删该行导致每个首页请求都被当未认证，反复重签 cookie + 303，` +
      `浏览器报 ERR_TOO_MANY_REDIRECTS。请保留该短路行（位于注入块之前）。未写入任何修改。`
    );
  }
  const scIndex = patched.indexOf(SHORT_CIRCUIT);
  const markerIndex = patched.indexOf(MARKER);
  if (markerIndex === -1 || scIndex > markerIndex) {
    throw new Error(
      `补丁不变式校验失败：短路行必须在自动签发块（${MARKER}）之前。未写入任何修改。`
    );
  }
}

function doApply(target, version) {
  const src = readFileSync(target, "utf8");
  if (src.includes(MARKER)) {
    console.log(`[web-tokenless] 已打过补丁（幂等跳过）: ${target}`);
    return;
  }
  if (src.includes(V1_MARKER) && !src.includes(MARKER)) {
    throw new Error(
      `检测到 v1 旧版补丁残留（${target}）。v2 无法原位升级：请先执行 restore 还原官方原版，再重新 apply。`
    );
  }
  assertIdentifiers(src);
  const match = TAIL_RE.exec(src);
  if (match === null) {
    throw new Error(
      `dsh@${version} 的 client-connection 未命中预期尾段（authorizeIndex 无 token 分支）。\n` +
      `官方代码结构可能已变化，需更新本补丁（docker/patch/web-tokenless-patch.mjs）。未做任何修改。`
    );
  }
  const indent = match[1];
  const start = match.index + 1; // 保留开头的换行
  const end = match.index + match[0].length;
  // v2 fix: 先保留官方“已有有效会话 cookie 即放行”的短路，再注入回环自动签发块。
  // 旧版补丁把这一行一起替换掉了，导致每次请求都重签 cookie + 303，形成无限重定向。
  const patched =
    src.slice(0, start) +
    `${indent}if (this.isAuthenticated(req)) return true;\n` +
    indentBlock(indent) +
    src.slice(end);
  assertPatchInvariant(patched); // 写入前自检（短路保留且位于注入块之前）

  // 首次 apply 时在旁边留一份官方原版快照，供 restore 使用
  const snapshot = `${target}.pristine`;
  if (!existsSync(snapshot)) {
    copyFileSync(target, snapshot);
    console.log(`[web-tokenless] 已保存官方原版快照: ${snapshot}`);
  }
  writeFileSync(target, patched, "utf8");
  checkSyntax(target);
  console.log(`[web-tokenless] 补丁已应用: ${target}（dsh@${version}）`);
  console.log("[web-tokenless] 重启 dsh web 后生效；还原: node <本脚本> restore");
}

function doStatus() {
  let info;
  try {
    info = resolveTarget();
  } catch (error) {
    console.error(`[web-tokenless] ${error.message}`);
    process.exitCode = 1;
    return;
  }
  const src = readFileSync(info.target, "utf8");
  const state = src.includes(MARKER) ? "patched (已打补丁)" : "pristine (官方原版)";
  console.log(`[web-tokenless] ${info.target}（dsh@${info.version}）: ${state}`);
}

function doRestore() {
  const { target, version } = resolveTarget();
  const snapshot = `${target}.pristine`;
  if (!existsSync(snapshot)) {
    throw new Error(`找不到官方原版快照 ${snapshot}——请先 install 官方 dsh 或删除后重新安装，再执行 apply。`);
  }
  copyFileSync(snapshot, target);
  checkSyntax(target);
  console.log(`[web-tokenless] 已还原官方原版: ${target}（dsh@${version}）。重启 dsh web 后生效。`);
}

const cmd = process.argv[2] ?? "status";
try {
  if (cmd === "apply") {
    const { target, version } = resolveTarget();
    doApply(target, version);
  } else if (cmd === "status") {
    doStatus();
  } else if (cmd === "restore") {
    doRestore();
  } else {
    console.error("用法: node web-tokenless-patch.mjs <apply|status|restore>   (环境变量: DSH_NPM_ROOT)");
    process.exitCode = 1;
  }
} catch (error) {
  console.error(`[web-tokenless] ERROR: ${error.message}`);
  process.exitCode = 1;
}
