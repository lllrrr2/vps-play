#!/bin/bash
# sing-box Reality 模块 (Namespaced for Mixed Installer)
#
# Copyright (C) 2025 VPS-play Contributors

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/port_manager.sh" ] && source "$VPSPLAY_DIR/utils/port_manager.sh"
[ -f "$VPSPLAY_DIR/utils/process_manager.sh" ] && source "$VPSPLAY_DIR/utils/process_manager.sh"
[ -f "$VPSPLAY_DIR/utils/network.sh" ] && source "$VPSPLAY_DIR/utils/network.sh"

# ==================== 配置 ====================
SINGBOX_DIR="/root/sing-box"
SINGBOX_BIN="$SINGBOX_DIR/sing-box"
SB_TARGET_BIN="/usr/bin/sing-box"
SB_CONFIG_DIR="/etc/sing-box"
SB_CONFIG_FILE="$SB_CONFIG_DIR/config.json"
SB_SERVICE_FILE="/etc/systemd/system/sing-box.service"

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

sb_archAffix() {
    case "$(uname -m)" in
        x86_64 | amd64) echo 'amd64' ;;
        armv8 | arm64 | aarch64) echo 'arm64' ;;
        s390x) echo 's390x' ;;
        *) echo "amd64" ;;
    esac
}

sb_get_latest_version() {
    curl -s https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | sed -n 4p | tr -d ',"' | awk '{print $1}'
}

sb_install_base() {
    # 模拟 Misaka 的依赖安装
    if command -v apt-get &>/dev/null; then
        apt-get update && apt-get -y install curl wget sudo tar openssl
    elif command -v yum &>/dev/null; then
        yum -y update && yum -y install curl wget sudo tar openssl
    fi
}

download_singbox() {
    sb_install_base
    local version=$(sb_get_latest_version)
    if [ -z "$version" ]; then
        echo -e "${Error} 获取版本失败"
        return 1
    fi
    
    local arch=$(sb_archAffix)
    echo -e "${Info} 安装 Sing-box v$version ($arch)..."
    
    # Misaka 使用 rpm/deb 包安装
    if [ -f /etc/redhat-release ]; then
        wget "https://github.com/SagerNet/sing-box/releases/download/v$version/sing-box_${version}_linux_${arch}.rpm" -O sing-box.rpm
        rpm -ivh sing-box.rpm
        rm -f sing-box.rpm
    else
        # Debian/Ubuntu
        wget "https://github.com/SagerNet/sing-box/releases/download/v$version/sing-box_${version}_linux_${arch}.deb" -O sing-box.deb
        dpkg -i sing-box.deb
        rm -f sing-box.deb
    fi
    
    if command -v sing-box &>/dev/null; then
        echo -e "${Info} 安装成功"
        return 0
    else
        echo -e "${Error} 安装失败"
        return 1
    fi
}

sb_generate_uuid() {
    sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid
}

sb_generate_keys() {
    local keys=$(sing-box generate reality-keypair)
    local private_key=$(echo $keys | awk -F " " '{print $2}')
    local public_key=$(echo $keys | awk -F " " '{print $4}')
    local short_id=$(openssl rand -hex 8)
    echo "$private_key $public_key $short_id"
}

# ==================== 安装逻辑 (Reality Only) ====================

install_reality() {
    echo -e "${Cyan}========== 安装 Sing-box Reality (Misaka Logic) ==========${Reset}"
    
    # 1. 安装 Sing-box
    if ! command -v sing-box &>/dev/null; then
        download_singbox || return 1
    fi
    
    # 2. 配置参数
    read -p "设置端口 [回车随机]: " port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    
    # 检查端口占用 (简单检查)
    while ss -tunlp | grep -q ":$port "; do
        echo -e "${Warning} 端口 $port 被占用"
        port=$(shuf -i 2000-65535 -n 1)
        echo -e "${Info} 更换为 $port"
    done
    
    read -rp "请输入 UUID [回车生成]: " uuid
    [[ -z $uuid ]] && uuid=$(sb_generate_uuid)
    
    read -rp "请输入回落域名 [默认 www.sega.com]: " dest_server
    [[ -z $dest_server ]] && dest_server="www.sega.com"
    
    # 生成 Reality Key
    read -r private_key public_key short_id <<< $(sb_generate_keys)
    
    echo -e "${Info} UUID: $uuid"
    echo -e "${Info} 端口: $port"
    echo -e "${Info} 回落: $dest_server"
    echo -e "${Info} ShortId: $short_id"
    
    # 3. 生成配置
    mkdir -p "$SB_CONFIG_DIR"
    rm -f "$SB_CONFIG_FILE"
    
    # Misaka 风格配置
    cat << EOF > "$SB_CONFIG_FILE"
{
    "log": {
        "level": "info",
        "timestamp": true
    },
    "inbounds": [
        {
            "type": "vless",
            "tag": "vless-in",
            "listen": "::",
            "listen_port": $port,
            "sniff": true,
            "sniff_override_destination": true,
            "users": [
                {
                    "uuid": "$uuid",
                    "flow": "xtls-rprx-vision"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "$dest_server",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "$dest_server",
                        "server_port": 443
                    },
                    "private_key": "$private_key",
                    "short_id": [
                        "$short_id"
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct"
        },
        {
            "type": "block",
            "tag": "block"
        }
    ]
}
EOF

    # 4. 启动服务 (systemd)
    systemctl daemon-reload
    systemctl enable sing-box
    systemctl restart sing-box
    
    # 5. 生成分享链接
    local ip=$(curl -s4 ip.sb || curl -s6 ip.sb)
    local share_link="vless://$uuid@$ip:$port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$dest_server&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#Misaka-Reality"
    
    if systemctl is-active --quiet sing-box; then
        echo -e "${Green}Sing-box Reality 启动成功!${Reset}"
        echo -e ""
        echo -e "分享链接:"
        echo -e "${Cyan}$share_link${Reset}"
        echo -e ""
        echo -e "Clash Meta 片段:"
        echo -e "- name: Misaka-Reality"
        echo -e "  type: vless"
        echo -e "  server: $ip"
        echo -e "  port: $port"
        echo -e "  uuid: $uuid"
        echo -e "  network: tcp"
        echo -e "  tls: true"
        echo -e "  udp: true"
        echo -e "  flow: xtls-rprx-vision"
        echo -e "  servername: $dest_server"
        echo -e "  reality-opts:"
        echo -e "    public-key: $public_key"
        echo -e "    short-id: $short_id"
        echo -e "  client-fingerprint: chrome"
    else
        echo -e "${Error} 启动失败，请检查日志"
    fi
}

uninstall_reality() {
    echo -e "${Warning} 卸载 Sing-box Reality..."
    systemctl stop sing-box
    systemctl disable sing-box
    
    if [ -f /etc/redhat-release ]; then
        rpm -e sing-box
    else
        dpkg -r sing-box
    fi
    
    rm -rf "$SB_CONFIG_DIR"
    echo -e "${Green}卸载完成${Reset}"
}

sb_menu() {
    clear
    echo -e "${Cyan}========== Sing-box Reality 管理 (Misaka Logic) ==========${Reset}"
    echo -e " 1. 安装 Reality"
    echo -e " 2. 卸载 Reality"
    echo -e " 3. 查看状态"
    echo -e " 4. 重启服务"
    echo -e " 5. 查看配置"
    echo -e " 0. 返回"
    echo -e "=================================================="
    read -p "请选择: " choice

    case "$choice" in
        1) install_reality ;;
        2) uninstall_reality ;;
        3) systemctl status sing-box ;;
        4) systemctl restart sing-box && echo -e "${Info} 已重启" ;;
        5) [ -f "$SB_CONFIG_FILE" ] && cat "$SB_CONFIG_FILE" || echo -e "${Error} 配置文件不存在" ;;
        0) return ;;
        *) echo -e "${Error} 无效选择" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    sb_menu
fi
