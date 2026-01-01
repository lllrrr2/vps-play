#!/bin/bash
# TUIC v5 模块 (Namespaced for Mixed Installer)
#
# Copyright (C) 2025 VPS-play Contributors

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/port_manager.sh" ] && source "$VPSPLAY_DIR/utils/port_manager.sh"
[ -f "$VPSPLAY_DIR/utils/process_manager.sh" ] && source "$VPSPLAY_DIR/utils/process_manager.sh"
[ -f "$VPSPLAY_DIR/utils/network.sh" ] && source "$VPSPLAY_DIR/utils/network.sh"


# ==================== 配置 ====================
TUIC_BIN="/usr/local/bin/tuic"
TUIC_CONFIG_DIR="/etc/tuic"
TUIC_CONFIG_FILE="$TUIC_CONFIG_DIR/tuic.json"
TUIC_SERVICE_FILE="/etc/systemd/system/tuic.service"
TUIC_CERT_DIR="/root/cert" # Misaka 这里用的是 /root/cert，我们保持一致或用 /etc/tuic/cert

# 颜色定义
if [ -z "$Green" ]; then
    Red="\033[31m"
    Green="\033[32m"
    Yellow="\033[33m"
    Cyan="\033[36m"
    Reset="\033[0m"
    Info="${Green}[信息]${Reset}"
    Error="${Red}[错误]${Reset}"
    Warning="${Yellow}[警告]${Reset}"
fi

# ==================== 辅助函数 ====================

tuic_get_latest_version() {
    curl -s https://api.github.com/repos/eaimty/tuic/releases/latest | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4
}

tuic_download_binary() {
    local arch=$(uname -m)
    local filename=""

    case "$arch" in
        x86_64) arch="x86_64-unknown-linux-gnu" ;;
        aarch64) arch="aarch64-unknown-linux-gnu" ;;
        *) echo -e "${Error} 不支持的架构: $arch"; return 1 ;;
    esac
    
    local version=$(tuic_get_latest_version)
    if [ -z "$version" ]; then
        echo -e "${Error} 无法获取版本"
        return 1
    fi
    
    local dl_filename="tuic-server-${version#v}-$arch"
    local url="https://github.com/eaimty/tuic/releases/download/$version/$dl_filename"
    
    echo -e "${Info} 下载 TUIC $version..."
    curl -L -o tuic_bin "$url"
    
    if [ $? -eq 0 ]; then
        chmod +x tuic_bin
        mv tuic_bin "$TUIC_BIN"
        echo -e "${Info} 安装成功: $TUIC_BIN"
        return 0
    else
        echo -e "${Error} 下载失败"
        rm -f tuic_bin
        return 1
    fi
}

tuic_generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

tuic_generate_password() {
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 8
}

# ==================== 证书逻辑 (Misaka ACME) ====================
tuic_install_acme_cert() {
    local domain=$1
    
    if ! command -v socat &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            apt-get install -y socat
        elif command -v yum &>/dev/null; then
            yum install -y socat
        fi
    fi
    
    if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        echo -e "${Info} 安装 acme.sh..."
        curl https://get.acme.sh | sh -s email=hacker@gmail.com
    fi
    
    mkdir -p "$TUIC_CERT_DIR"
    
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    
    echo -e "${Info} 申请证书: $domain"
    # 使用 standalone 模式，需要 80 端口空闲
    if lsof -i :80 &>/dev/null; then
        echo -e "${Warning} 80 端口被占用，尝试停止 nginx/caddy..."
        systemctl stop nginx 2>/dev/null
        systemctl stop caddy 2>/dev/null
    fi
    
    ~/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 --force
    
    ~/.acme.sh/acme.sh --install-cert -d "$domain" \
        --key-file "$TUIC_CERT_DIR/private.key" \
        --fullchain-file "$TUIC_CERT_DIR/cert.crt" \
        --ecc
        
    if [ -f "$TUIC_CERT_DIR/cert.crt" ] && [ -f "$TUIC_CERT_DIR/private.key" ]; then
        echo -e "${Info} 证书申请成功"
        return 0
    else
        echo -e "${Error} 证书申请失败"
        return 1
    fi
}


# ==================== 安装逻辑 ====================

install_tuic() {
    echo -e "${Cyan}========== 安装 TUIC v5 (原生) ==========${Reset}"
    
    # 0. 检查依赖
    if ! command -v curl &>/dev/null || ! command -v socat &>/dev/null; then
        echo -e "${Info} 安装依赖..."
        if command -v apt-get &>/dev/null; then
            apt-get update && apt-get install -y curl wget socat tar openssl
        elif command -v yum &>/dev/null; then
            yum update -y && yum install -y curl wget socat tar openssl
        fi
    fi
    
    # 1. 下载
    tuic_download_binary || return 1
    
    # 2. 证书
    read -p "请输入域名 (用于申请证书): " domain
    if [ -z "$domain" ]; then
        echo -e "${Error} 域名不能为空"
        return 1
    fi
    tuic_install_acme_cert "$domain" || return 1
    
    # 3. 配置参数
    if [ -n "$TUIC_PORT" ]; then
        echo -e "${Info} 使用预设端口: $TUIC_PORT"
        port="$TUIC_PORT"
    else
        read -p "请输入端口 [8443]: " port
        port=${port:-8443}
    fi
    
    local uuid=$(tuic_generate_uuid)
    local password=$(tuic_generate_password)
    echo -e "${Info} 生成 UUID: $uuid"
    echo -e "${Info} 生成 密码: $password"
    
    read -p "拥塞控制 (bbr/cubic/new_reno) [bbr]: " congestion
    congestion=${congestion:-bbr}
    
    # 4. 生成配置
    mkdir -p "$TUIC_CONFIG_DIR"
    
    cat > "$TUIC_CONFIG_FILE" <<EOF
{
    "server": {
        "listen": "[::]:$port",
        "cert": "$TUIC_CERT_DIR/cert.crt",
        "key": "$TUIC_CERT_DIR/private.key",
        "congestion_controller": "$congestion",
        "max_idle_time": 15000,
        "authentication_timeout": 1000,
        "alpn": ["h3"],
        "max_udp_relay_packet_size": 1500
    },
    "users": {
        "$uuid": "$password"
    }
}
EOF

    # 5. 创建服务
    cat > "$TUIC_SERVICE_FILE" <<EOF
[Unit]
Description=tuic Service
Documentation=https://github.com/eaimty/tuic
After=network.target

[Service]
User=root
ExecStart=$TUIC_BIN -c $TUIC_CONFIG_FILE
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable tuic
    systemctl start tuic
    
    if systemctl is-active --quiet tuic; then
        echo -e "${Green}TUIC v5 启动成功!${Reset}"
        echo -e ""
        echo -e "配置信息:"
        echo -e "  端口: $port"
        echo -e "  域名: $domain"
        echo -e "  UUID: $uuid"
        echo -e "  密码: $password"
        echo -e "  拥塞: $congestion"
        echo -e ""
        echo -e "Clash Meta 参考片段:"
        echo -e "- name: tuic"
        echo -e "  type: tuic"
        echo -e "  server: $domain"
        echo -e "  port: $port"
        echo -e "  uuid: $uuid"
        echo -e "  password: $password"
        echo -e "  alpn: [h3]"
        echo -e "  congestion-controller: $congestion"
        echo -e "  udp-relay-mode: native"
    else
        echo -e "${Error} 服务启动失败"
    fi
}

uninstall_tuic() {
    echo -e "${Warning} 卸载 TUIC..."
    systemctl stop tuic
    systemctl disable tuic
    rm -f "$TUIC_SERVICE_FILE"
    systemctl daemon-reload
    rm -f "$TUIC_BIN"
    rm -rf "$TUIC_CONFIG_DIR"
    echo -e "${Green}卸载完成${Reset}"
}

tuic_menu() {
    clear
    echo -e "${Cyan}========== TUIC v5 管理 (Misaka Logic) ==========${Reset}"
    echo -e " 1. 安装 TUIC v5"
    echo -e " 2. 卸载 TUIC v5"
    echo -e " 3. 查看状态"
    echo -e " 4. 重启服务"
    echo -e " 5. 查看配置"
    echo -e " 0. 返回"
    echo -e "=================================================="
    read -p "请选择: " choice

    case "$choice" in
        1) install_tuic ;;
        2) uninstall_tuic ;;
        3) systemctl status tuic ;;
        4) systemctl restart tuic && echo -e "${Info} 已重启" ;;
        5) [ -f "$TUIC_CONFIG_FILE" ] && cat "$TUIC_CONFIG_FILE" || echo -e "${Error} 配置文件不存在" ;;
        0) return ;;
        *) echo -e "${Error} 无效选择" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    tuic_menu
fi
