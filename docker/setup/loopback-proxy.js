#!/usr/bin/env node
// DeepSeek Harness NAS - 回环设置代理（本仓库原创）
//
// 为什么需要它：
//   官方 DeepSeek Harness 的 Web 设置有明确约束 —— DSH web 只能绑定 127.0.0.1
//   （官方刻意禁止 --host 0.0.0.0：会暴露远程代码执行），且设置/凭据等特权
//   方法集只在浏览器以「回环 hostname」打开页面时才可用（客户端 isLoopback 判定）。
//   而本镜像对外只暴露 Caddy 的 HTTPS 8443，反向代理到容器内 127.0.0.1:3080；
//   用户从局域网 IP / 域名访问时，浏览器地址栏 hostname 不是回环 → 设置页报
//   "settings are unavailable in this browser"。
//
//   解决：本进程在容器内把 0.0.0.0:<DSH_SETUP_PORT> 透明转发到 127.0.0.1:3080
//   （DSH web）。配合 docker 把该端口只发布到宿主机回环 127.0.0.1:<port>，
//   再在本机用 SSH 隧道（ssh -L <port>:127.0.0.1:<port> <NAS>）打开
//   http://127.0.0.1:<port>，浏览器 hostname 即回环 → 设置页可用。
//
//   透明 TCP 转发不解析 HTTP，因此 /api 的 unary 与 WebSocket（events.mux /
//   events.host）都能原样通过。
const net = require('net');
const os = require('os');

const LISTEN_HOST = process.env.DSH_SETUP_LISTEN_HOST || '0.0.0.0';
const LISTEN_PORT = Number(process.env.DSH_SETUP_PORT || 0);
const TARGET_HOST = process.env.DSH_WEB_HOST || '127.0.0.1';
const TARGET_PORT = Number(process.env.DSH_WEB_PORT || 3080);

if (!Number.isInteger(LISTEN_PORT) || LISTEN_PORT <= 0) {
  // 未启用（DSH_SETUP_PORT 未设置或为 0）：静默退出，不占端口
  process.exit(0);
}
if (!Number.isInteger(TARGET_PORT) || TARGET_PORT <= 0) {
  console.error('[loopback-proxy] 无效的目标端口: ' + TARGET_PORT);
  process.exit(1);
}

const server = net.createServer((client) => {
  const upstream = net.connect(TARGET_PORT, TARGET_HOST, () => {
    client.pipe(upstream).pipe(client);
  });

  upstream.on('error', (err) => {
    console.error('[loopback-proxy] 上游连接失败(' + TARGET_HOST + ':' + TARGET_PORT + '): ' + err.message);
    client.destroy();
  });
  client.on('error', () => {});
  client.on('close', () => upstream.destroy());
  upstream.on('close', () => client.destroy());
  // 空闲保活：无数据 15 分钟则断开，避免闲置隧道堆积
  client.setTimeout(15 * 60 * 1000, () => {
    client.destroy();
    upstream.destroy();
  });
});

// 端口占用 / 绑定失败时明确报错并让 entrypoint 感知（非零退出）
server.on('error', (err) => {
  console.error('[loopback-proxy] 监听 ' + LISTEN_HOST + ':' + LISTEN_PORT + ' 失败: ' + err.message);
  process.exit(1);
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  const ifaces = os.networkInterfaces();
  const lan = Object.values(ifaces).flat().find((a) => a && a.family === 'IPv4' && !a.internal);
  console.log('[loopback-proxy] 回环设置代理已就绪：' + LISTEN_HOST + ':' + LISTEN_PORT
    + ' -> ' + TARGET_HOST + ':' + TARGET_PORT);
  console.log('[loopback-proxy] 本机打开回环 URL（配合 SSH 隧道）: http://127.0.0.1:' + LISTEN_PORT);
  if (lan) {
    console.log('[loopback-proxy] 提示：只有把该端口发布为宿主机回环(127.0.0.1)才安全；请勿暴露到 0.0.0.0/公网。');
  }
});
