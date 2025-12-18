#!/bin/bash
# WARP 模块 - VPS-play
# Cloudflare WARP 代理管理
# 参考: ygkkk/CFwarp

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

source "$VPSPLAY_DIR/utils/env_detect.sh" 2>/dev/null
source "$VPSPLAY_DIR/utils/process_manager.sh" 2>/dev/null
source "$VPSPLAY_DIR/utils/network.sh" 2>/dev/null

# ==================== 配置 ====================
WARP_DIR="$HOME/.vps-play/warp"
WGCF_BIN="$WARP_DIR/wgcf"
WGCF_CONF="$WARP_DIR/wgcf-profile.conf"
WARP_LOG="$WARP_DIR/warp.log"

mkdir -p "$WARP_DIR"

# WGCF 版本
WGCF_VERSION="2.2.22"

# ==================== 检测当前 IP ====================
show_current_ip() {
    echo -e "${Info} 检测当前 IP..."
    echo -e ""
    
    local ipv4=$(curl -s4m5 ip.sb 2>/dev/null || echo "无法获取")
    local ipv6=$(curl -s6m5 ip.sb 2>/dev/null || echo "无法获取")
    
    echo -e " IPv4: ${Cyan}${ipv4}${Reset}"
    echo -e " IPv6: ${Cyan}${ipv6}${Reset}"
    
    # 检测 IP 归属
    if [ "$ipv4" != "无法获取" ]; then
        local ip_info=$(curl -s "https://ipinfo.io/${ipv4}/json" 2>/dev/null)
        local country=$(echo "$ip_info" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
        local org=$(echo "$ip_info" | grep -o '"org":"[^"]*"' | cut -d'"' -f4)
        echo -e " 归属: ${Cyan}${country} - ${org}${Reset}"
    fi
}

# ==================== 下载 wgcf ====================
download_wgcf() {
    echo -e "${Info} 下载 wgcf..."
    
    local os_type="linux"
    local arch_type="amd64"
    
    case "$ARCH" in
        amd64) arch_type="amd64" ;;
        arm64) arch_type="arm64" ;;
        armv7) arch_type="armv7" ;;
    esac
    
    local download_url="https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VERSION}/wgcf_${WGCF_VERSION}_${os_type}_${arch_type}"
    
    cd "$WARP_DIR"
    
    if command -v curl &>/dev/null; then
        curl -sL "$download_url" -o wgcf
    elif command -v wget &>/dev/null; then
        wget -q "$download_url" -O wgcf
    fi
    
    chmod +x wgcf
    
    if [ -f "$WGCF_BIN" ]; then
        echo -e "${Info} wgcf 下载完成"
    else
        echo -e "${Error} wgcf 下载失败"
        return 1
    fi
}

# ==================== 注册 WARP 账户 ====================
register_warp() {
    if [ ! -f "$WGCF_BIN" ]; then
        echo -e "${Error} 请先下载 wgcf"
        return 1
    fi
    
    cd "$WARP_DIR"
    
    echo -e "${Info} 注册 WARP 账户..."
    
    # 检查是否已有账户
    if [ -f "$WARP_DIR/wgcf-account.toml" ]; then
        echo -e "${Warning} 已存在 WARP 账户"
        read -p "是否重新注册? [y/N]: " re_register
        [[ ! $re_register =~ ^[Yy]$ ]] && return 0
        rm -f "$WARP_DIR/wgcf-account.toml"
    fi
    
    # 注册
    $WGCF_BIN register --accept-tos
    
    if [ -f "$WARP_DIR/wgcf-account.toml" ]; then
        echo -e "${Info} WARP 账户注册成功"
    else
        echo -e "${Error} 注册失败"
        return 1
    fi
}

# ==================== 生成配置 ====================
generate_config() {
    if [ ! -f "$WARP_DIR/wgcf-account.toml" ]; then
        echo -e "${Error} 请先注册 WARP 账户"
        return 1
    fi
    
    cd "$WARP_DIR"
    
    echo -e "${Info} 生成 WireGuard 配置..."
    
    $WGCF_BIN generate
    
    if [ -f "$WGCF_CONF" ]; then
        echo -e "${Info} 配置生成成功: $WGCF_CONF"
        
        # 显示配置
        echo -e ""
        echo -e "${Cyan}========================================${Reset}"
        cat "$WGCF_CONF"
        echo -e "${Cyan}========================================${Reset}"
    else
        echo -e "${Error} 配置生成失败"
        return 1
    fi
}

# ==================== 优化配置 ====================
optimize_config() {
    if [ ! -f "$WGCF_CONF" ]; then
        echo -e "${Error} 请先生成配置"
        return 1
    fi
    
    echo -e ""
    echo -e "${Info} 选择 WARP 模式:"
    echo -e " ${Green}1.${Reset} IPv4 only (仅替换 IPv4)"
    echo -e " ${Green}2.${Reset} IPv6 only (仅替换 IPv6)"
    echo -e " ${Green}3.${Reset} IPv4 + IPv6 (全局模式)"
    echo -e " ${Green}4.${Reset} 自定义 AllowedIPs"
    
    read -p "请选择 [1-4]: " mode
    
    case "$mode" in
        1)
            # IPv4 only
            sed -i 's/AllowedIPs = .*/AllowedIPs = 0.0.0.0\/0/' "$WGCF_CONF"
            echo -e "${Info} 已配置为 IPv4 only 模式"
            ;;
        2)
            # IPv6 only
            sed -i 's/AllowedIPs = .*/AllowedIPs = ::\/0/' "$WGCF_CONF"
            echo -e "${Info} 已配置为 IPv6 only 模式"
            ;;
        3)
            # 全局模式
            sed -i 's/AllowedIPs = .*/AllowedIPs = 0.0.0.0\/0, ::\/0/' "$WGCF_CONF"
            echo -e "${Info} 已配置为全局模式"
            ;;
        4)
            read -p "输入 AllowedIPs: " allowed_ips
            sed -i "s/AllowedIPs = .*/AllowedIPs = $allowed_ips/" "$WGCF_CONF"
            echo -e "${Info} 已更新 AllowedIPs"
            ;;
    esac
    
    # 添加 MTU 优化
    if ! grep -q "MTU" "$WGCF_CONF"; then
        sed -i '/\[Peer\]/i MTU = 1280' "$WGCF_CONF"
        echo -e "${Info} 已添加 MTU 优化"
    fi
}

# ==================== WireGuard 管理 ====================
start_warp() {
    if [ ! -f "$WGCF_CONF" ]; then
        echo -e "${Error} 请先生成配置"
        return 1
    fi
    
    # 检查 WireGuard 是否安装
    if ! command -v wg &>/dev/null; then
        echo -e "${Warning} WireGuard 未安装"
        echo -e "${Info} 尝试安装 WireGuard..."
        
        if [ "$OS_DISTRO" = "ubuntu" ] || [ "$OS_DISTRO" = "debian" ]; then
            apt update && apt install -y wireguard wireguard-tools
        elif [ "$OS_DISTRO" = "centos" ] || [ "$OS_DISTRO" = "rhel" ]; then
            yum install -y epel-release
            yum install -y wireguard-tools
        elif [ "$OS_DISTRO" = "alpine" ]; then
            apk add wireguard-tools
        else
            echo -e "${Error} 请手动安装 WireGuard"
            return 1
        fi
    fi
    
    # 复制配置到 WireGuard 目录
    cp "$WGCF_CONF" /etc/wireguard/wgcf.conf 2>/dev/null || {
        echo -e "${Warning} 无法复制配置到 /etc/wireguard/，使用用户模式"
    }
    
    echo -e "${Info} 启动 WARP..."
    
    # 尝试使用 wg-quick
    if [ -f "/etc/wireguard/wgcf.conf" ]; then
        wg-quick up wgcf
    else
        # 用户模式
        wg-quick up "$WGCF_CONF"
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${Info} WARP 启动成功"
        sleep 2
        show_current_ip
    else
        echo -e "${Error} WARP 启动失败"
    fi
}

stop_warp() {
    echo -e "${Info} 停止 WARP..."
    
    if [ -f "/etc/wireguard/wgcf.conf" ]; then
        wg-quick down wgcf 2>/dev/null
    fi
    
    wg-quick down "$WGCF_CONF" 2>/dev/null
    
    echo -e "${Info} WARP 已停止"
}

status_warp() {
    echo -e "${Info} WARP 状态:"
    
    if command -v wg &>/dev/null; then
        wg show
    else
        echo -e "${Warning} WireGuard 未安装"
    fi
    
    echo -e ""
    show_current_ip
}

# ==================== 解锁检测 ====================
check_unlock() {
    echo -e "${Info} 检测流媒体解锁状态..."
    echo -e ""
    
    # Netflix
    echo -n "Netflix: "
    local netflix=$(curl -s --max-time 5 "https://www.netflix.com/title/81215567" 2>/dev/null)
    if echo "$netflix" | grep -q "NSEZ-403"; then
        echo -e "${Red}未解锁${Reset}"
    elif echo "$netflix" | grep -qE "page-title|Netflix"; then
        echo -e "${Green}已解锁${Reset}"
    else
        echo -e "${Yellow}检测超时${Reset}"
    fi
    
    # YouTube Premium
    echo -n "YouTube Premium: "
    local youtube=$(curl -s --max-time 5 "https://www.youtube.com/premium" 2>/dev/null)
    if echo "$youtube" | grep -q "Premium is not available"; then
        echo -e "${Red}未解锁${Reset}"
    elif echo "$youtube" | grep -qE "Premium|youtube"; then
        echo -e "${Green}可用${Reset}"
    else
        echo -e "${Yellow}检测超时${Reset}"
    fi
    
    # ChatGPT
    echo -n "ChatGPT: "
    local chatgpt=$(curl -s --max-time 5 "https://chat.openai.com/" -H "User-Agent: Mozilla/5.0" 2>/dev/null)
    if echo "$chatgpt" | grep -qE "Sorry|unavailable"; then
        echo -e "${Red}不可用${Reset}"
    else
        echo -e "${Green}可用${Reset}"
    fi
}

# ==================== 一键安装 ====================
quick_install() {
    echo -e "${Info} 开始一键配置 WARP..."
    
    download_wgcf || return 1
    register_warp || return 1
    generate_config || return 1
    optimize_config
    start_warp
    
    echo -e ""
    echo -e "${Info} WARP 配置完成"
}

# ==================== 主菜单 ====================
show_warp_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╦ ╦╔═╗╦═╗╔═╗
    ║║║╠═╣╠╦╝╠═╝
    ╚╩╝╩ ╩╩╚═╩  
    Cloudflare WARP
EOF
        echo -e "${Reset}"
        
        # 检测状态
        if command -v wg &>/dev/null && wg show 2>/dev/null | grep -q "wgcf"; then
            echo -e " 运行状态: ${Green}运行中${Reset}"
        else
            echo -e " 运行状态: ${Red}未运行${Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== WARP 管理 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  一键配置 WARP"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}2.${Reset}  下载 wgcf"
        echo -e " ${Green}3.${Reset}  注册 WARP 账户"
        echo -e " ${Green}4.${Reset}  生成配置"
        echo -e " ${Green}5.${Reset}  优化配置 (选择模式)"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}6.${Reset}  启动 WARP"
        echo -e " ${Green}7.${Reset}  停止 WARP"
        echo -e " ${Green}8.${Reset}  查看状态"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}9.${Reset}  检测当前 IP"
        echo -e " ${Green}10.${Reset} 流媒体解锁检测"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}=================================================${Reset}"
        
        read -p " 请选择 [0-10]: " choice
        
        case "$choice" in
            1) quick_install ;;
            2) download_wgcf ;;
            3) register_warp ;;
            4) generate_config ;;
            5) optimize_config ;;
            6) start_warp ;;
            7) stop_warp ;;
            8) status_warp ;;
            9) show_current_ip ;;
            10) check_unlock ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    [ -z "$ENV_TYPE" ] && detect_environment 2>/dev/null
    show_warp_menu
fi
