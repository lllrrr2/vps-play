# AnyTLS 协议分析与代码对比

## 一、argosbx 脚本中的 AnyTLS 实现分析

### 1. 基础配置参数

从 `argosbx.sh` 脚本中提取的关键代码：

```bash
# 第507-538行: AnyTLS 配置
if [ -n "$anp" ]; then
    anp=anpt
    if [ -z "$port_an" ] && [ ! -e "$HOME/agsbx/port_an" ]; then
        port_an=$(shuf -i 10000-65535 -n 1)
        echo "$port_an" > "$HOME/agsbx/port_an"
    elif [ -n "$port_an" ]; then
        echo "$port_an" > "$HOME/agsbx/port_an"
    fi
    port_an=$(cat "$HOME/agsbx/port_an")
    echo "Anytls端口：$port_an"
    cat >> "$HOME/agsbx/sb.json" <<EOF
        {
            "type":"anytls",
            "tag":"anytls-sb",
            "listen":"::",
            "listen_port":${port_an},
            "users":[
                {
                  "password":"${uuid}"
                }
            ],
            "padding_scheme":[],
            "tls":{
                "enabled": true,
                "certificate_path": "$HOME/agsbx/cert.pem",
                "key_path": "$HOME/agsbx/private.key"
            }
        },
EOF
else
    anp=anptargo
fi
```

### 2. Any-Reality 配置（AnyTLS + Reality）

```bash
# 第539-596行: Any-Reality 配置
if [ -n "$arp" ]; then
    arp=arpt
    if [ -z "$ym_vl_re" ]; then
        ym_vl_re=apple.com
    fi
    echo "$ym_vl_re" > "$HOME/agsbx/ym_vl_re"
    echo "Reality域名：$ym_vl_re"
    mkdir -p "$HOME/agsbx/sbk"
    if [ ! -e "$HOME/agsbx/sbk/private_key" ]; then
        key_pair=$("$HOME/agsbx/sing-box" generate reality-keypair)
        private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
        public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
        short_id=$("$HOME/agsbx/sing-box" generate rand --hex 4)
        echo "$private_key" > "$HOME/agsbx/sbk/private_key"
        echo "$public_key" > "$HOME/agsbx/sbk/public_key"
        echo "$short_id" > "$HOME/agsbx/sbk/short_id"
    fi
    private_key_s=$(cat "$HOME/agsbx/sbk/private_key")
    public_key_s=$(cat "$HOME/agsbx/sbk/public_key")
    short_id_s=$(cat "$HOME/agsbx/sbk/short_id")
    if [ -z "$port_ar" ] && [ ! -e "$HOME/agsbx/port_ar" ]; then
        port_ar=$(shuf -i 10000-65535 -n 1)
        echo "$port_ar" > "$HOME/agsbx/port_ar"
    elif [ -n "$port_ar" ]; then
        echo "$port_ar" > "$HOME/agsbx/port_ar"
    fi
    port_ar=$(cat "$HOME/agsbx/port_ar")
    echo "Any-Reality端口：$port_ar"
    cat >> "$HOME/agsbx/sb.json" <<EOF
        {
            "type":"anytls",
            "tag":"anyreality-sb",
            "listen":"::",
            "listen_port":${port_ar},
            "users":[
                {
                  "password":"${uuid}"
                }
            ],
            "padding_scheme":[],
            "tls": {
            "enabled": true,
            "server_name": "${ym_vl_re}",
             "reality": {
              "enabled": true,
              "handshake": {
              "server": "${ym_vl_re}",
              "server_port": 443
             },
             "private_key": "$private_key_s",
             "short_id": ["$short_id_s"]
            }
          }
        },
EOF
else
    arp=arptargo
fi
```

### 3. 证书生成

```bash
# 第430-435行: 证书生成
command -v openssl >/dev/null 2>&1 && openssl ecparam -genkey -name prime256v1 -out "$HOME/agsbx/private.key" >/dev/null 2>&1
command -v openssl >/dev/null 2>&1 && openssl req -new -x509 -days 36500 -key "$HOME/agsbx/private.key" -out "$HOME/agsbx/cert.pem" -subj "/CN=www.bing.com" >/dev/null 2>&1
if [ ! -f "$HOME/agsbx/private.key" ]; then
    url="https://github.com/yonggekkk/argosbx/releases/download/argosbx/private.key"; out="$HOME/agsbx/private.key"; (command -v curl>/dev/null 2>&1 && curl -Ls -o "$out" --retry 2 "$url") || (command -v wget>/dev/null 2>&1 && timeout 3 wget -q -O "$out" --tries=2 "$url")
    url="https://github.com/yonggekkk/argosbx/releases/download/argosbx/cert.pem"; out="$HOME/agsbx/cert.pem"; (command -v curl>/dev/null 2>&1 && curl -Ls -o "$out" --retry 2 "$url") || (command -v wget>/dev/null 2>&1 && timeout 3 wget -q -O "$out" --tries=2 "$url")
fi
```

### 4. 节点信息输出

```bash
# 第1261-1276行: 节点信息显示
if grep anytls-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then
echo "💣【 AnyTLS 】节点信息如下："
port_an=$(cat "$HOME/agsbx/port_an")
an_link="anytls://$uuid@$server_ip:$port_an?insecure=1&allowInsecure=1#${sxname}anytls-$hostname"
echo "$an_link" >> "$HOME/agsbx/jh.txt"
echo "$an_link"
echo
fi
if grep anyreality-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then
echo "💣【 Any-Reality 】节点信息如下："
port_ar=$(cat "$HOME/agsbx/port_ar")
ar_link="anytls://$uuid@$server_ip:$port_ar?security=reality&sni=$ym_vl_re&fp=chrome&pbk=$public_key_s&sid=$short_id_s&type=tcp&headerType=none#${sxname}any-reality-$hostname"
echo "$ar_link" >> "$HOME/agsbx/jh.txt"
echo "$ar_link"
echo
fi
```

## 二、VPS-play 现有实现分析

### 当前 AnyTLS 实现特点

1. **版本检查**: 自动检测和升级到 sing-box v1.12.0+
2. **证书管理**: 使用 EC prime256v1 或 RSA 2048 自签证书
3. **配置简单**: 单个 AnyTLS inbound + mixed detour
4. **节点信息**: 提供基础分享链接和 JSON 配置

### 缺少的功能

1. ❌ **Any-Reality 支持**: 未实现 AnyTLS + Reality 组合
2. ❌ **padding_scheme**: 配置中缺少此字段
3. ❌ **链接格式**: 分享链接缺少 `insecure=1&allowInsecure=1` 参数
4. ❌ **证书备用方案**: 未实现从远程下载备用证书
5. ❌ **多协议组合**: 未与其他协议（如 Hysteria2、TUIC）方便组合

## 三、改进建议

### 1. 完善 AnyTLS 配置

**添加 padding_scheme 字段**:
```json
{
  "type": "anytls",
  "tag": "anytls-in",
  "listen": "::",
  "listen_port": 443,
  "users": [
    {"password": "your-password"}
  ],
  "padding_scheme": [],  // 添加此字段
  "tls": {
    "enabled": true,
    "certificate_path": "/path/to/cert.pem",
    "key_path": "/path/to/private.key"
  }
}
```

### 2. 添加 Any-Reality 支持

创建新函数 `install_any_reality()`:
```bash
install_any_reality() {
    # 1. 版本检查
    # 2. Reality 密钥对生成
    # 3. 端口配置
    # 4. 生成配置文件（AnyTLS + Reality）
    # 5. 输出节点信息
}
```

配置示例:
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
      "private_key": "your-private-key",
      "short_id": ["abcd1234"]
    }
  }
}
```

### 3. 改进分享链接格式

**AnyTLS 基础链接**:
```
anytls://password@server_ip:port?insecure=1&allowInsecure=1#AnyTLS-hostname
```

**Any-Reality 链接**:
```
anytls://password@server_ip:port?security=reality&sni=apple.com&fp=chrome&pbk=public_key&sid=short_id&type=tcp&headerType=none#Any-Reality-hostname
```

### 4. 证书备用方案

```bash
generate_anytls_cert() {
    local cert_dir="$1"
    local cert_domain="${2:-bing.com}"
    
    # 方法1: EC prime256v1
    if command -v openssl >/dev/null 2>&1; then
        openssl ecparam -genkey -name prime256v1 -out "$cert_dir/private.key" >/dev/null 2>&1
        openssl req -new -x509 -days 36500 -key "$cert_dir/private.key" \
            -out "$cert_dir/cert.pem" -subj "/CN=$cert_domain" >/dev/null 2>&1
    fi
    
    # 方法2: RSA 2048 (备用)
    if [ ! -f "$cert_dir/private.key" ]; then
        openssl req -x509 -newkey rsa:2048 \
            -keyout "$cert_dir/private.key" \
            -out "$cert_dir/cert.pem" \
            -days 36500 -nodes \
            -subj "/CN=$cert_domain" >/dev/null 2>&1
    fi
    
    # 方法3: 从 GitHub 下载备用证书
    if [ ! -f "$cert_dir/private.key" ]; then
        echo "正在下载备用证书..."
        curl -Ls -o "$cert_dir/private.key" \
            "https://github.com/yonggekkk/argosbx/releases/download/argosbx/private.key" 2>/dev/null
        curl -Ls -o "$cert_dir/cert.pem" \
            "https://github.com/yonggekkk/argosbx/releases/download/argosbx/cert.pem" 2>/dev/null
    fi
}
```

### 5. Reality 密钥生成（sing-box）

```bash
generate_reality_keys() {
    local key_dir="$1"
    local singbox_bin="$2"
    
    mkdir -p "$key_dir"
    
    if [ -e "$key_dir/private_key" ]; then
        # 已存在，读取
        private_key=$(cat "$key_dir/private_key")
        public_key=$(cat "$key_dir/public_key")
        short_id=$(cat "$key_dir/short_id")
    else
        # 生成新密钥对
        key_pair=$("$singbox_bin" generate reality-keypair)
        private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
        public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
        short_id=$("$singbox_bin" generate rand --hex 4)
        
        # 保存
        echo "$private_key" > "$key_dir/private_key"
        echo "$public_key" > "$key_dir/public_key"
        echo "$short_id" > "$key_dir/short_id"
    fi
    
    echo "$private_key"
    echo "$public_key"
    echo "$short_id"
}
```

## 四、实施计划

### Phase 1: 改进现有 AnyTLS 功能
- [ ] 添加 `padding_scheme: []` 字段
- [ ] 完善分享链接格式（添加 insecure 参数）
- [ ] 实现证书备用下载方案
- [ ] 优化节点信息输出

### Phase 2: 添加 Any-Reality 支持
- [ ] 创建 `install_any_reality()` 函数
- [ ] 实现 Reality 密钥对自动生成
- [ ] 配置 AnyTLS + Reality 组合
- [ ] 生成 Any-Reality 分享链接

### Phase 3: 菜单集成
- [ ] 在主菜单添加 Any-Reality 选项
- [ ] 在组合安装中支持 Any-Reality
- [ ] 完善配置管理和查看功能

## 五、代码对比总结

| 特性 | argosbx | VPS-play | 改进建议 |
|------|---------|----------|----------|
| AnyTLS 基础 | ✅ | ✅ | 添加 padding_scheme |
| Any-Reality | ✅ | ❌ | 需要实现 |
| 证书生成 | ✅ EC + 备用下载 | ✅ EC + RSA 备用 | 添加远程下载 |
| 分享链接 | ✅ 完整参数 | ⚠️ 缺少 insecure | 完善参数 |
| Reality 密钥 | ✅ | ❌ | 需要实现 |
| 多协议组合 | ✅ | ✅ | 已支持 |

## 六、参考资料

- argosbx GitHub: https://github.com/yonggekkk/argosbx
- sing-box 官方文档: https://sing-box.sagernet.org/
- AnyTLS 协议说明: sing-box v1.12.0+ 新协议
- Reality 协议: XTLS 开发的新型协议
