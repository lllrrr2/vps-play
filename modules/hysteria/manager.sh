#!/bin/bash
# Hysteria 2 模块 (Namespaced for Mixed Installer)
#
# Copyright (C) 2025 VPS-play Contributors

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/port_manager.sh" ] && source "$VPSPLAY_DIR/utils/port_manager.sh"
[ -f "$VPSPLAY_DIR/utils/process_manager.sh" ] && source "$VPSPLAY_DIR/utils/process_manager.sh"
[ -f "$VPSPLAY_DIR/utils/network.sh" ] && source "$VPSPLAY_DIR/utils/network.sh"

# ==================== 配置 ====================
HY2_BIN="/usr/local/bin/hysteria"
HY2_CONFIG_DIR="/etc/hysteria"
HY2_CONFIG_FILE="$HY2_CONFIG_DIR/config.yaml"
HY2_SERVICE_FILE="/etc/systemd/system/hysteria-server.service"

# 颜色定义 (如果没有定义则定义)
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

hy2_get_latest_version() {
    curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4
}

hy2_download_binary() {
    local version=$1
    local arch=$(uname -m)
    local filename=""

    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) echo -e "${Error} 不支持的架构: $arch"; return 1 ;;
    esac

    filename="hysteria-linux-$arch"
    url="https://github.com/apernet/hysteria/releases/download/$version/$filename"

    echo -e "${Info} 下载 Hysteria $version ($arch)..."
    curl -L -o "$filename" "$url"
    
    if [ $? -eq 0 ]; then
        chmod +x "$filename"
        mv "$filename" "$HY2_BIN"
        echo -e "${Info} 安装成功: $HY2_BIN"
        return 0
    else
        echo -e "${Error} 下载失败"
        rm -f "$filename"
        return 1
    fi
}

hy2_generate_password() {
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16
}

# ==================== 安装逻辑 ====================

install_hysteria() {
    echo -e "${Cyan}========== 安装 Hysteria 2 (原生) ==========${Reset}"
    
    # 1. 下载二进制
    local version=$(hy2_get_latest_version)
    if [ -z "$version" ]; then
        echo -e "${Error} 无法获取最新版本"
        return 1
    fi
    hy2_download_binary "$version" || return 1

    # 2. 配置参数
    echo -e "${Info} 配置参数..."
    read -p "请输入端口 [443]: " port
    port=${port:-443}
    
    # 端口跳跃
    read -p "是否启用端口跳跃 (Port Hopping)? [y/N]: " enable_hop
    local hopping=""
    if [[ "$enable_hop" =~ ^[Yy]$ ]]; then
        read -p "请输入跳跃端口范围 (例如 10000-20000): " hop_range
        if [ -n "$hop_range" ]; then
            hopping=":$hop_range"
        fi
    fi
    
    # 域名与证书 (内置 ACME)
    read -p "请输入域名 (用于申请证书): " domain
    read -p "请输入邮箱 (用于申请证书): " email
    if [ -z "$domain" ] || [ -z "$email" ]; then
        echo -e "${Error} 域名和邮箱不能为空"
        return 1
    fi

    local password=$(hy2_generate_password)
    echo -e "${Info} 生成随机密码: $password"

    # 3. 生成配置
    mkdir -p "$HY2_CONFIG_DIR"
    
    # 主要监听配置
    local listen_config=""
    if [ -n "$hopping" ]; then
         listen_config="listen: \":$port$hopping\""
    else
         listen_config="listen: \":$port\""
    fi

    cat > "$HY2_CONFIG_FILE" <<EOF
$listen_config

acme:
  domains:
    - $domain
  email: $email

auth:
  type: password
  password: $password

masquerade:
  type: proxy
  proxy:
    url: https://news.ycombinator.com/
    rewriteHost: true

bandwidth:
  up: 100 mbps
  down: 100 mbps

ignoreClientBandwidth: false
EOF

    # 4. 创建服务
    cat > "$HY2_SERVICE_FILE" <<EOF
[Unit]
Description=Hysteria Server Service (config.yaml)
After=network.target

[Service]
Type=simple
ExecStart=$HY2_BIN server --config $HY2_CONFIG_FILE
WorkingDirectory=$HY2_CONFIG_DIR
User=root
Group=root
Environment=HYSTERIA_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable hysteria-server
    systemctl start hysteria-server

    if systemctl is-active --quiet hysteria-server; then
        echo -e "${Green}Hysteria 2 启动成功!${Reset}"
        echo -e ""
        echo -e "配置信息:"
        echo -e "  端口: $port"
        echo -e "  跳跃: ${hopping:-无}"
        echo -e "  域名: $domain"
        echo -e "  密码: $password"
        echo -e "  配置: $HY2_CONFIG_FILE"
        echo -e ""
        # 尝试生成分享链接或提示
        echo -e "v2rayN/NekoBox 链接格式参考:"
        echo -e "hysteria2://$password@$domain:$port/?sni=$domain&alpn=h3"
    else
        echo -e "${Error} 服务启动失败，请检查日志: journalctl -u hysteria-server"
    fi
}

uninstall_hysteria() {
    echo -e "${Warning} 正在卸载 Hysteria 2..."
    systemctl stop hysteria-server
    systemctl disable hysteria-server
    rm -f "$HY2_SERVICE_FILE"
    systemctl daemon-reload
    rm -f "$HY2_BIN"
    rm -rf "$HY2_CONFIG_DIR"
    echo -e "${Green}卸载完成${Reset}"
}

# ==================== 菜单 ====================

hy2_menu() {
    clear
    echo -e "${Cyan}========== Hysteria 2 管理 (Misaka Logic) ==========${Reset}"
    echo -e " 1. 安装 Hysteria 2"
    echo -e " 2. 卸载 Hysteria 2"
    echo -e " 3. 查看状态"
    echo -e " 4. 重启服务"
    echo -e " 5. 查看配置"
    echo -e " 0. 返回"
    echo -e "=================================================="
    read -p "请选择: " choice

    case "$choice" in
        1) install_hysteria ;;
        2) uninstall_hysteria ;;
        3) systemctl status hysteria-server ;;
        4) systemctl restart hysteria-server && echo -e "${Info} 已重启" ;;
        5) [ -f "$HY2_CONFIG_FILE" ] && cat "$HY2_CONFIG_FILE" || echo -e "${Error} 配置文件不存在" ;;
        0) return ;;
        *) echo -e "${Error} 无效选择" ;;
    esac
}

# 如果直接运行脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    hy2_menu
fi
