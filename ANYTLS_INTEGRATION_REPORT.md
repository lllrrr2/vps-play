# AnyTLS 协议集成完成报告

## 一、项目背景

根据 argosbx 脚本的实现，将 AnyTLS 和 Any-Reality 协议的完整支持集成到 VPS-play 项目中。

## 二、已完成的改进

### 1. 改进 AnyTLS 基础协议

**文件**: `modules/singbox/manager.sh` - `install_anytls()` 函数

**改进内容**:

✅ **添加 `padding_scheme` 字段**
- 在配置中添加空的 `padding_scheme: []` 字段
- 与 argosbx 保持一致，为未来扩展预留

✅ **完善分享链接格式**
- 旧格式: `anytls://password@server:port#name`
- 新格式: `anytls://password@server:port?insecure=1&allowInsecure=1#anytls-hostname`
- 添加 `insecure=1&allowInsecure=1` 参数，提升客户端兼容性

✅ **实现三层证书备用方案**
1. **方法1**: 使用 EC prime256v1 生成证书（最优）
2. **方法2**: 使用 RSA 2048 生成证书（备用）
3. **方法3**: 从 GitHub 下载预置证书（最终备用）

```bash
# 方法1: EC prime256v1
openssl ecparam -genkey -name prime256v1 -out "anytls.key"
openssl req -new -x509 -days 36500 -key "anytls.key" -out "anytls.crt" -subj "/CN=bing.com"

# 方法2: RSA 2048
openssl req -x509 -newkey rsa:2048 -keyout "anytls.key" -out "anytls.crt" -days 36500 -nodes -subj "/CN=bing.com"

# 方法3: 从 argosbx 项目下载备用证书
curl -sL -o "anytls.key" "https://github.com/yonggekkk/argosbx/releases/download/argosbx/private.key"
curl -sL -o "anytls.crt" "https://github.com/yonggekkk/argosbx/releases/download/argosbx/cert.pem"
```

✅ **改进 JSON 输出配置**
- 添加完整的 TLS 配置信息到 JSON 输出
- 包含 `insecure: true` 参数

### 2. 新增 Any-Reality 协议

**文件**: `modules/singbox/manager.sh` - `install_any_reality()` 函数 (新增)

**功能特点**:

✅ **AnyTLS + Reality 组合**
- 结合 AnyTLS 协议的隐蔽性
- 利用 Reality 的抗审查能力
- sing-box v1.12.0+ 独有协议

✅ **自动密钥管理**
```bash
# Reality 密钥对生成
sing-box generate reality-keypair

# 密钥持久化保存
$CERT_DIR/reality/
├── private_key    # 服务器私钥
├── public_key     # 客户端公钥
└── short_id       # 短ID
```

✅ **完整配置示例**
```json
{
  "type": "anytls",
  "tag": "anyreality-in",
  "listen": "::",
  "listen_port": 443,
  "users": [
    {"password": "your-password"}
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
      "private_key": "xxx",
      "short_id": ["abcd1234"]
    }
  }
}
```

✅ **分享链接格式**
```
anytls://password@server_ip:port?security=reality&sni=apple.com&fp=chrome&pbk=public_key&sid=short_id&type=tcp&headerType=none#any-reality-hostname
```

### 3. 菜单集成

**文件**: `modules/singbox/manager.sh` - `show_singbox_menu()` 函数

**更新内容**:

```
==================== sing-box 管理 ====================
 单协议安装
 1.  Hysteria2 (推荐)
 2.  TUIC v5
 3.  VLESS Reality
 4.  AnyTLS (新)
 5.  Any-Reality (AnyTLS + Reality)    ← 新增
---------------------------------------------------
 多协议组合
 6.  自定义组合 (多选协议)
 7.  预设组合 (一键安装)
---------------------------------------------------
 服务管理
 8.  启动
 9.  停止
 10. 重启
 11. 查看状态
---------------------------------------------------
 12. 查看节点信息
 13. 查看配置文件
 14. 卸载 sing-box
```

## 三、代码对比总结

| 特性 | argosbx | VPS-play (改进前) | VPS-play (改进后) | 状态 |
|------|---------|------------------|------------------|------|
| AnyTLS 基础 | ✅ | ✅ | ✅ | ✅ 完成 |
| padding_scheme | ✅ | ❌ | ✅ | ✅ 已添加 |
| insecure 参数 | ✅ | ❌ | ✅ | ✅ 已添加 |
| Any-Reality | ✅ | ❌ | ✅ | ✅ 已实现 |
| Reality 密钥管理 | ✅ | ❌ | ✅ | ✅ 已实现 |
| 证书三层备用 | ✅ | ⚠️ | ✅ | ✅ 已完善 |
| 分享链接完整性 | ✅ | ⚠️ | ✅ | ✅ 已完善 |

## 四、使用指南

### AnyTLS 安装

```bash
cd /path/to/vps-play
bash modules/singbox/manager.sh

# 选择菜单: 4. AnyTLS (新)
```

**配置步骤**:
1. 系统自动检查 sing-box 版本，必要时升级到 v1.12.0+
2. 配置端口（留空随机分配 10000-65535）
3. 配置密码（留空随机16位字符）
4. 自动生成自签证书
5. 生成配置文件和分享链接
6. 询问是否立即启动

### Any-Reality 安装

```bash
cd /path/to/vps-play
bash modules/singbox/manager.sh

# 选择菜单: 5. Any-Reality (AnyTLS + Reality)
```

**配置步骤**:
1. 版本检查（sing-box v1.12.0+）
2. 配置端口
3. 配置密码
4. 配置目标网站（默认: apple.com）
5. 配置 SNI（默认: 与目标网站相同）
6. 自动生成 Reality 密钥对
7. 生成配置并启动

### 客户端配置

#### AnyTLS

**sing-box 客户端** (v1.12.0+):
```json
{
  "type": "anytls",
  "tag": "proxy",
  "server": "your-server-ip",
  "server_port": 443,
  "password": "your-password",
  "tls": {
    "enabled": true,
    "server_name": "bing.com",
    "insecure": true
  }
}
```

**Clash Meta**:
使用分享链接导入或手动配置：
```yaml
- name: AnyTLS
  type: anytls
  server: your-server-ip
  port: 443
  password: your-password
  skip-cert-verify: true
  sni: bing.com
```

#### Any-Reality

**sing-box 客户端**:
```json
{
  "type": "anytls",
  "tag": "proxy",
  "server": "your-server-ip",
  "server_port": 443,
  "password": "your-password",
  "tls": {
    "enabled": true,
    "server_name": "apple.com",
    "reality": {
      "enabled": true,
      "public_key": "your-public-key",
      "short_id": "short-id"
    }
  }
}
```

## 五、技术亮点

### 1. 渐进式错误处理

证书生成采用三层备用方案，确保在各种环境下都能成功：
- 优先使用 EC prime256v1（更安全）
- RSA 2048 作为备用（兼容性好）
- 远程下载预置证书（最终保障）

### 2. 密钥持久化

Reality 密钥对自动生成并保存到文件：
```bash
$CERT_DIR/reality/
├── private_key    # 服务器端使用
├── public_key     # 客户端配置需要
└── short_id       # Reality 协议参数
```

重新安装时会复用已有密钥，节点配置保持一致。

### 3. 完整的节点信息

每次安装后都会生成：
- `node_info.txt`: 完整的配置说明和示例
- `anytls_link.txt` / `anyreality_link.txt`: 分享链接
- 终端输出: 即时查看关键信息

### 4. 版本兼容性检查

```bash
# 自动检测 sing-box 版本
if [ -z "$current_ver" ] || ! version_ge "$current_ver" "$min_ver"; then
    echo "正在自动升级内核..."
    download_singbox "$min_ver"
fi
```

确保 AnyTLS 协议所需的 v1.12.0+ 内核。

## 六、已知问题与解决

### 问题1: OpenSSL 不可用

**现象**: EC 证书生成失败  
**解决**: 自动降级到 RSA 2048，或从 GitHub 下载备用证书

### 问题2: sing-box 命令不存在

**现象**: Reality 密钥生成失败  
**解决**: 提供备用的 `head /dev/urandom` 方法生成随机 short_id

### 问题3: 端口被占用

**现象**: 配置的端口已被使用  
**解决**: 自动检测端口占用，重新分配随机端口

## 七、后续优化建议

### 1. 支持多协议组合

在 `install_combo_internal()` 函数中添加 Any-Reality 支持：
```bash
# 添加到组合安装选项
echo " 5. Any-Reality (AnyTLS + Reality)"
```

### 2. 支持自定义 padding_scheme

允许用户配置 padding 策略：
```json
"padding_scheme": ["random:100-200"]  // 随机填充 100-200 字节
```

### 3. Reality 目标网站优化

提供常用目标网站列表：
- apple.com（默认）
- microsoft.com
- cloudflare.com
- www.lovelive-anime.jp

### 4. 配置导出/导入

添加配置备份功能：
```bash
# 导出节点配置
vps-play export-config > config.json

# 导入配置快速部署
vps-play import-config config.json
```

## 八、参考资料

- **argosbx 项目**: https://github.com/yonggekkk/argosbx
- **sing-box 官方文档**: https://sing-box.sagernet.org/
- **AnyTLS 协议说明**: sing-box v1.12.0 changelog
- **Reality 协议**: https://github.com/XTLS/REALITY

## 九、贡献者

- **原始实现**: yonggekkk (argosbx)
- **集成到 VPS-play**: 本次改进
- **参考文档**: sing-box 官方团队

---

## 快速测试

### 测试 AnyTLS
```bash
# 安装
bash modules/singbox/manager.sh
# 选择: 4

# 验证
curl -v https://your-server-ip:port
# 应该看到 TLS 握手成功

# 客户端测试
# 使用分享链接导入到 sing-box 或 Clash Meta
```

### 测试 Any-Reality
```bash
# 安装
bash modules/singbox/manager.sh
# 选择: 5

# 查看密钥
cat ~/.vps-play/singbox/cert/reality/public_key

# 客户端配置
# 使用公钥和 short_id 配置 Reality
```

**测试环境建议**:
- 服务器: Debian 11+ / Ubuntu 20.04+ / CentOS 8+
- 客户端: sing-box v1.12.0+ / Clash Meta
- 网络: 需要公网 IP

---

**状态**: ✅ 集成完成  
**测试**: ⚠️ 待用户测试  
**文档**: ✅ 已完善
