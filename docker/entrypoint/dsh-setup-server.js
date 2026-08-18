#!/usr/bin/env node
// DeepSeek Harness NAS - 首次部署认证设置服务（本仓库原创）
// 监听 127.0.0.1:3081，提供网页设置页，保存后写入 /data/dsh/.dsh-auth.json
const http = require('http');
const fs = require('fs');
const { execFileSync } = require('child_process');

const AUTH_FILE = process.env.DSH_HOME + '/.dsh-auth.json';
const PORT = 3081;

const html = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>DeepSeek Harness - 首次设置</title>
<style>
body{font-family:-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;background:#f5f7fa;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0}
.card{background:#fff;border-radius:12px;box-shadow:0 4px 24px rgba(0,0,0,.08);padding:40px;width:360px}
h1{font-size:20px;color:#1a1a2e;margin:0 0 8px}
p.desc{color:#666;font-size:13px;margin:0 0 24px;line-height:1.6}
label{display:block;font-size:13px;color:#333;margin:12px 0 6px}
input{width:100%;box-sizing:border-box;padding:10px 12px;border:1px solid #d9dee8;border-radius:8px;font-size:14px;outline:none}
input:focus{border-color:#4f7cff}
button{width:100%;margin-top:24px;padding:12px;background:#4f7cff;color:#fff;border:none;border-radius:8px;font-size:15px;cursor:pointer}
button:hover{background:#3d68e8}
button:disabled{background:#a8b8e8;cursor:not-allowed}
.msg{margin-top:12px;font-size:13px;color:#e04f4f;min-height:18px}
.ok{color:#2f9e44}
</style>
</head>
<body>
<div class="card">
<h1>DeepSeek Harness 首次设置</h1>
<p class="desc">这是首次部署，请设置登录用户名和密码。<br>设置完成后将自动启用登录保护。</p>
<label for="u">用户名</label>
<input id="u" autocomplete="username" placeholder="如 admin">
<label for="p">密码（至少 12 位）</label>
<input id="p" type="password" autocomplete="new-password" placeholder="至少 12 位字符">
<label for="c">确认密码</label>
<input id="c" type="password" autocomplete="new-password" placeholder="再次输入密码">
<button id="btn">保存并启用登录</button>
<div class="msg" id="msg"></div>
</div>
<script>
const btn=document.getElementById('btn'),msg=document.getElementById('msg'),u=document.getElementById('u'),p=document.getElementById('p'),c=document.getElementById('c');
btn.onclick=async()=>{
  msg.className='msg';msg.textContent='';
  if(!u.value.trim())return msg.textContent='用户名不能为空';
  if(p.value.length<12)return msg.textContent='密码至少需要 12 个字符';
  if(p.value!==c.value)return msg.textContent='两次输入的密码不一致';
  btn.disabled=true;btn.textContent='保存中...';
  try{
    const r=await fetch('/setup',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:u.value.trim(),password:p.value,confirm:c.value})});
    const d=await r.json();
    if(d.ok){msg.className='msg ok';msg.textContent='设置成功！正在启用登录...';setTimeout(()=>{msg.textContent='页面即将跳转，请刷新后使用新账号登录';},500);}
    else{msg.textContent=d.error||'保存失败';btn.disabled=false;btn.textContent='保存并启用登录';}
  }catch(e){msg.textContent='网络错误：'+e.message;btn.disabled=false;btn.textContent='保存并启用登录';}
};
</script>
</body>
</html>
`;

function fail(res, error) {
  res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify({ ok: false, error }));
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
  } else if (req.method === 'POST' && req.url === '/setup') {
    if (fs.existsSync(AUTH_FILE)) {
      return fail(res, '认证配置已存在，请重启容器后直接登录');
    }
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      try {
        const { username, password, confirm } = JSON.parse(body);
        if (!username || !username.trim()) return fail(res, '用户名不能为空');
        if (!password || password.length < 12) return fail(res, '密码至少需要 12 个字符');
        if (password !== confirm) return fail(res, '两次输入的密码不一致');
        const hash = execFileSync('caddy', ['hash-password', '--plaintext', password]).toString().trim();
        fs.writeFileSync(AUTH_FILE, JSON.stringify({ username: username.trim(), hash }));
        res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ ok: true }));
      } catch (e) {
        fail(res, '处理失败: ' + e.message);
      }
    });
  } else {
    res.writeHead(404);
    res.end();
  }
});

server.listen(PORT, '127.0.0.1');
console.log('setup server: http://127.0.0.1:' + PORT);