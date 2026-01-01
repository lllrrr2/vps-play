#!/bin/bash
# Sing-box Reality 模块 (对齐 Misaka reality.sh)
#
# Copyright (C) 2025 VPS-play Contributors

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"

# ==================== 配置 ====================
SB_CONFIG_DIR="/etc/sing-box"
SB_CONFIG_FILE="$SB_CONFIG_DIR/config.json"
SB_CLIENT_DIR="/root/sing-box"

# 颜色定义
Red="\033[31m"
Green="\033[32m"
Yellow="\033[33m"
Cyan="\033[36m"
Reset="\033[0m"
Info="${Green}[信息]${Reset}"
Error="${Red}[错误]${Reset}"
Warning="${Yellow}[警告]${Reset}"

# ==================== 系统检测 ====================
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Alpine")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "apk update -f")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "apk add -f")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove" "apk del -f")

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
        SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
    fi
done

sb_archAffix() {
    case "$(uname -m)" in
        x86_64 | amd64) echo 'amd64' ;;
        armv8 | arm64 | aarch64) echo 'arm64' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${Error} 不支持的CPU架构" && exit 1 ;;
    esac
}

# 杀死占用端口的进程
sb_kill_port_process() {
    local port=$1
    local pids=$(ss -tunlp | grep ":$port " | grep -oP 'pid=\K[0-9]+')
    if [ -n "$pids" ]; then
        echo -e "${Warning} 检测到端口 $port 被占用，正在释放..."
        for pid in $pids; do
            kill -9 $pid 2>/dev/null && echo -e "${Info} 已杀死进程 $pid"
        done
        sleep 1
    fi
}

sb_install_base() {
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl wget sudo tar openssl
}

# ==================== 安装 Sing-box ====================
sb_install_singbox() {
    sb_install_base
    
    last_version=$(curl -s https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | sed -n 4p | tr -d ',"' | awk '{print $1}')
    if [[ -z $last_version ]]; then
        echo -e "${Error} 获取版本信息失败，请检查VPS的网络状态"
        return 1
    fi
    
    echo -e "${Info} 安装 Sing-box v$last_version..."
    
    if [[ $SYSTEM == "CentOS" ]]; then
        wget https://github.com/SagerNet/sing-box/releases/download/v"$last_version"/sing-box_"$last_version"_linux_$(sb_archAffix).rpm -O sing-box.rpm
        rpm -ivh sing-box.rpm
        rm -f sing-box.rpm
    else
        wget https://github.com/SagerNet/sing-box/releases/download/v"$last_version"/sing-box_"$last_version"_linux_$(sb_archAffix).deb -O sing-box.deb
        dpkg -i sing-box.deb
        rm -f sing-box.deb
    fi
    
    if [[ -f "/etc/systemd/system/sing-box.service" ]] || command -v sing-box &>/dev/null; then
        echo -e "${Info} Sing-box 安装成功"
        return 0
    else
        echo -e "${Error} Sing-box 安装失败"
        return 1
    fi
}

# ==================== 安装 Reality ====================
install_reality() {
    echo -e "${Cyan}========== 安装 Sing-box Reality (Misaka Logic) ==========${Reset}"
    
    # 清理旧配置
    echo -e "${Info} 清理旧配置文件..."
    systemctl stop sing-box >/dev/null 2>&1
    systemctl disable sing-box >/dev/null 2>&1
    rm -rf "$SB_CONFIG_DIR" "$SB_CLIENT_DIR"
    
    # 安装 Sing-box
    if ! command -v sing-box &>/dev/null; then
        sb_install_singbox || return 1
    fi
    
    # 端口配置
    if [ -n "$SB_PORT" ]; then
        echo -e "${Info} 使用预设端口: $SB_PORT"
        sb_port="$SB_PORT"
    else
        read -p "设置 Sing-box 端口 [1-65535]（回车则随机分配端口）：" sb_port
        [[ -z $sb_port ]] && sb_port=$(shuf -i 2000-65535 -n 1)
        until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$sb_port") ]]; do
            echo -e "${Error} $sb_port 端口已被占用"
            read -p "设置 Sing-box 端口 [1-65535]（回车则随机分配端口）：" sb_port
            [[ -z $sb_port ]] && sb_port=$(shuf -i 2000-65535 -n 1)
        done
    fi
    
    # UUID
    read -rp "请输入 UUID [可留空待脚本生成]: " sb_uuid
    [[ -z $sb_uuid ]] && sb_uuid=$(sing-box generate uuid)
    
    # 回落域名
    read -rp "请输入配置回落的域名 [默认世嘉官网]: " sb_dest_server
    [[ -z $sb_dest_server ]] && sb_dest_server="www.sega.com"
    
    # 释放端口
    sb_kill_port_process $sb_port
    
    # Reality 密钥
    sb_short_id=$(openssl rand -hex 8)
    sb_keys=$(sing-box generate reality-keypair)
    sb_private_key=$(echo $sb_keys | awk -F " " '{print $2}')
    sb_public_key=$(echo $sb_keys | awk -F " " '{print $4}')
    
    echo -e "${Info} UUID: $sb_uuid"
    echo -e "${Info} 端口: $sb_port"
    echo -e "${Info} 回落: $sb_dest_server"
    echo -e "${Info} ShortId: $sb_short_id"
    
    # 生成配置文件
    rm -f "$SB_CONFIG_FILE"
    cat << EOF > "$SB_CONFIG_FILE"
{
    "log": {
        "level": "trace",
        "timestamp": true
    },
    "inbounds": [
        {
            "type": "vless",
            "tag": "vless-in",
            "listen": "::",
            "listen_port": $sb_port,
            "sniff": true,
            "sniff_override_destination": true,
            "users": [
                {
                    "uuid": "$sb_uuid",
                    "flow": "xtls-rprx-vision"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "$sb_dest_server",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "$sb_dest_server",
                        "server_port": 443
                    },
                    "private_key": "$sb_private_key",
                    "short_id": [
                        "$sb_short_id"
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct"
        }
    ]
}
EOF
    
    # 获取真实 IP
    warp_v4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    warp_v6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $warp_v4 =~ on|plus ]] || [[ $warp_v6 =~ on|plus ]]; then
        systemctl stop warp-go >/dev/null 2>&1
        wg-quick down wgcf >/dev/null 2>&1
        sb_IP=$(curl -ks4m8 -A Mozilla https://api.ip.sb/geoip | grep -oP '"ip":\s*"\K[^"]+') || sb_IP=$(curl -ks6m8 -A Mozilla https://api.ip.sb/geoip | grep -oP '"ip":\s*"\K[^"]+')
        systemctl start warp-go >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
    else
        sb_IP=$(curl -ks4m8 -A Mozilla https://api.ip.sb/geoip | grep -oP '"ip":\s*"\K[^"]+') || sb_IP=$(curl -ks6m8 -A Mozilla https://api.ip.sb/geoip | grep -oP '"ip":\s*"\K[^"]+')
    fi
    
    mkdir -p "$SB_CLIENT_DIR"
    
    # 生成分享链接
    sb_share_link="vless://$sb_uuid@$sb_IP:$sb_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$sb_dest_server&fp=chrome&pbk=$sb_public_key&sid=$sb_short_id&type=tcp&headerType=none#Misaka-Reality"
    echo "$sb_share_link" > "$SB_CLIENT_DIR/share-link.txt"
    
    # Clash Meta 配置
    cat << EOF > "$SB_CLIENT_DIR/clash-meta.yaml"
mixed-port: 7890
external-controller: 127.0.0.1:9090
allow-lan: false
mode: rule
log-level: debug
ipv6: true
dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  nameserver:
    - 8.8.8.8
    - 1.1.1.1
proxies:
  - name: Misaka-Reality
    type: vless
    server: $sb_IP
    port: $sb_port
    uuid: $sb_uuid
    network: tcp
    tls: true
    udp: true
    xudp: true
    flow: xtls-rprx-vision
    servername: $sb_dest_server
    reality-opts:
      public-key: "$sb_public_key"
      short-id: "$sb_short_id"
    client-fingerprint: chrome
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Misaka-Reality
rules:
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
EOF
    
    # 启动服务
    systemctl start sing-box >/dev/null 2>&1
    systemctl enable sing-box >/dev/null 2>&1
    
    if [[ -n $(systemctl status sing-box 2>/dev/null | grep -w active) && -f "$SB_CONFIG_FILE" ]]; then
        echo -e "${Green}Sing-box Reality 服务启动成功${Reset}"
        echo ""
        echo -e "${Yellow}分享链接已保存到 $SB_CLIENT_DIR/share-link.txt${Reset}"
        echo -e "${Cyan}$sb_share_link${Reset}"
        echo ""
        echo -e "${Yellow}Clash Meta 配置文件已保存到 $SB_CLIENT_DIR/clash-meta.yaml${Reset}"
    else
        echo -e "${Error} 服务启动失败，请运行 systemctl status sing-box 查看"
    fi
}

uninstall_reality() {
    echo -e "${Warning} 正在卸载 Sing-box Reality..."
    systemctl stop sing-box >/dev/null 2>&1
    systemctl disable sing-box >/dev/null 2>&1
    ${PACKAGE_UNINSTALL[int]} sing-box
    rm -rf "$SB_CLIENT_DIR"
    echo -e "${Green}Sing-box Reality 已卸载${Reset}"
}

sb_change_port() {
    old_port=$(cat "$SB_CONFIG_FILE" | grep listen_port | awk -F ": " '{print $2}' | sed "s/,//g")
    
    read -p "设置 Sing-box 端口 [1-65535]（回车则随机分配端口）：" sb_port
    [[ -z $sb_port ]] && sb_port=$(shuf -i 2000-65535 -n 1)
    
    sed -i "s/$old_port/$sb_port/g" "$SB_CONFIG_FILE"
    sed -i "s/$old_port/$sb_port/g" "$SB_CLIENT_DIR/share-link.txt"
    
    systemctl restart sing-box
    echo -e "${Info} 端口已修改为 $sb_port"
}

sb_change_uuid() {
    old_uuid=$(cat "$SB_CONFIG_FILE" | grep uuid | awk -F ": " '{print $2}' | sed 's/"//g' | sed "s/,//g")
    
    read -rp "请输入 UUID [可留空待脚本生成]: " sb_uuid
    [[ -z $sb_uuid ]] && sb_uuid=$(sing-box generate uuid)
    
    sed -i "s/$old_uuid/$sb_uuid/g" "$SB_CONFIG_FILE"
    sed -i "s/$old_uuid/$sb_uuid/g" "$SB_CLIENT_DIR/share-link.txt"
    
    systemctl restart sing-box
    echo -e "${Info} UUID 已修改为 $sb_uuid"
}

sb_change_dest() {
    old_dest=$(cat "$SB_CONFIG_FILE" | grep server | sed -n 1p | awk -F ": " '{print $2}' | sed 's/"//g' | sed "s/,//g")
    
    read -rp "请输入配置回落的域名 [默认世嘉官网]: " sb_dest_server
    [[ -z $sb_dest_server ]] && sb_dest_server="www.sega.com"
    
    sed -i "s/$old_dest/$sb_dest_server/g" "$SB_CONFIG_FILE"
    sed -i "s/$old_dest/$sb_dest_server/g" "$SB_CLIENT_DIR/share-link.txt"
    
    systemctl restart sing-box
    echo -e "${Info} 回落域名已修改为 $sb_dest_server"
}

sb_change_conf() {
    echo -e "${Cyan}Sing-box 配置变更选择如下:${Reset}"
    echo -e " ${Green}1.${Reset} 修改端口"
    echo -e " ${Green}2.${Reset} 修改UUID"
    echo -e " ${Green}3.${Reset} 修改回落域名"
    echo ""
    read -p "请选择操作 [1-3]: " confAnswer
    case $confAnswer in
        1) sb_change_port ;;
        2) sb_change_uuid ;;
        3) sb_change_dest ;;
        *) exit 1 ;;
    esac
}

sb_show_conf() {
    if [[ -f "$SB_CLIENT_DIR/share-link.txt" ]]; then
        echo -e "${Yellow}分享链接:${Reset}"
        cat "$SB_CLIENT_DIR/share-link.txt"
    else
        echo -e "${Error} 配置文件不存在"
    fi
}

sb_menu() {
    clear
    echo -e "${Cyan}========== Sing-box Reality 管理 (Misaka Logic) ==========${Reset}"
    echo -e " ${Green}1.${Reset} 安装 Sing-box Reality"
    echo -e " ${Green}2.${Reset} ${Red}卸载 Sing-box Reality${Reset}"
    echo " -------------"
    echo -e " ${Green}3.${Reset} 启动 Sing-box"
    echo -e " ${Green}4.${Reset} 停止 Sing-box"
    echo -e " ${Green}5.${Reset} 重启 Sing-box"
    echo " -------------"
    echo -e " ${Green}6.${Reset} 修改配置"
    echo -e " ${Green}7.${Reset} 查看配置信息"
    echo -e " ${Green}0.${Reset} 返回"
    echo "=================================================="
    read -p "请选择: " choice

    case "$choice" in
        1) install_reality ;;
        2) uninstall_reality ;;
        3) systemctl start sing-box && systemctl enable sing-box && echo -e "${Info} 已启动" ;;
        4) systemctl stop sing-box && systemctl disable sing-box && echo -e "${Info} 已停止" ;;
        5) systemctl restart sing-box && echo -e "${Info} 已重启" ;;
        6) sb_change_conf ;;
        7) sb_show_conf ;;
        0) return ;;
        *) echo -e "${Error} 无效选择" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    sb_menu
fi
