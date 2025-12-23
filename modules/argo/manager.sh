#!/bin/bash
# Argo 节点模块 - VPS-play
# 使用 Cloudflare Argo Tunnel 搭建代理节点
# 支持 VLESS+WS+TLS、VMess+WS+TLS 等

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/argo"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"
[ -z "$VPSPLAY_DIR" ] && VPSPLAY_DIR="$HOME/vps-play"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/process_manager.sh" ] && source "$VPSPLAY_DIR/utils/process_manager.sh"

# ==================== 颜色定义 ====================
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Cyan="\033[36m"
Blue="\033[34m"
Reset="\033[0m"
Info="${Green}[信息]${Reset}"
Error="${Red}[错误]${Reset}"
Warning="${Yellow}[警告]${Reset}"
Tip="${Cyan}[提示]${Reset}"

# ==================== 配置 ====================
ARGO_DIR="$HOME/.vps-play/argo"
CFD_BIN="$ARGO_DIR/cloudflared"
XRAY_BIN="$ARGO_DIR/xray"
XRAY_CONF="$ARGO_DIR/config.json"
ARGO_LOG="$ARGO_DIR/argo.log"
NODE_INFO="$ARGO_DIR/node_info.txt"
LINKS_FILE="$ARGO_DIR/links.txt"

mkdir -p "$ARGO_DIR"

# ==================== 下载工具 ====================
download_cloudflared() {
    echo -e "${Info} 下载 Cloudflared..."
    
    local download_url=""
    
    case "$OS_TYPE" in
        linux)
            case "$(uname -m)" in
                x86_64|amd64) download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" ;;
                aarch64|arm64) download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" ;;
                armv7l) download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm" ;;
            esac
            ;;
        freebsd)
            download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-freebsd-amd64"
            ;;
    esac
    
    if [ -z "$download_url" ]; then
        echo -e "${Error} 不支持的系统架构"
        return 1
    fi
    
    curl -sL "$download_url" -o "$CFD_BIN"
    chmod +x "$CFD_BIN"
    
    if [ -f "$CFD_BIN" ]; then
        echo -e "${Info} Cloudflared 下载完成"
        return 0
    else
        echo -e "${Error} 下载失败"
        return 1
    fi
}

download_xray() {
    echo -e "${Info} 下载 Xray..."
    
    local download_url=""
    local arch_name=""
    
    case "$(uname -m)" in
        x86_64|amd64) arch_name="64" ;;
        aarch64|arm64) arch_name="arm64-v8a" ;;
        armv7l) arch_name="arm32-v7a" ;;
    esac
    
    case "$OS_TYPE" in
        linux)
            download_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${arch_name}.zip"
            ;;
        freebsd)
            download_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-freebsd-${arch_name}.zip"
            ;;
    esac
    
    if [ -z "$download_url" ]; then
        echo -e "${Error} 不支持的系统架构"
        return 1
    fi
    
    cd "$ARGO_DIR"
    curl -sL "$download_url" -o xray.zip
    unzip -oq xray.zip xray
    rm -f xray.zip
    chmod +x xray
    
    if [ -f "$XRAY_BIN" ]; then
        echo -e "${Info} Xray 下载完成"
        return 0
    else
        echo -e "${Error} 下载失败"
        return 1
    fi
}

# ==================== 生成配置 ====================
generate_uuid() {
    cat /proc/sys/kernel/random/uuid 2>/dev/null || \
    uuidgen 2>/dev/null || \
    echo "$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)-$(head /dev/urandom | tr -dc a-f0-9 | head -c 4)-$(head /dev/urandom | tr -dc a-f0-9 | head -c 4)-$(head /dev/urandom | tr -dc a-f0-9 | head -c 4)-$(head /dev/urandom | tr -dc a-f0-9 | head -c 12)"
}

generate_random_port() {
    local min=${1:-10000}
    local max=${2:-65535}
    shuf -i ${min}-${max} -n 1 2>/dev/null || echo $((RANDOM % (max - min + 1) + min))
}

# ==================== VLESS+WS+Argo ====================
install_vless_ws_argo() {
    echo -e ""
    echo -e "${Cyan}========== 安装 VLESS+WS+Argo 节点 ==========${Reset}"
    
    # 下载组件
    [ ! -f "$CFD_BIN" ] && download_cloudflared
    [ ! -f "$XRAY_BIN" ] && download_xray
    
    # 生成配置
    local uuid=$(generate_uuid)
    local ws_path="/$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)"
    local listen_port=$(generate_random_port 20000 40000)
    
    echo -e ""
    echo -e "${Info} 配置参数:"
    read -p "UUID [留空随机]: " input_uuid
    [ -n "$input_uuid" ] && uuid="$input_uuid"
    
    read -p "WebSocket 路径 [${ws_path}]: " input_path
    [ -n "$input_path" ] && ws_path="$input_path"
    
    read -p "本地监听端口 [${listen_port}]: " input_port
    [ -n "$input_port" ] && listen_port="$input_port"
    
    # 生成 Xray 配置
    cat > "$XRAY_CONF" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-ws",
      "port": ${listen_port},
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${ws_path}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF

    echo -e "${Info} Xray 配置已生成"
    
    # 启动 Xray
    echo -e "${Info} 启动 Xray..."
    nohup "$XRAY_BIN" run -c "$XRAY_CONF" > "$ARGO_DIR/xray.log" 2>&1 &
    local xray_pid=$!
    echo "$xray_pid" > "$ARGO_DIR/xray.pid"
    sleep 2
    
    if ! kill -0 "$xray_pid" 2>/dev/null; then
        echo -e "${Error} Xray 启动失败"
        cat "$ARGO_DIR/xray.log"
        return 1
    fi
    echo -e "${Info} Xray 运行中 (PID: ${xray_pid})"
    
    # 启动 Argo 隧道
    echo -e ""
    echo -e "${Info} 启动 Argo 隧道 (临时隧道)..."
    echo -e "${Tip} 获取 Cloudflare 临时域名中..."
    
    # 使用临时隧道
    nohup "$CFD_BIN" tunnel --url "http://127.0.0.1:${listen_port}" --no-autoupdate > "$ARGO_LOG" 2>&1 &
    local cfd_pid=$!
    echo "$cfd_pid" > "$ARGO_DIR/cfd.pid"
    
    # 等待获取临时域名
    local argo_domain=""
    local max_wait=30
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        sleep 2
        waited=$((waited + 2))
        
        argo_domain=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" "$ARGO_LOG" 2>/dev/null | head -1)
        
        if [ -n "$argo_domain" ]; then
            break
        fi
        
        echo -e "${Info} 等待 Argo 隧道建立... (${waited}s)"
    done
    
    if [ -z "$argo_domain" ]; then
        echo -e "${Error} Argo 隧道建立失败"
        cat "$ARGO_LOG"
        stop_argo
        return 1
    fi
    
    # 提取域名
    local domain=$(echo "$argo_domain" | sed 's|https://||')
    
    echo -e ""
    echo -e "${Green}========== VLESS+WS+Argo 安装完成 ==========${Reset}"
    echo -e ""
    echo -e " 协议: ${Cyan}VLESS${Reset}"
    echo -e " 地址: ${Cyan}${domain}${Reset}"
    echo -e " 端口: ${Cyan}443${Reset}"
    echo -e " UUID: ${Cyan}${uuid}${Reset}"
    echo -e " 传输: ${Cyan}WebSocket${Reset}"
    echo -e " 路径: ${Cyan}${ws_path}${Reset}"
    echo -e " TLS: ${Cyan}开启${Reset}"
    echo -e ""
    
    # 生成分享链接
    local vless_link="vless://${uuid}@${domain}:443?encryption=none&security=tls&sni=${domain}&type=ws&host=${domain}&path=${ws_path}#Argo-VLESS-${domain}"
    
    echo -e " 分享链接:"
    echo -e " ${Yellow}${vless_link}${Reset}"
    echo -e ""
    
    # 保存节点信息
    cat > "$NODE_INFO" << EOF
协议: VLESS+WS+TLS (Argo)
域名: ${domain}
端口: 443
UUID: ${uuid}
路径: ${ws_path}
TLS: 开启 (Cloudflare 证书)
EOF
    
    echo "$vless_link" > "$LINKS_FILE"
    
    echo -e "${Green}=========================================${Reset}"
    echo -e ""
    echo -e "${Warning} 这是临时隧道，重启后域名会改变"
    echo -e "${Tip} 如需固定域名，请使用选项 2 (Token 模式)"
}

# ==================== VLESS+WS+Argo (Token) ====================
install_vless_ws_argo_token() {
    echo -e ""
    echo -e "${Cyan}========== 安装 VLESS+WS+Argo (固定隧道) ==========${Reset}"
    echo -e ""
    echo -e "${Tip} 使用 Cloudflare 控制台创建隧道获取 Token"
    echo -e "${Tip} 步骤: Cloudflare Dashboard -> Zero Trust -> Networks -> Tunnels"
    echo -e ""
    
    read -p "Argo Token: " argo_token
    [ -z "$argo_token" ] && { echo -e "${Error} Token 不能为空"; return 1; }
    
    read -p "隧道绑定的域名 (如 vless.example.com): " argo_domain
    [ -z "$argo_domain" ] && { echo -e "${Error} 域名不能为空"; return 1; }
    
    # 下载组件
    [ ! -f "$CFD_BIN" ] && download_cloudflared
    [ ! -f "$XRAY_BIN" ] && download_xray
    
    # 生成配置
    local uuid=$(generate_uuid)
    local ws_path="/$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)"
    local listen_port=$(generate_random_port 20000 40000)
    
    echo -e ""
    read -p "UUID [留空随机]: " input_uuid
    [ -n "$input_uuid" ] && uuid="$input_uuid"
    
    read -p "WebSocket 路径 [${ws_path}]: " input_path
    [ -n "$input_path" ] && ws_path="$input_path"
    
    read -p "本地监听端口 [${listen_port}]: " input_port
    [ -n "$input_port" ] && listen_port="$input_port"
    
    # 生成 Xray 配置
    cat > "$XRAY_CONF" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-ws",
      "port": ${listen_port},
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${ws_path}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF

    # 保存 Token
    echo "$argo_token" > "$ARGO_DIR/token.txt"
    echo "$argo_domain" > "$ARGO_DIR/domain.txt"
    echo "$listen_port" > "$ARGO_DIR/port.txt"
    
    # 启动服务
    start_argo_token
    
    echo -e ""
    echo -e "${Green}========== VLESS+WS+Argo (固定隧道) 安装完成 ==========${Reset}"
    echo -e ""
    echo -e " 协议: ${Cyan}VLESS${Reset}"
    echo -e " 域名: ${Cyan}${argo_domain}${Reset}"
    echo -e " 端口: ${Cyan}443${Reset}"
    echo -e " UUID: ${Cyan}${uuid}${Reset}"
    echo -e " 路径: ${Cyan}${ws_path}${Reset}"
    echo -e ""
    
    # 生成分享链接
    local vless_link="vless://${uuid}@${argo_domain}:443?encryption=none&security=tls&sni=${argo_domain}&type=ws&host=${argo_domain}&path=${ws_path}#Argo-VLESS-${argo_domain}"
    
    echo -e " 分享链接:"
    echo -e " ${Yellow}${vless_link}${Reset}"
    
    # 保存
    cat > "$NODE_INFO" << EOF
协议: VLESS+WS+TLS (Argo Token)
域名: ${argo_domain}
端口: 443
UUID: ${uuid}
路径: ${ws_path}
EOF
    
    echo "$vless_link" > "$LINKS_FILE"
    echo -e "${Green}=========================================${Reset}"
}

# ==================== VMess+WS+Argo ====================
install_vmess_ws_argo() {
    echo -e ""
    echo -e "${Cyan}========== 安装 VMess+WS+Argo 节点 ==========${Reset}"
    
    # 下载组件
    [ ! -f "$CFD_BIN" ] && download_cloudflared
    [ ! -f "$XRAY_BIN" ] && download_xray
    
    # 生成配置
    local uuid=$(generate_uuid)
    local ws_path="/$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)"
    local listen_port=$(generate_random_port 20000 40000)
    local alter_id=0
    
    echo -e ""
    read -p "UUID [留空随机]: " input_uuid
    [ -n "$input_uuid" ] && uuid="$input_uuid"
    
    read -p "WebSocket 路径 [${ws_path}]: " input_path
    [ -n "$input_path" ] && ws_path="$input_path"
    
    # 生成 Xray 配置
    cat > "$XRAY_CONF" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vmess-ws",
      "port": ${listen_port},
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "alterId": ${alter_id}
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${ws_path}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF

    echo -e "${Info} Xray 配置已生成"
    
    # 启动 Xray
    echo -e "${Info} 启动 Xray..."
    nohup "$XRAY_BIN" run -c "$XRAY_CONF" > "$ARGO_DIR/xray.log" 2>&1 &
    local xray_pid=$!
    echo "$xray_pid" > "$ARGO_DIR/xray.pid"
    sleep 2
    
    if ! kill -0 "$xray_pid" 2>/dev/null; then
        echo -e "${Error} Xray 启动失败"
        cat "$ARGO_DIR/xray.log"
        return 1
    fi
    
    # 启动 Argo 隧道
    echo -e "${Info} 启动 Argo 隧道..."
    nohup "$CFD_BIN" tunnel --url "http://127.0.0.1:${listen_port}" --no-autoupdate > "$ARGO_LOG" 2>&1 &
    local cfd_pid=$!
    echo "$cfd_pid" > "$ARGO_DIR/cfd.pid"
    
    # 等待域名
    local argo_domain=""
    local max_wait=30
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        sleep 2
        waited=$((waited + 2))
        argo_domain=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" "$ARGO_LOG" 2>/dev/null | head -1)
        [ -n "$argo_domain" ] && break
        echo -e "${Info} 等待 Argo 隧道... (${waited}s)"
    done
    
    if [ -z "$argo_domain" ]; then
        echo -e "${Error} Argo 隧道建立失败"
        stop_argo
        return 1
    fi
    
    local domain=$(echo "$argo_domain" | sed 's|https://||')
    
    echo -e ""
    echo -e "${Green}========== VMess+WS+Argo 安装完成 ==========${Reset}"
    echo -e ""
    echo -e " 协议: ${Cyan}VMess${Reset}"
    echo -e " 地址: ${Cyan}${domain}${Reset}"
    echo -e " 端口: ${Cyan}443${Reset}"
    echo -e " UUID: ${Cyan}${uuid}${Reset}"
    echo -e " 路径: ${Cyan}${ws_path}${Reset}"
    echo -e ""
    
    # 生成 VMess 链接 (标准 base64 格式)
    local vmess_json=$(cat << EOF
{
  "v": "2",
  "ps": "Argo-VMess-${domain}",
  "add": "${domain}",
  "port": "443",
  "id": "${uuid}",
  "aid": "${alter_id}",
  "scy": "auto",
  "net": "ws",
  "type": "none",
  "host": "${domain}",
  "path": "${ws_path}",
  "tls": "tls",
  "sni": "${domain}"
}
EOF
)
    local vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w0)"
    
    echo -e " 分享链接:"
    echo -e " ${Yellow}${vmess_link}${Reset}"
    
    # 保存
    cat > "$NODE_INFO" << EOF
协议: VMess+WS+TLS (Argo)
域名: ${domain}
端口: 443
UUID: ${uuid}
AlterId: ${alter_id}
路径: ${ws_path}
EOF
    
    echo "$vmess_link" > "$LINKS_FILE"
    echo -e "${Green}=========================================${Reset}"
}

# ==================== 多协议组合 ====================
install_multi_protocol() {
    echo -e ""
    echo -e "${Cyan}========== 安装 多协议 Argo 节点 ==========${Reset}"
    echo -e "${Tip} 同时支持 VLESS 和 VMess"
    echo -e ""
    
    # 下载组件
    [ ! -f "$CFD_BIN" ] && download_cloudflared
    [ ! -f "$XRAY_BIN" ] && download_xray
    
    # 生成配置
    local uuid=$(generate_uuid)
    local vless_path="/vl$(head /dev/urandom | tr -dc a-z0-9 | head -c 4)"
    local vmess_path="/vm$(head /dev/urandom | tr -dc a-z0-9 | head -c 4)"
    local listen_port=$(generate_random_port 20000 40000)
    
    echo -e "${Info} 使用统一 UUID: ${Cyan}${uuid}${Reset}"
    echo -e "${Info} VLESS 路径: ${Cyan}${vless_path}${Reset}"
    echo -e "${Info} VMess 路径: ${Cyan}${vmess_path}${Reset}"
    
    # 生成多入站配置
    cat > "$XRAY_CONF" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-ws",
      "port": ${listen_port},
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${vless_path}"
        }
      }
    },
    {
      "tag": "vmess-ws",
      "port": $((listen_port + 1)),
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${vmess_path}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF

    # 启动 Xray
    echo -e "${Info} 启动 Xray..."
    nohup "$XRAY_BIN" run -c "$XRAY_CONF" > "$ARGO_DIR/xray.log" 2>&1 &
    echo "$!" > "$ARGO_DIR/xray.pid"
    sleep 2
    
    # 启动两个 Argo 隧道
    echo -e "${Info} 启动 VLESS Argo 隧道..."
    nohup "$CFD_BIN" tunnel --url "http://127.0.0.1:${listen_port}" --no-autoupdate > "$ARGO_DIR/argo_vless.log" 2>&1 &
    echo "$!" > "$ARGO_DIR/cfd_vless.pid"
    
    echo -e "${Info} 启动 VMess Argo 隧道..."
    nohup "$CFD_BIN" tunnel --url "http://127.0.0.1:$((listen_port + 1))" --no-autoupdate > "$ARGO_DIR/argo_vmess.log" 2>&1 &
    echo "$!" > "$ARGO_DIR/cfd_vmess.pid"
    
    # 等待域名
    sleep 15
    
    local vless_domain=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" "$ARGO_DIR/argo_vless.log" 2>/dev/null | head -1 | sed 's|https://||')
    local vmess_domain=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" "$ARGO_DIR/argo_vmess.log" 2>/dev/null | head -1 | sed 's|https://||')
    
    echo -e ""
    echo -e "${Green}========== 多协议 Argo 节点安装完成 ==========${Reset}"
    echo -e ""
    
    # VLESS 链接
    if [ -n "$vless_domain" ]; then
        echo -e " ${Cyan}VLESS 节点:${Reset}"
        echo -e " 域名: ${vless_domain}"
        local vless_link="vless://${uuid}@${vless_domain}:443?encryption=none&security=tls&sni=${vless_domain}&type=ws&host=${vless_domain}&path=${vless_path}#Argo-VLESS"
        echo -e " 链接: ${Yellow}${vless_link}${Reset}"
        echo -e ""
    fi
    
    # VMess 链接
    if [ -n "$vmess_domain" ]; then
        echo -e " ${Cyan}VMess 节点:${Reset}"
        echo -e " 域名: ${vmess_domain}"
        local vmess_json=$(cat << EOF
{"v":"2","ps":"Argo-VMess","add":"${vmess_domain}","port":"443","id":"${uuid}","aid":"0","scy":"auto","net":"ws","type":"none","host":"${vmess_domain}","path":"${vmess_path}","tls":"tls","sni":"${vmess_domain}"}
EOF
)
        local vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w0)"
        echo -e " 链接: ${Yellow}${vmess_link}${Reset}"
    fi
    
    echo -e ""
    echo -e "${Green}=========================================${Reset}"
}

# ==================== 服务管理 ====================
start_argo_token() {
    if [ ! -f "$ARGO_DIR/token.txt" ]; then
        echo -e "${Error} 未找到 Token 配置"
        return 1
    fi
    
    local token=$(cat "$ARGO_DIR/token.txt")
    local port=$(cat "$ARGO_DIR/port.txt" 2>/dev/null || echo "8080")
    
    # 启动 Xray
    [ -f "$XRAY_CONF" ] && {
        echo -e "${Info} 启动 Xray..."
        nohup "$XRAY_BIN" run -c "$XRAY_CONF" > "$ARGO_DIR/xray.log" 2>&1 &
        echo "$!" > "$ARGO_DIR/xray.pid"
    }
    
    sleep 2
    
    # 启动 Cloudflared
    echo -e "${Info} 启动 Cloudflared 隧道..."
    nohup "$CFD_BIN" tunnel --no-autoupdate run --token "$token" > "$ARGO_LOG" 2>&1 &
    echo "$!" > "$ARGO_DIR/cfd.pid"
    
    sleep 3
    
    if kill -0 "$(cat "$ARGO_DIR/cfd.pid" 2>/dev/null)" 2>/dev/null; then
        echo -e "${Info} ${Green}Argo 隧道启动成功${Reset}"
    else
        echo -e "${Error} Argo 隧道启动失败"
        cat "$ARGO_LOG"
    fi
}

stop_argo() {
    echo -e "${Info} 停止 Argo 服务..."
    
    # 停止所有相关进程
    for pid_file in "$ARGO_DIR"/*.pid; do
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file")
            kill "$pid" 2>/dev/null
            rm -f "$pid_file"
        fi
    done
    
    # 确保进程已停止
    pkill -f "cloudflared.*tunnel" 2>/dev/null
    pkill -f "xray.*run" 2>/dev/null
    
    echo -e "${Info} Argo 服务已停止"
}

restart_argo() {
    stop_argo
    sleep 2
    
    if [ -f "$ARGO_DIR/token.txt" ]; then
        start_argo_token
    else
        echo -e "${Warning} 临时隧道需要重新安装以获取新域名"
    fi
}

status_argo() {
    echo -e ""
    echo -e "${Green}==================== Argo 状态 ====================${Reset}"
    
    # Xray 状态
    if [ -f "$ARGO_DIR/xray.pid" ] && kill -0 "$(cat "$ARGO_DIR/xray.pid")" 2>/dev/null; then
        echo -e " Xray: ${Green}运行中${Reset} (PID: $(cat "$ARGO_DIR/xray.pid"))"
    else
        echo -e " Xray: ${Red}已停止${Reset}"
    fi
    
    # Cloudflared 状态
    local cfd_running=false
    for pid_file in "$ARGO_DIR"/cfd*.pid; do
        if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
            echo -e " Cloudflared: ${Green}运行中${Reset} (PID: $(cat "$pid_file"))"
            cfd_running=true
        fi
    done
    
    [ "$cfd_running" = false ] && echo -e " Cloudflared: ${Red}已停止${Reset}"
    
    echo -e "${Green}===================================================${Reset}"
}

show_node_info() {
    if [ -f "$NODE_INFO" ]; then
        echo -e ""
        echo -e "${Green}==================== 节点信息 ====================${Reset}"
        cat "$NODE_INFO"
        echo -e "${Green}===================================================${Reset}"
        
        if [ -f "$LINKS_FILE" ]; then
            echo -e ""
            echo -e "${Info} 分享链接:"
            cat "$LINKS_FILE"
        fi
    else
        echo -e "${Warning} 未找到节点配置"
    fi
}

uninstall_argo() {
    echo -e "${Warning} 确定要卸载 Argo 节点? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    stop_argo
    rm -rf "$ARGO_DIR"
    echo -e "${Info} Argo 节点已卸载"
}

# ==================== 主菜单 ====================
show_argo_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔═╗╦═╗╔═╗╔═╗  ╔╗╔╔═╗╔╦╗╔═╗
    ╠═╣╠╦╝║ ╦║ ║  ║║║║ ║ ║║║╣ 
    ╩ ╩╩╚═╚═╝╚═╝  ╝╚╝╚═╝═╩╝╚═╝
    Cloudflare Argo 节点
EOF
        echo -e "${Reset}"
        
        # 显示状态
        if [ -f "$XRAY_BIN" ] && [ -f "$CFD_BIN" ]; then
            echo -e " 安装状态: ${Green}已安装${Reset}"
            if [ -f "$ARGO_DIR/xray.pid" ] && kill -0 "$(cat "$ARGO_DIR/xray.pid" 2>/dev/null)" 2>/dev/null; then
                echo -e " 运行状态: ${Green}运行中${Reset}"
            else
                echo -e " 运行状态: ${Red}已停止${Reset}"
            fi
        else
            echo -e " 安装状态: ${Yellow}未安装${Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== Argo 节点管理 ====================${Reset}"
        echo -e " ${Yellow}安装节点 (临时隧道)${Reset}"
        echo -e " ${Green}1.${Reset}  VLESS+WS+Argo (推荐)"
        echo -e " ${Green}2.${Reset}  VMess+WS+Argo"
        echo -e " ${Green}3.${Reset}  多协议组合 (VLESS+VMess)"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}安装节点 (固定隧道)${Reset}"
        echo -e " ${Green}4.${Reset}  VLESS+WS+Argo (Token 模式)"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}服务管理${Reset}"
        echo -e " ${Green}5.${Reset}  启动"
        echo -e " ${Green}6.${Reset}  停止"
        echo -e " ${Green}7.${Reset}  重启"
        echo -e " ${Green}8.${Reset}  查看状态"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}9.${Reset}  查看节点信息"
        echo -e " ${Green}10.${Reset} 查看日志"
        echo -e " ${Green}11.${Reset} 卸载"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回主菜单"
        echo -e "${Green}========================================================${Reset}"
        
        read -p " 请选择 [0-11]: " choice
        
        case "$choice" in
            1) install_vless_ws_argo ;;
            2) install_vmess_ws_argo ;;
            3) install_multi_protocol ;;
            4) install_vless_ws_argo_token ;;
            5) start_argo_token ;;
            6) stop_argo ;;
            7) restart_argo ;;
            8) status_argo ;;
            9) show_node_info ;;
            10) 
                echo -e "${Info} Argo 日志:"
                [ -f "$ARGO_LOG" ] && tail -50 "$ARGO_LOG"
                ;;
            11) uninstall_argo ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# ==================== 主程序 ====================
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    [ -z "$ENV_TYPE" ] && detect_environment 2>/dev/null
    show_argo_menu
fi
