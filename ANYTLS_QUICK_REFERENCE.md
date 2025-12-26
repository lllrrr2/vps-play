# AnyTLS & Any-Reality 快速参考

## 一、AnyTLS 配置示例

### 服务器端 (sing-box inbound)

```json
{
  "type": "anytls",
  "tag": "anytls-in",
  "listen": "::",
  "listen_port": 443,
  "users": [
    {
       "password": "your-password-here"
    }
  ],
  "padding_scheme": [],
  "tls": {
    "enabled": true,
    "certificate_path": "/path/to/cert.crt",
    "key_path": "/path/to/private.key"
  }
}
```

### 客户端 (sing-box outbound)

```json
{
  "type": "anytls",
  "tag": "anytls-out",
  "server": "your.server.ip",
  "server_port": 443,
  "password": "your-password-here",
  "tls": {
    "enabled": true,
    "server_name": "bing.com",
    "insecure": true
  }
}
```

### 分享链接格式

```
anytls://password@server_ip:port?insecure=1&allowInsecure=1#anytls-hostname
```

**示例**:
```
anytls://Abc123456789@1.2.3.4:443?insecure=1&allowInsecure=1#anytls-vps
```

---

## 二、Any-Reality 配置示例

### 服务器端 (sing-box inbound)

```json
{
  "type": "anytls",
  "tag": "anyreality-in",
  "listen": "::",
  "listen_port": 443,
  "users": [
    {
       "password": "your-password-here"
    }
  ],
  "padding_scheme": [],
  "tls": {
    "enabled": true,
    "server_name": "apple.com",
    "reality": {
      "enabled": true,
      "handshake": {
        "server": "apple.com",
        "server_port": 443
      },
      "private_key": "your-private-key-here",
      "short_id": ["abcd1234"]
    }
  }
}
```

### 客户端 (sing-box outbound)

```json
{
  "type": "anytls",
  "tag": "anyreality-out",
  "server": "your.server.ip",
  "server_port": 443,
  "password": "your-password-here",
  "tls": {
    "enabled": true,
    "server_name": "apple.com",
    "reality": {
      "enabled": true,
      "public_key": "your-public-key-here",
      "short_id": "abcd1234"
    }
  }
}
```

### 分享链接格式

```
anytls://password@server:port?security=reality&sni=apple.com&fp=chrome&pbk=public_key&sid=short_id&type=tcp&headerType=none#any-reality-hostname
```

**示例**:
```
anytls://Abc123456789@1.2.3.4:443?security=reality&sni=apple.com&fp=chrome&pbk=abcdefghijklmn&sid=1234abcd&type=tcp&headerType=none#any-reality-vps
```

---

## 三、Clash Meta 配置

### AnyTLS

```yaml
proxies:
  - name: "AnyTLS"
    type: anytls
    server: your.server.ip
    port: 443
    password: your-password-here
    skip-cert-verify: true
    sni: bing.com
```

### Any-Reality

```yaml
proxies:
  - name: "Any-Reality"
    type: anytls
    server: your.server.ip
    port: 443
    password: your-password-here
    sni: apple.com
    reality-opts:
      public-key: your-public-key-here
      short-id: abcd1234
```

---

## 四、常用目标网站（Reality）

推荐的 Reality 目标网站：

1. **apple.com** （默认，推荐）
   - 全球分布式 CDN
   - HTTPS 稳定

2. **microsoft.com**
   - 流量特征相似
   - 访问稳定

3. **cloudflare.com**
   - 高性能边缘网络
   - 混淆效果好

4. **www.lovelive-anime.jp**
   - 日本动漫官网
   - 适合特定区域

选择标准：
- ✅ 支持 HTTPS (443端口)
- ✅ 全球可访问
- ✅ 流量特征稳定
- ✅ 不易被封锁

---

## 五、证书生成命令

### 方法1: EC prime256v1 (推荐)

```bash
openssl ecparam -genkey -name prime256v1 -out private.key
openssl req -new -x509 -days 36500 -key private.key \
    -out cert.crt -subj "/CN=bing.com"
```

### 方法2: RSA 2048 (备用)

```bash
openssl req -x509 -newkey rsa:2048 \
    -keyout private.key \
    -out cert.crt \
    -days 36500 -nodes \
    -subj "/CN=bing.com"
```

### 方法3: 下载备用证书

```bash
# 私钥
curl -sL -o private.key \
    "https://github.com/yonggekkk/argosbx/releases/download/argosbx/private.key"

# 证书
curl -sL -o cert.crt \
    "https://github.com/yonggekkk/argosbx/releases/download/argosbx/cert.pem"
```

---

## 六、Reality 密钥生成

### 使用 sing-box 生成

```bash
# 生成密钥对
sing-box generate reality-keypair

# 输出示例:
# PrivateKey: "abcdefghijklmnopqrstuvwxyz123456"
# PublicKey: "ABCDEFGHIJKLMNOPQRSTUVWXYZ789012"

# 生成 Short ID
sing-box generate rand --hex 4
# 输出示例: 1234abcd
```

### 手动生成 (备用)

```bash
# 生成 8 位十六进制 Short ID
head /dev/urandom | tr -dc a-f0-9 | head -c 8
```

---

## 七、端口选择建议

### 常用端口

| 端口 | 协议 | 说明 | 推荐度 |
|------|------|------|--------|
| 443 | HTTPS | 最常用，不易被封 | ⭐⭐⭐⭐⭐ |
| 8443 | HTTPS备用 | 备用HTTPS端口 | ⭐⭐⭐⭐ |
| 2096 | Cloudflare | CF CDN端口 | ⭐⭐⭐⭐ |
| 20000-65535 | 随机 | 自定义高位端口 | ⭐⭐⭐ |

### 避免使用

❌ 80 (HTTP，易被识别)  
❌ 22 (SSH，可能引起混淆)  
❌ 3389 (RDP，常被扫描)  
❌ 1080 (SOCKS，敏感端口)

---

## 八、客户端兼容性

### AnyTLS

| 客户端 | 版本要求 | 支持度 |
|--------|---------|--------|
| sing-box | v1.12.0+ | ✅ 完全支持 |
| Clash Meta | latest | ✅ 支持 |
| NekoBox | latest | ✅ 需启用 skip-cert-verify |
| Shadowrocket | - | ⚠️ 需测试 |
| v2rayN | - | ❌ 不支持 |

### Any-Reality

| 客户端 | 版本要求 | 支持度 |
|--------|---------|--------|
| sing-box | v1.12.0+ | ✅ 完全支持 |
| Clash Meta | latest | ✅ 支持 |
| NekoBox | latest | ⚠️ 部分支持 |
| 其他 | - | ❌ 不支持 |

---

## 九、常见问题

### Q1: AnyTLS 和 Any-Reality 有什么区别？

**AnyTLS**:
- 使用自签证书
- 客户端需启用 `insecure: true`
- 配置简单，适合快速部署

**Any-Reality**:
- 使用 Reality 技术伪装真实网站
- 更强的抗审查能力
- 配置稍复杂，需要密钥对

### Q2: 客户端提示证书错误？

**解决方法**:
1. 启用 `insecure: true` 或 `skip-cert-verify: true`
2. 检查 SNI 是否正确（默认: bing.com）
3. 确认证书文件路径正确

### Q3: Reality 连接失败？

**排查步骤**:
1. 检查 public_key 和 private_key 是否匹配
2. 确认 short_id 配置正确
3. 验证目标网站可访问（如 apple.com:443）
4. 客户端 Reality 配置格式是否正确

### Q4: 如何更换 Reality 目标网站？

**方法**:
1. 重新运行安装脚本
2. 在提示时输入新的目标网站（如 microsoft.com）
3. 保持 SNI 与目标网站一致
4. 更新客户端配置

---

## 十、性能优化建议

### 服务器端

```json
{
  "type": "anytls",
  "listen": "::",           // 同时监听 IPv4 和 IPv6
  "sniff": {
    "enabled": true,
    "override_destination": true
  },
  "domain_strategy": "prefer_ipv4"
}
```

### 客户端

```json
{
  "type": "anytls",
  "tcp_fast_open": true,    // 启用 TFO
  "tcp_multi_path": true,   // 启用 MPTCP (需系统支持)
  "multiplex": {
    "enabled": true,
    "protocol": "smux",
    "max_connections": 4,
    "min_streams": 4,
    "max_streams": 0
  }
}
```

---

## 十一、安全建议

1. **密码强度**
   - 最少 16 位
   - 包含大小写字母、数字
   - 避免使用常见单词

2. **端口选择**
   - 优先使用 443 端口
   - 避免使用敏感端口

3. **Reality 配置**
   - 定期更换目标网站
   - 使用知名网站作为伪装

4. **证书更新**
   - 虽然有效期 100 年，但建议定期更换
   - 避免多个服务使用相同证书

---

## 十二、监控与日志

### 查看 sing-box 日志

```bash
# systemd 方式
journalctl -u sing-box -f

# nohup 方式
tail -f ~/.vps-play/singbox/nohup.out
```

### 检查连接状态

```bash
# 查看监听端口
ss -tulnp | grep sing-box

# 查看连接数
ss -ant | grep :443 | wc -l
```

---

**文档版本**: v1.0  
**最后更新**: 2025-12-26  
**项目**: VPS-play
