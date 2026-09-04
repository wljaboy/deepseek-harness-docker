# 用容器 Service 名接入 Cloudflare Tunnel（不依赖局域网 IP）

> **适用场景**：你的 cloudflared 隧道容器和本容器在同一 Docker 自定义网络里，
> 且希望公网访问不依赖宿主局域网 IP（IP 变了 / 网段改了都不断公网）。
> 面板里不再填 `https://192.168.1.100:8443` 这种 IP，而是直接填容器名。

---

## 为什么推荐这样做

在 Cloudflare 面板把 Service URL 写成宿主 IP（如 `https://192.168.1.100:8443`）时，
一旦宿主机的局域网 IP 变化（换路由 / DHCP 重分配），公网立刻失效，必须回面板改一次。

若 cloudflared 与本容器**同属一个 Docker 自定义网络**，面板可以直接写
`https://<服务名>:<容器内端口>`，由 Docker 内置 DNS 解析——宿主 IP 怎么变都不受影响
（`openclaw` 这类服务同样适用本方案）。

## 前置条件

1. 本容器与 cloudflared 容器在**同一个自定义 bridge 网络**里
   （如 `docker network inspect <网络名>` 能看到两个容器；compose 项目内默认同网）。
2. 面板入口已存在（Public Hostname 已添加）。

## 配置步骤（Cloudflare Zero Trust 面板）

进 **Zero Trust → Networks → Tunnels → 你的隧道 → Public Hostname → 编辑**：

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| Service Type | `HTTPS` | 容器内 Caddy 是 HTTPS |
| URL | `https://<容器名>:8443` | ⚠️ **8443 是容器内部端口**，不是宿主机映射的端口 |
| No TLS Verify | **开启** | 容器内是自签名证书，必须关验证 |
| Origin Server Name（SNI） | **你的公网域名**（即 `DSH_PUBLIC_HOST`） | ⚠️ 关键，见下方「为什么必须设 SNI」 |

> 面板里的 "Origin Server Name" 在不同界面可能叫 "SNI" / "Server Name"，
> 填纯域名（不带协议端口），与 `.env` 里 `DSH_PUBLIC_HOST` 保持一致。

## 三个最容易踩的坑（都是实测）

### 坑 1：URL 端口写错 → `connection refused` / 502

```text
dial tcp 172.18.0.8:8773: connect: connection refused
```

**原因**：宿主上映射的是 `8773 -> 容器 8443`（`docker ps` 里 `0.0.0.0:8773->8443/tcp`）。
写 Service URL 时沿用宿主端口 `8773` 就会连到容器里不存在的端口。
**容器名方式必须写容器内部端口 `8443`**。

### 坑 2：SNI 不匹配 Caddy 证书 → `remote error: tls: internal error`

```text
Unable to reach the origin service: remote error: tls: internal error
```

**原因**：本容器用 Caddy 托管 HTTPS，只为两个名字签发证书：
`HTTPS_ACCESS_HOST`（局域网 IP）和 `DSH_PUBLIC_HOST`（你的公网域名）。
Service URL 写成 `https://deepseek-harness:8443` 时，cloudflared 默认用
`deepseek-harness` 做 SNI——Caddy 没有这个证书，握手直接失败。

**解决**：面板里把 **Origin Server Name 设为 `DSH_PUBLIC_HOST` 的域名**，
让 TLS 握手携带 Caddy 认识的域名。（No TLS Verify 仍需开启，因为证书是自签的。）

### 坑 3：改完配置后浏览器「重定向太多次」

**原因**：多半是浏览器残留的旧会话 Cookie 与新的访问路径不匹配，
dsh 反复 303 跳转（常见于刚切换访问方式后，或旧 Cookie 未失效时）。

**解决**：用**无痕窗口**（Ctrl+Shift+N）重新打开即可，无需改任何配置。
确认可用后再让其他新设备直接访问。

## 免 token 首访（新设备直达）

本镜像内置「免 token 首访」补丁：Caddy 转发时会把 Host 改写为回环地址
`127.0.0.1:3080`，dsh 判定为回环来源后自动签发会话 Cookie——
**所以无论面板指向宿主 IP 还是容器 service 名，经 Caddy 的请求都免 token**，
新设备登录 Basic Auth 后直达界面，不需要复制 `?token=...` 链接。

> ⚠️ 补丁修改的是镜像内文件，**镜像升级 / 容器重建后会丢失**。
> 升级后验证新设备首访是否还要 token；若需要，重新执行补丁脚本再重启容器：
>
> ```bash
> docker exec <容器名> node /data/dsh/web-tokenless-patch.mjs apply
> docker restart <容器名>
> ```
>
> 也可在镜像入口脚本（`dsh web &` 之前）加一行自动 apply，一劳永逸：
>
> ```sh
> node /data/dsh/web-tokenless-patch.mjs apply
> ```

## 快速故障排查表

| 现象（cloudflared 日志 / 页面） | 原因 | 处理 |
| --- | --- | --- |
| `connect: connection refused` | Service URL 端口写成了宿主映射口 | 改为容器内部端口 `8443` |
| `tls: internal error` | SNI 不是 Caddy 认识的域名 | 面板 Origin Server Name 填 `DSH_PUBLIC_HOST` |
| `x509: certificate is not valid for any names` | No TLS Verify 未开启 | 面板开启 No TLS Verify |
| `dial tcp ... no such host` | 两容器不在同一 Docker 网络 | 让 cloudflared 与容器同网 |
| 页面「重定向太多次」 | 浏览器旧 Cookie | 无痕窗口重开 |
| 新设备要 token | 镜像升级后补丁丢失 | 重跑 `web-tokenless-patch.mjs apply` |

## 验证命令

```bash
# 两个容器是否同网络
docker network inspect <网络名> --format '{{range .Containers}}{{.Name}} {{end}}'

# cloudflared 侧能否解析服务名（进 cloudflared 容器，若带 shell）
docker exec <cloudflared容器> getent hosts <容器名>

# 看 cloudflared 实时错误
docker logs <cloudflared容器> --tail 20
```
