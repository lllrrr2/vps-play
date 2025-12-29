#!/bin/bash
# WARP 模块 - VPS-play
# Cloudflare WARP 代理管理
# 采用 ygkkk 的 Sing-box WireGuard 实现方式
# 参考: ygkkk/argosbx

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/warp"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"
[ -z "$VPSPLAY_DIR" ] && VPSPLAY_DIR="$HOME/vps-play"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/process_manager.sh" ] && source "$VPSPLAY_DIR/utils/process_manager.sh"

# ==================== 颜色定义 ====================
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Cyan="\033[36m"
Reset="\033[0m"
Info="${Green}[信息]${Reset}"
Error="${Red}[错误]${Reset}"
Warning="${Yellow}[警告]${Reset}"
Tip="${Cyan}[提示]${Reset}"

# ==================== 配置 ====================
WARP_DIR="$HOME/.vps-play/warp"
WARP_DATA_DIR="$WARP_DIR/data"
WARP_ENDPOINT_FILE="$WARP_DATA_DIR/endpoint"
WARP_RESULT_FILE="$WARP_DIR/endpoint_result.csv"

SINGBOX_DIR="$HOME/.vps-play/singbox"
SINGBOX_BIN="$SINGBOX_DIR/sing-box"
SINGBOX_CONF="$SINGBOX_DIR/config.json"
SINGBOX_VERSION="1.12.0"
SINGBOX_REPO="https://github.com/SagerNet/sing-box"

mkdir -p "$WARP_DIR" "$WARP_DATA_DIR" "$SINGBOX_DIR"

# ==================== 系统检测 ====================
check_system() {
    if [ -z "$OS_TYPE" ]; then
        case "$(uname -s)" in
            Linux) OS_TYPE="linux" ;;
            FreeBSD) OS_TYPE="freebsd" ;;
            Darwin) OS_TYPE="darwin" ;;
        esac
    fi
    
    if [ -z "$ARCH" ]; then
        case "$(uname -m)" in
            x86_64|amd64) ARCH="amd64" ;;
            aarch64|arm64) ARCH="arm64" ;;
            armv7l) ARCH="armv7" ;;
        esac
    fi
}

# ==================== 获取 IP ====================
get_ipv4() {
    curl -s4m5 ip.sb 2>/dev/null || curl -s4m5 ifconfig.me 2>/dev/null || echo ""
}

get_ipv6() {
    curl -s6m5 ip.sb 2>/dev/null || curl -s6m5 ifconfig.me 2>/dev/null || echo ""
}

show_ip() {
    echo -e "${Info} 当前 IP 信息:"
    local ipv4=$(get_ipv4)
    local ipv6=$(get_ipv6)
    
    [ -n "$ipv4" ] && echo -e " IPv4: ${Cyan}${ipv4}${Reset}" || echo -e " IPv4: ${Red}无${Reset}"
    [ -n "$ipv6" ] && echo -e " IPv6: ${Cyan}${ipv6}${Reset}" || echo -e " IPv6: ${Red}无${Reset}"
    
    # 检测 WARP 状态
    local warp_status=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep warp | cut -d= -f2)
    case "$warp_status" in
        on) echo -e " WARP: ${Green}已启用${Reset}" ;;
        plus) echo -e " WARP: ${Green}WARP+ 已启用${Reset}" ;;
        off) echo -e " WARP: ${Yellow}未启用${Reset}" ;;
        *) echo -e " WARP: ${Red}检测失败${Reset}" ;;
    esac
}

# ==================== WARP 配置获取 (ygkkk 方案) ====================
# 全局变量
WARP_PRIVATE_KEY=""
WARP_IPV6=""
WARP_RESERVED=""

init_warp_config() {
    echo -e "${Info} 获取 WARP 配置 (ygkkk 方案)..."
    
    # 尝试从勇哥的 API 获取预注册配置
    local warpurl=""
    warpurl=$(curl -sm5 -k https://ygkkk-warp.renky.eu.org 2>/dev/null) || \
    warpurl=$(wget -qO- --timeout=5 https://ygkkk-warp.renky.eu.org 2>/dev/null)
    
    if echo "$warpurl" | grep -q ygkkk; then
        WARP_PRIVATE_KEY=$(echo "$warpurl" | awk -F'：' '/Private_key/{print $2}' | xargs)
        WARP_IPV6=$(echo "$warpurl" | awk -F'：' '/IPV6/{print $2}' | xargs)
        WARP_RESERVED=$(echo "$warpurl" | awk -F'：' '/reserved/{print $2}' | xargs)
        echo -e "${Info} WARP 配置获取成功 (远程 API)"
    else
        # 备用硬编码配置 (和 argosbx 一样)
        WARP_IPV6='2606:4700:110:8d8d:1845:c39f:2dd5:a03a'
        WARP_PRIVATE_KEY='52cuYFgCJXp0LAq7+nWJIbCXXgU9eGggOc+Hlfz5u6A='
        WARP_RESERVED='[215, 69, 233]'
        echo -e "${Info} WARP 配置获取成功 (备用配置)"
    fi
    
    # 保存配置供后续使用
    echo "$WARP_PRIVATE_KEY" > "$WARP_DATA_DIR/private_key"
    echo "$WARP_RESERVED" > "$WARP_DATA_DIR/reserved"
    echo "$WARP_IPV6" > "$WARP_DATA_DIR/ipv6"
    
    return 0
}

# 加载已保存的 WARP 配置
load_warp_config() {
    if [ -f "$WARP_DATA_DIR/private_key" ]; then
        WARP_PRIVATE_KEY=$(cat "$WARP_DATA_DIR/private_key" 2>/dev/null)
        WARP_RESERVED=$(cat "$WARP_DATA_DIR/reserved" 2>/dev/null)
        WARP_IPV6=$(cat "$WARP_DATA_DIR/ipv6" 2>/dev/null)
        return 0
    fi
    return 1
}

# ==================== Endpoint 优选功能 ====================
# 获取 CPU 架构
get_cpu_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo 'amd64' ;;
        armv8|arm64|aarch64) echo 'arm64' ;;
        *) 
            echo -e "${Error} 不支持的 CPU 架构: $(uname -m)" >&2
            return 1 
            ;;
    esac
}

# 获取当前保存的 Endpoint
get_saved_endpoint() {
    if [ -f "$WARP_ENDPOINT_FILE" ]; then
        cat "$WARP_ENDPOINT_FILE"
    else
        echo ""
    fi
}

# 获取默认 Endpoint (根据网络环境)
get_default_endpoint() {
    local has_ipv4=false
    local has_ipv6=false
    
    # 检测网络环境
    curl -s4m2 https://www.cloudflare.com/cdn-cgi/trace -k 2>/dev/null | grep -q "warp" && has_ipv4=true
    curl -s6m2 https://www.cloudflare.com/cdn-cgi/trace -k 2>/dev/null | grep -q "warp" && has_ipv6=true
    
    # 备用检测
    if [ "$has_ipv4" = false ] && [ "$has_ipv6" = false ]; then
        ip -4 route show default 2>/dev/null | grep -q default && has_ipv4=true
        ip -6 route show default 2>/dev/null | grep -q default && has_ipv6=true
    fi
    
    if [ "$has_ipv6" = true ] && [ "$has_ipv4" = false ]; then
        # 纯 IPv6 环境
        echo "[2606:4700:d0::a29f:c001]:2408"
    else
        # IPv4 或双栈，使用默认 IP
        echo "162.159.192.1:2408"
    fi
}

# 获取当前使用的 Endpoint
get_current_endpoint() {
    local saved_ep=$(get_saved_endpoint)
    if [ -n "$saved_ep" ]; then
        echo "$saved_ep"
    else
        get_default_endpoint
    fi
}

# 停止 WARP (运行优选前需要停止)
stop_warp_for_optimize() {
    echo -e "${Info} 暂停 WARP 以进行 Endpoint 优选..."
    
    # 停止 sing-box (如果正在运行 WARP 配置)
    if pgrep -f "sing-box" >/dev/null 2>&1; then
        if [ -f "$SINGBOX_CONF" ] && grep -q "warp" "$SINGBOX_CONF" 2>/dev/null; then
            pkill -f "sing-box" 2>/dev/null
            sleep 2
            echo -e "${Info} sing-box 已暂停"
        fi
    fi
}

# 恢复 WARP
resume_warp_after_optimize() {
    echo -e "${Info} 恢复 WARP 服务..."
    
    if [ -f "$SINGBOX_CONF" ] && [ -f "$SINGBOX_BIN" ]; then
        cd "$SINGBOX_DIR"
        nohup "$SINGBOX_BIN" run -c "$SINGBOX_CONF" > "$SINGBOX_DIR/sing-box.log" 2>&1 &
        sleep 2
        
        if pgrep -f "sing-box" >/dev/null 2>&1; then
            echo -e "${Info} WARP 服务已恢复"
        else
            echo -e "${Warning} WARP 服务恢复失败，请手动检查"
        fi
    fi
}

# 运行 Endpoint 优选
run_endpoint_optimize() {
    local ipv6_mode=${1:-false}
    
    echo -e ""
    echo -e "${Cyan}========== WARP Endpoint IP 优选 ==========${Reset}"
    echo -e ""
    
    local arch=$(get_cpu_arch)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local warp_tool="$WARP_DIR/warp-optimizer"
    local result_file="$WARP_RESULT_FILE"
    
    # 清理之前的结果
    rm -f "$result_file"
    
    # 停止 WARP 进行优选
    stop_warp_for_optimize
    
    # 下载 WARP 优选工具 (Linux 版本)
    echo -e "${Info} 下载 Endpoint 优选工具 ($arch)..."
    
    # 根据系统选择正确的版本
    local os_type="linux"
    case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
        darwin) os_type="darwin" ;;
        freebsd) os_type="freebsd" ;;
        *) os_type="linux" ;;
    esac
    
    local download_url="https://gitlab.com/Misaka-blog/warp-script/-/raw/main/files/warp-yxip/warp-${os_type}-${arch}"
    
    # 尝试多个下载源
    local download_success=false
    
    if curl -sL "$download_url" -o "$warp_tool" 2>/dev/null && [ -s "$warp_tool" ]; then
        download_success=true
    else
        # 备用源1: ghproxy
        echo -e "${Warning} 主线下载失败，尝试备用源..."
        download_url="https://mirror.ghproxy.com/$download_url"
        if curl -sL "$download_url" -o "$warp_tool" 2>/dev/null && [ -s "$warp_tool" ]; then
            download_success=true
        fi
    fi
    
    if [ "$download_success" = false ]; then
        echo -e "${Error} 下载优选工具失败"
        echo -e "${Tip} 您可以手动下载工具到 $warp_tool"
        resume_warp_after_optimize
        return 1
    fi
    
    chmod +x "$warp_tool"
    
    # 取消线程限制
    ulimit -n 102400 2>/dev/null
    
    echo -e "${Info} 开始 Endpoint IP 优选..."
    echo -e "${Tip} 这可能需要几分钟，请耐心等待..."
    echo -e ""
    
    # 进入工作目录运行优选
    cd "$WARP_DIR"
    
    if [ "$ipv6_mode" = true ]; then
        "$warp_tool" -ipv6
    else
        "$warp_tool"
    fi
    
    # 检查结果文件
    if [ ! -f "result.csv" ]; then
        echo -e "${Error} 优选结果文件未生成"
        rm -f "$warp_tool"
        resume_warp_after_optimize
        return 1
    fi
    
    # 复制结果
    mv "result.csv" "$result_file"
    
    echo -e ""
    echo -e "${Green}========== 优选结果 ==========${Reset}"
    echo -e ""
    
    # 显示前 10 个最优结果
    echo -e "${Info} 最优 Endpoint IP 列表:"
    echo -e ""
    awk -F, 'NR==1 || ($3!="timeout ms" && $3!="") {print}' "$result_file" | sort -t, -nk2 -nk3 | uniq | head -11 | while read line; do
        if [ -n "$line" ]; then
            local ep=$(echo "$line" | cut -d, -f1)
            local loss=$(echo "$line" | cut -d, -f2)
            local delay=$(echo "$line" | cut -d, -f3)
            
            if [ "$ep" = "IP" ] || [ "$ep" = "IP:PORT" ]; then
                printf " %-25s %-12s %s\n" "Endpoint" "丢包率" "延迟"
                echo " ----------------------------------------"
            else
                printf " %-25s %-12s %s\n" "$ep" "$loss" "$delay"
            fi
        fi
    done
    
    echo -e ""
    
    # 获取最优 IP
    local best_endpoint=$(awk -F, 'NR==2{print $1}' "$result_file")
    
    if [ -z "$best_endpoint" ]; then
        echo -e "${Error} 未能获取最优 Endpoint"
        rm -f "$warp_tool"
        resume_warp_after_optimize
        return 1
    fi
    
    echo -e "${Info} 最优 Endpoint: ${Cyan}$best_endpoint${Reset}"
    echo -e ""
    
    # 确保 endpoint 包含端口
    if ! echo "$best_endpoint" | grep -q ":"; then
        best_endpoint="${best_endpoint}:2408"
    fi
    
    # 询问是否使用最优 IP
    echo -e "${Tip} 是否使用此 Endpoint?"
    echo -e " ${Green}1.${Reset} 是，使用最优 Endpoint (推荐)"
    echo -e " ${Green}2.${Reset} 手动选择其他 Endpoint"
    echo -e " ${Green}3.${Reset} 输入自定义 Endpoint"
    echo -e " ${Green}0.${Reset} 取消，保持当前设置"
    echo -e ""
    
    read -p "请选择 [0-3, 默认1]: " ep_choice
    ep_choice=${ep_choice:-1}
    
    local selected_endpoint="$best_endpoint"
    
    case "$ep_choice" in
        1)
            # 使用最优
            ;;
        2)
            # 手动选择
            echo -e ""
            echo -e "${Info} 请输入序号选择 Endpoint (2-10):"
            read -p "序号: " row_num
            if [[ "$row_num" =~ ^[0-9]+$ ]] && [ "$row_num" -ge 2 ] && [ "$row_num" -le 11 ]; then
                selected_endpoint=$(awk -F, "NR==$row_num{print \$1}" "$result_file")
                if [ -n "$selected_endpoint" ]; then
                    if ! echo "$selected_endpoint" | grep -q ":"; then
                        selected_endpoint="${selected_endpoint}:2408"
                    fi
                else
                    echo -e "${Warning} 无效序号，使用最优 Endpoint"
                    selected_endpoint="$best_endpoint"
                fi
            else
                echo -e "${Warning} 无效输入，使用最优 Endpoint"
            fi
            ;;
        3)
            # 自定义输入
            echo -e ""
            read -p "输入 Endpoint (IP:端口): " custom_ep
            if [ -n "$custom_ep" ]; then
                selected_endpoint="$custom_ep"
            else
                echo -e "${Warning} 输入为空，使用最优 Endpoint"
            fi
            ;;
        0)
            echo -e "${Info} 已取消"
            rm -f "$warp_tool"
            resume_warp_after_optimize
            return 0
            ;;
        *)
            # 默认使用最优
            ;;
    esac
    
    # 保存选择的 Endpoint
    echo "$selected_endpoint" > "$WARP_ENDPOINT_FILE"
    echo -e "${Info} 已保存 Endpoint: ${Cyan}$selected_endpoint${Reset}"
    
    # 清理优选工具
    rm -f "$warp_tool"
    
    # 更新配置文件中的 Endpoint
    update_singbox_endpoint "$selected_endpoint"
    
    # 恢复 WARP 服务
    resume_warp_after_optimize
    
    echo -e ""
    echo -e "${Green}========== Endpoint 优选完成 ==========${Reset}"
    
    return 0
}

# 更新 sing-box 配置中的 Endpoint
update_singbox_endpoint() {
    local new_endpoint="$1"
    
    if [ ! -f "$SINGBOX_CONF" ]; then
        echo -e "${Warning} sing-box 配置文件不存在，跳过更新"
        return 1
    fi
    
    # 分离 IP 和端口
    local ep_ip=""
    local ep_port="2408"
    
    if echo "$new_endpoint" | grep -q "]:"; then
        # IPv6 格式 [ip]:port
        ep_ip=$(echo "$new_endpoint" | sed 's/\]:.*/]/' | sed 's/^\[//' | sed 's/\]$//')
        ep_port=$(echo "$new_endpoint" | sed 's/.*\]://')
    elif echo "$new_endpoint" | grep -q ":"; then
        # IPv4 格式 ip:port
        ep_ip=$(echo "$new_endpoint" | cut -d: -f1)
        ep_port=$(echo "$new_endpoint" | cut -d: -f2)
    else
        ep_ip="$new_endpoint"
    fi
    
    echo -e "${Info} 更新 sing-box 配置中的 Endpoint..."
    echo -e " IP: $ep_ip, 端口: $ep_port"
    
    # 备份配置
    cp "$SINGBOX_CONF" "${SINGBOX_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    
    # 使用 jq 更新配置 (如果有 jq)
    if command -v jq &>/dev/null; then
        local new_config=$(jq --arg ip "$ep_ip" --argjson port "$ep_port" '
            if .endpoints then
                .endpoints |= map(
                    if .type == "wireguard" then
                        .peers |= map(.address = $ip | .port = $port)
                    else
                        .
                    end
                )
            else
                .
            end
        ' "$SINGBOX_CONF" 2>/dev/null)
        
        if [ -n "$new_config" ]; then
            echo "$new_config" > "$SINGBOX_CONF"
            echo -e "${Info} 配置更新成功"
            return 0
        fi
    fi
    
    # 备用: 使用 sed 替换 (不太精确但兼容性好)
    # 匹配 "address": "xxx" 在 peers 数组中
    sed -i.tmp "s/\"address\": *\"[^\"]*\"/\"address\": \"$ep_ip\"/g" "$SINGBOX_CONF" 2>/dev/null
    sed -i.tmp "s/\"port\": *[0-9]*/\"port\": $ep_port/g" "$SINGBOX_CONF" 2>/dev/null
    rm -f "${SINGBOX_CONF}.tmp"
    
    echo -e "${Info} 配置更新完成 (sed 方式)"
    return 0
}

# Endpoint 优选菜单
endpoint_optimize_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔═╗╔╗╔╔╦╗╔═╗╔═╗╦╔╗╔╔╦╗
    ║╣ ║║║ ║║╠═╝║ ║║║║║ ║ 
    ╚═╝╝╚╝═╩╝╩  ╚═╝╩╝╚╝ ╩ 
    WARP Endpoint 优选
EOF
        echo -e "${Reset}"
        
        # 显示当前 Endpoint
        local current_ep=$(get_current_endpoint)
        echo -e " 当前 Endpoint: ${Cyan}$current_ep${Reset}"
        
        # 显示上次优选结果 (如果有)
        if [ -f "$WARP_RESULT_FILE" ]; then
            local last_optimize=$(stat -c %Y "$WARP_RESULT_FILE" 2>/dev/null || stat -f %m "$WARP_RESULT_FILE" 2>/dev/null)
            if [ -n "$last_optimize" ]; then
                local now=$(date +%s)
                local diff=$((now - last_optimize))
                local hours=$((diff / 3600))
                local mins=$(((diff % 3600) / 60))
                echo -e " 上次优选: ${Yellow}${hours}小时${mins}分钟前${Reset}"
            fi
        else
            echo -e " 上次优选: ${Yellow}尚未进行${Reset}"
        fi
        
        echo -e ""
        echo -e "${Green}==================== Endpoint 优选 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  IPv4 Endpoint 优选 ${Yellow}(推荐)${Reset}"
        echo -e " ${Green}2.${Reset}  IPv6 Endpoint 优选"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}3.${Reset}  查看上次优选结果"
        echo -e " ${Green}4.${Reset}  手动设置 Endpoint"
        echo -e " ${Green}5.${Reset}  重置为默认 Endpoint"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}========================================================${Reset}"
        
        read -p " 请选择 [0-5]: " choice
        
        case "$choice" in
            1) run_endpoint_optimize false ;;
            2) run_endpoint_optimize true ;;
            3) view_optimize_result ;;
            4) manual_set_endpoint ;;
            5) reset_default_endpoint ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# 查看上次优选结果
view_optimize_result() {
    echo -e ""
    
    if [ ! -f "$WARP_RESULT_FILE" ]; then
        echo -e "${Warning} 尚未进行过 Endpoint 优选"
        return 1
    fi
    
    echo -e "${Green}========== 上次优选结果 ==========${Reset}"
    echo -e ""
    
    awk -F, 'NR==1 || ($3!="timeout ms" && $3!="") {print}' "$WARP_RESULT_FILE" | sort -t, -nk2 -nk3 | uniq | head -11 | while read line; do
        if [ -n "$line" ]; then
            local ep=$(echo "$line" | cut -d, -f1)
            local loss=$(echo "$line" | cut -d, -f2)
            local delay=$(echo "$line" | cut -d, -f3)
            
            if [ "$ep" = "IP" ] || [ "$ep" = "IP:PORT" ]; then
                printf " %-25s %-12s %s\n" "Endpoint" "丢包率" "延迟"
                echo " ----------------------------------------"
            else
                printf " %-25s %-12s %s\n" "$ep" "$loss" "$delay"
            fi
        fi
    done
    
    echo -e ""
    
    # 询问是否使用结果中的某个 Endpoint
    echo -e "${Tip} 是否从结果中选择一个 Endpoint?"
    read -p "输入序号 (2-10) 或回车跳过: " row_num
    
    if [[ "$row_num" =~ ^[0-9]+$ ]] && [ "$row_num" -ge 2 ] && [ "$row_num" -le 11 ]; then
        local selected_endpoint=$(awk -F, "NR==$row_num{print \$1}" "$WARP_RESULT_FILE")
        if [ -n "$selected_endpoint" ]; then
            if ! echo "$selected_endpoint" | grep -q ":"; then
                selected_endpoint="${selected_endpoint}:2408"
            fi
            echo "$selected_endpoint" > "$WARP_ENDPOINT_FILE"
            echo -e "${Info} 已保存 Endpoint: ${Cyan}$selected_endpoint${Reset}"
            update_singbox_endpoint "$selected_endpoint"
        fi
    fi
}

# 手动设置 Endpoint
manual_set_endpoint() {
    echo -e ""
    echo -e "${Info} 手动设置 Endpoint"
    echo -e "${Tip} 常用 Endpoint 参考:"
    echo -e "   IPv4: 162.159.192.1:2408, 162.159.193.1:2408"
    echo -e "   IPv6: [2606:4700:d0::a29f:c001]:2408"
    echo -e ""
    
    local current_ep=$(get_current_endpoint)
    echo -e " 当前: ${Cyan}$current_ep${Reset}"
    echo -e ""
    
    read -p "输入新的 Endpoint (IP:端口): " new_ep
    
    if [ -z "$new_ep" ]; then
        echo -e "${Warning} 输入为空，已取消"
        return 1
    fi
    
    echo "$new_ep" > "$WARP_ENDPOINT_FILE"
    echo -e "${Info} 已保存 Endpoint: ${Cyan}$new_ep${Reset}"
    
    update_singbox_endpoint "$new_ep"
    
    # 询问是否重启服务
    read -p "是否重启 WARP 服务使配置生效? [Y/n]: " restart_now
    if [[ ! $restart_now =~ ^[Nn]$ ]]; then
        restart_warp_singbox
    fi
}

# 重置为默认 Endpoint
reset_default_endpoint() {
    echo -e ""
    
    rm -f "$WARP_ENDPOINT_FILE"
    
    local default_ep=$(get_default_endpoint)
    echo -e "${Info} 已重置为默认 Endpoint: ${Cyan}$default_ep${Reset}"
    
    update_singbox_endpoint "$default_ep"
    
    # 询问是否重启服务
    read -p "是否重启 WARP 服务使配置生效? [Y/n]: " restart_now
    if [[ ! $restart_now =~ ^[Nn]$ ]]; then
        restart_warp_singbox
    fi
}

# ==================== 下载 sing-box ====================
download_singbox() {
    local target_version=${1:-$SINGBOX_VERSION}
    echo -e "${Info} 正在下载 sing-box v${target_version}..."
    
    mkdir -p "$SINGBOX_DIR"
    
    local os_type
    local arch_type
    
    case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
        freebsd) os_type="freebsd" ;;
        linux) os_type="linux" ;;
        darwin) os_type="darwin" ;;
        *) os_type="linux" ;;
    esac
    
    case "$(uname -m)" in
        x86_64|amd64) arch_type="amd64" ;;
        aarch64|arm64) arch_type="arm64" ;;
        armv7l) arch_type="armv7" ;;
        i386|i686) arch_type="386" ;;
        *) arch_type="amd64" ;;
    esac
    
    echo -e "${Info} 检测到系统: ${os_type}-${arch_type}"
    
    local download_url="${SINGBOX_REPO}/releases/download/v${target_version}/sing-box-${target_version}-${os_type}-${arch_type}.tar.gz"
    
    cd "$SINGBOX_DIR" || { echo -e "${Error} 无法进入目录"; return 1; }
    
    # 备份旧版本
    [ -f "$SINGBOX_BIN" ] && mv "$SINGBOX_BIN" "${SINGBOX_BIN}.bak"
    
    echo -e "${Info} 下载地址: $download_url"
    
    if curl -sL "$download_url" -o sing-box.tar.gz && [ -s sing-box.tar.gz ]; then
        tar -xzf sing-box.tar.gz --strip-components=1 2>/dev/null
        rm -f sing-box.tar.gz
        chmod +x sing-box 2>/dev/null
        
        if [ -f "$SINGBOX_BIN" ] && [ -x "$SINGBOX_BIN" ]; then
            echo -e "${Info} sing-box 下载完成"
            $SINGBOX_BIN version
            return 0
        fi
    fi
    
    echo -e "${Error} 下载失败"
    [ -f "${SINGBOX_BIN}.bak" ] && mv "${SINGBOX_BIN}.bak" "$SINGBOX_BIN"
    return 1
}

# ==================== 生成 WARP Sing-box 配置 ====================
generate_warp_singbox_config() {
    echo -e "${Info} 生成 WARP Sing-box 配置..."
    
    # 确保已有 WARP 配置
    if [ -z "$WARP_PRIVATE_KEY" ]; then
        if ! load_warp_config; then
            init_warp_config
        fi
    fi
    
    if [ -z "$WARP_PRIVATE_KEY" ]; then
        echo -e "${Error} WARP 配置获取失败"
        return 1
    fi
    
    # 获取 Endpoint
    local warp_endpoint=$(get_current_endpoint)
    local ep_ip=""
    local ep_port="2408"
    
    # 解析 Endpoint
    if echo "$warp_endpoint" | grep -q "]:"; then
        # IPv6 格式
        ep_ip=$(echo "$warp_endpoint" | sed 's/\]:.*/]/' | sed 's/^\[//' | sed 's/\]$//')
        ep_port=$(echo "$warp_endpoint" | sed 's/.*\]://')
    elif echo "$warp_endpoint" | grep -q ":"; then
        # IPv4 格式
        ep_ip=$(echo "$warp_endpoint" | cut -d: -f1)
        ep_port=$(echo "$warp_endpoint" | cut -d: -f2)
    else
        ep_ip="$warp_endpoint"
    fi
    
    local warp_ipv6="${WARP_IPV6:-2606:4700:110:8f1a:c53:a4c5:2249:1546}"
    local warp_reserved="${WARP_RESERVED:-[0,0,0]}"
    
    echo -e "${Info} 使用 Endpoint: ${Cyan}${ep_ip}:${ep_port}${Reset}"
    
    # 检测可用端口 (从 1080 开始)
    local socks_port=1080
    while netstat -tuln 2>/dev/null | grep -q ":${socks_port} "; do
        ((socks_port++))
    done
    
    echo -e "${Info} 本地 Socks5 端口: ${Green}${socks_port}${Reset}"
    echo "$socks_port" > "$WARP_DATA_DIR/socks_port"
    
    # 生成配置 (sing-box 1.12+ endpoints 格式)
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "cloudflare",
        "address": "https://1.1.1.1/dns-query",
        "detour": "warp-out"
      }
    ]
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": ${socks_port}
    },
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "warp0",
      "address": [
        "172.16.0.2/30",
        "fd00::2/126"
      ],
      "mtu": 1280,
      "auto_route": true,
      "strict_route": true,
      "stack": "system"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp-out",
      "address": [
        "172.16.0.2/32",
        "${warp_ipv6}/128"
      ],
      "private_key": "${WARP_PRIVATE_KEY}",
      "peers": [
        {
          "address": "${ep_ip}",
          "port": ${ep_port},
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": [
            "0.0.0.0/0",
            "::/0"
          ],
          "reserved": ${warp_reserved}
        }
      ]
    }
  ],
  "route": {
    "rules": [
      {
        "action": "sniff"
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      }
    ],
    "final": "warp-out",
    "auto_detect_interface": true
  }
}
EOF
    
    echo -e "${Info} 配置生成完成: $SINGBOX_CONF"
    return 0
}

# ==================== 服务管理 ====================
start_warp_singbox() {
    if [ ! -f "$SINGBOX_BIN" ]; then
        echo -e "${Error} sing-box 未安装"
        return 1
    fi
    
    if [ ! -f "$SINGBOX_CONF" ]; then
        echo -e "${Error} 配置文件不存在"
        return 1
    fi
    
    echo -e "${Info} 启动 WARP (sing-box)..."
    
    # 检查是否已运行
    if pgrep -f "sing-box" >/dev/null 2>&1; then
        echo -e "${Warning} sing-box 已在运行"
        return 0
    fi
    
    cd "$SINGBOX_DIR"
    
    # 验证配置
    if ! "$SINGBOX_BIN" check -c "$SINGBOX_CONF" 2>/dev/null; then
        echo -e "${Error} 配置验证失败"
        return 1
    fi
    
    # 启动服务
    nohup "$SINGBOX_BIN" run -c "$SINGBOX_CONF" > "$SINGBOX_DIR/sing-box.log" 2>&1 &
    
    sleep 2
    
    if pgrep -f "sing-box" >/dev/null 2>&1; then
        echo -e "${Info} WARP 启动成功"
        echo -e "${Tip} 本地代理: socks5://127.0.0.1:1080"
        return 0
    else
        echo -e "${Error} WARP 启动失败"
        echo -e "${Tip} 查看日志: cat $SINGBOX_DIR/sing-box.log"
        return 1
    fi
}

stop_warp_singbox() {
    echo -e "${Info} 停止 WARP..."
    
    pkill -f "sing-box" 2>/dev/null
    
    sleep 1
    
    if ! pgrep -f "sing-box" >/dev/null 2>&1; then
        echo -e "${Info} WARP 已停止"
    else
        echo -e "${Warning} 强制终止..."
        pkill -9 -f "sing-box" 2>/dev/null
    fi
}

restart_warp_singbox() {
    stop_warp_singbox
    sleep 1
    start_warp_singbox
}

status_warp_singbox() {
    echo -e ""
    echo -e "${Info} WARP 状态:"
    echo -e ""
    
    if pgrep -f "sing-box" >/dev/null 2>&1; then
        echo -e " 运行状态: ${Green}运行中${Reset}"
        
        local pid=$(pgrep -f "sing-box" | head -1)
        echo -e " 进程 PID: ${Cyan}$pid${Reset}"
        
        # 显示当前 Endpoint
        local current_ep=$(get_current_endpoint)
        echo -e " Endpoint: ${Cyan}$current_ep${Reset}"
    else
        echo -e " 运行状态: ${Red}未运行${Reset}"
    fi
    
    echo -e ""
    show_ip
}

# ==================== 一键安装 ====================
quick_install() {
    echo -e ""
    echo -e "${Cyan}========== WARP 一键安装 (Sing-box 模式) ==========${Reset}"
    echo -e ""
    echo -e "${Tip} 此方式采用 ygkkk 的 Sing-box WireGuard 实现"
    echo -e "${Tip} 将创建本地 SOCKS5 代理 (127.0.0.1:1080)"
    echo -e ""
    
    check_system
    
    # 检查是否已安装
    if [ -f "$SINGBOX_CONF" ] && pgrep -f "sing-box" >/dev/null 2>&1; then
        echo -e "${Warning} WARP 已安装并运行中"
        read -p "是否重新安装? [y/N]: " reinstall
        [[ ! $reinstall =~ ^[Yy]$ ]] && return 0
        stop_warp_singbox
    fi
    
    # 步骤1: 下载 sing-box (如果需要)
    if [ ! -f "$SINGBOX_BIN" ]; then
        echo -e ""
        echo -e "${Green}[步骤 1/4] 下载 sing-box${Reset}"
        download_singbox || return 1
    else
        echo -e "${Info} sing-box 已安装，跳过下载"
    fi
    
    # 步骤2: 获取 WARP 配置
    echo -e ""
    echo -e "${Green}[步骤 2/4] 获取 WARP 配置${Reset}"
    init_warp_config || return 1
    
    # 步骤3: Endpoint 优选
    echo -e ""
    echo -e "${Green}[步骤 3/4] Endpoint IP 优选${Reset}"
    echo -e ""
    echo -e "${Tip} 推荐进行 Endpoint 优选以获得最佳连接质量"
    read -p "是否进行 Endpoint 优选? [Y/n]: " do_optimize
    
    if [[ ! $do_optimize =~ ^[Nn]$ ]]; then
        run_endpoint_optimize false
    else
        echo -e "${Info} 跳过优选，使用默认 Endpoint"
    fi
    
    # 步骤4: 生成配置并启动
    echo -e ""
    echo -e "${Green}[步骤 4/4] 生成配置并启动${Reset}"
    generate_warp_singbox_config || return 1
    start_warp_singbox
    
    echo -e ""
    echo -e "${Green}========== WARP 安装完成 ==========${Reset}"
    # 获取实际使用的端口
    local socks_port=1080
    if [ -f "$WARP_DATA_DIR/socks_port" ]; then
        socks_port=$(cat "$WARP_DATA_DIR/socks_port")
    fi
    
    echo -e ""
    echo -e "${Green}========== WARP 安装完成 ==========${Reset}"
    echo -e ""
    echo -e " ${Cyan}本地代理:${Reset} socks5://127.0.0.1:${socks_port}"
    echo -e " ${Cyan}配置文件:${Reset} $SINGBOX_CONF"
    echo -e ""
    echo -e "${Tip} 使用方法:"
    echo -e "   curl -x socks5h://127.0.0.1:${socks_port} ip.sb"
    echo -e ""
    
    # 验证
    echo -e "${Info} 验证 WARP 连接..."
    sleep 3
    local test_ip=$(curl -sx socks5h://127.0.0.1:${socks_port} ip.sb --connect-timeout 10 2>/dev/null)
    
    if [ -n "$test_ip" ]; then
        echo -e "${Info} WARP 出口 IP: ${Cyan}$test_ip${Reset}"
        echo -e "${Info} 安装成功!"
    else
        echo -e "${Warning} WARP 代理测试未通过，可能需要几秒钟才能就绪"
        echo -e "${Tip} 手动测试: curl -x socks5h://127.0.0.1:${socks_port} ip.sb"
    fi
}

# ==================== 卸载 ====================
uninstall_warp() {
    echo -e ""
    read -p "确定卸载 WARP? [y/N]: " confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    echo -e "${Info} 正在卸载 WARP..."
    
    # 停止服务
    stop_warp_singbox
    
    # 删除配置
    rm -rf "$WARP_DIR"
    rm -f "$SINGBOX_CONF"
    
    echo -e "${Info} WARP 已卸载"
    echo -e "${Tip} sing-box 程序已保留，如需删除请手动执行:"
    echo -e "     rm -rf $SINGBOX_DIR"
}

# ==================== 流媒体解锁检测 ====================
check_streaming() {
    echo -e "${Info} 检测流媒体解锁状态 (通过 WARP 代理)..."
    echo -e ""
    
    local proxy_opt=""
    local socks_port=1080
    if [ -f "$WARP_DATA_DIR/socks_port" ]; then
        socks_port=$(cat "$WARP_DATA_DIR/socks_port")
    fi
    
    if pgrep -f "sing-box" >/dev/null 2>&1; then
        proxy_opt="-x socks5h://127.0.0.1:${socks_port}"
        echo -e "${Info} 使用 WARP 代理进行检测 (端口: ${socks_port})"
    else
        echo -e "${Warning} WARP 未运行，使用直连检测"
    fi
    
    # Netflix
    echo -n " Netflix: "
    local nf=$(curl -sLm5 $proxy_opt "https://www.netflix.com/title/81215567" 2>/dev/null)
    if echo "$nf" | grep -q "NSEZ-403"; then
        echo -e "${Red}未解锁${Reset}"
    elif echo "$nf" | grep -qE "page-title|Netflix"; then
        echo -e "${Green}已解锁${Reset}"
    else
        echo -e "${Yellow}检测超时${Reset}"
    fi
    
    # YouTube Premium
    echo -n " YouTube: "
    local yt=$(curl -sLm5 $proxy_opt "https://www.youtube.com/premium" 2>/dev/null)
    if echo "$yt" | grep -q "Premium is not available"; then
        echo -e "${Red}无 Premium${Reset}"
    else
        echo -e "${Green}可访问${Reset}"
    fi
    
    # ChatGPT
    echo -n " ChatGPT: "
    local gpt=$(curl -sLm5 $proxy_opt "https://chat.openai.com/" -H "User-Agent: Mozilla/5.0" 2>/dev/null)
    if echo "$gpt" | grep -qE "Sorry|unavailable|blocked"; then
        echo -e "${Red}不可用${Reset}"
    else
        echo -e "${Green}可访问${Reset}"
    fi
    
    # Google
    echo -n " Google:  "
    if curl -sLm5 $proxy_opt "https://www.google.com" &>/dev/null; then
        echo -e "${Green}可访问${Reset}"
    else
        echo -e "${Red}不可访问${Reset}"
    fi
}

# ==================== 查看日志 ====================
view_logs() {
    local log_file="$SINGBOX_DIR/sing-box.log"
    
    if [ ! -f "$log_file" ]; then
        echo -e "${Warning} 日志文件不存在"
        return 1
    fi
    
    echo -e "${Info} 最近 50 行日志:"
    echo -e ""
# ==================== 辅助函数 ====================
# 安装 jq 工具
install_jq() {
    if command -v jq &>/dev/null; then
        return 0
    fi
    
    echo -e "${Info} 正在安装 jq..."
    
    # 尝试系统包管理器
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq jq 2>/dev/null
    elif command -v yum &>/dev/null; then
        yum install -y -q jq 2>/dev/null
    elif command -v apk &>/dev/null; then
        apk add --quiet jq 2>/dev/null
    elif command -v pkg &>/dev/null; then
        pkg install -y jq 2>/dev/null
    fi
    
    if command -v jq &>/dev/null; then
        return 0
    fi
    
    # 尝试下载静态二进制文件
    echo -e "${Info} 系统安装失败，尝试下载 jq 二进制文件..."
    local jq_url=""
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64" ;;
        aarch64|arm64) jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-arm64" ;;
        *) 
            echo -e "${Warning} 不支持的架构: $arch"
            return 1 
            ;;
    esac
    
    # 使用 ghproxy 加速
    local download_urls=(
        "https://mirror.ghproxy.com/$jq_url"
        "$jq_url"
    )
    
    for url in "${download_urls[@]}"; do
        if curl -sL "$url" -o "/usr/local/bin/jq" 2>/dev/null; then
            chmod +x "/usr/local/bin/jq"
            if command -v jq &>/dev/null; then
                echo -e "${Info} jq 安装成功"
                return 0
            fi
        fi
    done
    
    # 尝试安装到当前目录
    if curl -sL "${download_urls[0]}" -o "./jq" 2>/dev/null; then
        chmod +x "./jq"
        export PATH="$PATH:$(pwd)"
        if command -v jq &>/dev/null; then
             echo -e "${Info} jq 安装成功 (当前目录)"
             return 0
        fi
    fi
    
    echo -e "${Error} jq 安装失败"
    return 1
}

# ==================== 为现有节点配置 WARP 出站 ====================
# 检测并列出可用的配置文件
detect_proxy_configs() {
    local configs=()
    
    # Singbox 配置
    local singbox_paths=(
        "$HOME/.vps-play/singbox/config.json"
        "/etc/sing-box/config.json"
        "/usr/local/etc/sing-box/config.json"
    )
    
    for path in "${singbox_paths[@]}"; do
        if [ -f "$path" ]; then
            configs+=("singbox:$path")
        fi
    done
    
    # Xray 配置
    local xray_paths=(
        "$HOME/.vps-play/xui/config.json"
        "/etc/xray/config.json"
        "/usr/local/etc/xray/config.json"
        "/etc/x-ui/xray/config.json"
    )
    
    for path in "${xray_paths[@]}"; do
        if [ -f "$path" ]; then
            configs+=("xray:$path")
        fi
    done
    
    echo "${configs[@]}"
}

# 为 Singbox 添加 WARP 出站
add_warp_outbound_singbox() {
    local config_file="$1"
    
    echo -e "${Info} 为 Singbox 配置添加 WARP 出站..."
    echo -e " 配置文件: ${Cyan}$config_file${Reset}"
    echo -e ""
    
    # 确保有 WARP 配置
    if [ -z "$WARP_PRIVATE_KEY" ]; then
        if ! load_warp_config; then
            echo -e "${Info} 正在获取 WARP 配置..."
            init_warp_config
        fi
    fi
    
    if [ -z "$WARP_PRIVATE_KEY" ]; then
        echo -e "${Error} 无法获取 WARP 配置"
        return 1
    fi
    
    # 备份原配置
    local backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$config_file" "$backup_file"
    echo -e "${Info} 原配置已备份: $backup_file"
    
    # 获取 Endpoint
    local warp_endpoint=$(get_current_endpoint)
    local ep_ip=""
    local ep_port="2408"
    
    if echo "$warp_endpoint" | grep -q "]:"; then
        ep_ip=$(echo "$warp_endpoint" | sed 's/\]:.*/]/' | sed 's/^\[//' | sed 's/\]$//')
        ep_port=$(echo "$warp_endpoint" | sed 's/.*\]://')
    elif echo "$warp_endpoint" | grep -q ":"; then
        ep_ip=$(echo "$warp_endpoint" | cut -d: -f1)
        ep_port=$(echo "$warp_endpoint" | cut -d: -f2)
    else
        ep_ip="$warp_endpoint"
    fi
    
    local warp_ipv6="${WARP_IPV6:-2606:4700:110:8f1a:c53:a4c5:2249:1546}"
    local warp_reserved="${WARP_RESERVED:-[0,0,0]}"
    
    echo -e "${Info} WARP Endpoint: ${Cyan}${ep_ip}:${ep_port}${Reset}"
    
    # 尝试安装 jq
    install_jq
    
    # 使用 jq 修改配置 (如果可用)
    if command -v jq &>/dev/null; then
        # 构造 WARP endpoint 配置
        local warp_endpoint_json=$(cat <<WARP_EP_EOF
{
  "type": "wireguard",
  "tag": "warp-out",
  "address": ["172.16.0.2/32", "${warp_ipv6}/128"],
  "private_key": "${WARP_PRIVATE_KEY}",
  "peers": [{
    "address": "${ep_ip}",
    "port": ${ep_port},
    "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
    "allowed_ips": ["0.0.0.0/0", "::/0"],
    "reserved": ${warp_reserved}
  }]
}
WARP_EP_EOF
)
        
        # 读取现有配置并添加 WARP
        local new_config=$(jq --argjson warp_ep "$warp_endpoint_json" '
            # 确保有 outbounds 数组
            .outbounds = (.outbounds // []) |
            
            # 移除已有的 warp-out (如果有)
            .outbounds = [.outbounds[] | select(.tag != "warp-out")] |
            
            # 确保有 direct 出站
            (if any(.outbounds[]; .tag == "direct") then . else .outbounds = [{type: "direct", tag: "direct"}] + .outbounds end) |
            
            # 添加 endpoints 数组 (移除已有的 warp)
            .endpoints = ((.endpoints // []) | [.[] | select(.tag != "warp-out")]) |
            .endpoints = .endpoints + [$warp_ep] |
            
            # 设置路由 final 为 warp-out
            .route = (.route // {}) |
            .route.final = "warp-out" |
            
            # 添加基本路由规则 (如果没有)
            .route.rules = (.route.rules // []) |
            (if any(.route.rules[]; .action == "sniff") then . else .route.rules = [{action: "sniff"}] + .route.rules end)
        ' "$config_file" 2>/dev/null)
        
        if [ -n "$new_config" ] && echo "$new_config" | jq empty 2>/dev/null; then
            echo "$new_config" > "$config_file"
            echo -e "${Info} Singbox 配置已更新 (jq)"
            
            # 验证配置
            if [ -f "$SINGBOX_BIN" ]; then
                if "$SINGBOX_BIN" check -c "$config_file" 2>/dev/null; then
                    echo -e "${Info} 配置验证通过"
                else
                    echo -e "${Error} 配置验证失败，恢复备份"
                    cp "$backup_file" "$config_file"
                    return 1
                fi
            fi
            
            return 0
        else
            echo -e "${Warning} jq 处理失败，尝试 sed 方式..."
        fi
    fi
    
    # 备用方案：使用 sed 直接修改 JSON (简单但有限)
    echo -e "${Info} 使用 sed 方式修改配置..."
    
    # 创建 WARP endpoint JSON 块
    local warp_block=$(cat <<WARP_BLOCK_EOF
  ],
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp-out",
      "address": ["172.16.0.2/32", "${warp_ipv6}/128"],
      "private_key": "${WARP_PRIVATE_KEY}",
      "peers": [{
        "address": "${ep_ip}",
        "port": ${ep_port},
        "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
        "allowed_ips": ["0.0.0.0/0", "::/0"],
        "reserved": ${warp_reserved}
      }]
    }
  ],
  "route": {
    "rules": [{"action": "sniff"}],
    "final": "warp-out"
  }
}
WARP_BLOCK_EOF
)
    
    # 检查配置文件是否已有 endpoints
    if grep -q '"endpoints"' "$config_file" 2>/dev/null; then
        echo -e "${Warning} 配置中已有 endpoints，使用手动方式"
    else
        # 尝试在 outbounds 结尾后添加 endpoints
        # 先找到最后一个 } 并替换
        if grep -q '"outbounds"' "$config_file" 2>/dev/null; then
            # 使用 awk 处理 JSON，在文件末尾 } 前插入配置
            local tmp_file="${config_file}.tmp"
            awk -v warp="$warp_block" '
            {
                lines[NR] = $0
            }
            END {
                # 找到最后一个 }
                for (i = NR; i >= 1; i--) {
                    if (lines[i] ~ /^[[:space:]]*\}[[:space:]]*$/) {
                        last_brace = i
                        break
                    }
                }
                # 找到 outbounds 数组的结尾 ]
                for (i = last_brace - 1; i >= 1; i--) {
                    if (lines[i] ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) {
                        # 输出到这一行
                        for (j = 1; j < i; j++) {
                            print lines[j]
                        }
                        # 插入 WARP 配置
                        print warp
                        break
                    } else if (i == 1) {
                        # 未找到，原样输出
                        for (j = 1; j <= NR; j++) {
                            print lines[j]
                        }
                    }
                }
            }
            ' "$config_file" > "$tmp_file" 2>/dev/null
            
            if [ -s "$tmp_file" ]; then
                mv "$tmp_file" "$config_file"
                echo -e "${Info} 配置已更新 (sed/awk)"
                
                # 验证
                if [ -f "$SINGBOX_BIN" ]; then
                    if "$SINGBOX_BIN" check -c "$config_file" 2>/dev/null; then
                        echo -e "${Info} 配置验证通过"
                        return 0
                    else
                        echo -e "${Error} 配置验证失败，恢复备份"
                        cp "$backup_file" "$config_file"
                    fi
                else
                    return 0
                fi
            else
                rm -f "$tmp_file"
            fi
        fi
    fi
    
    # 备用方案：提示用户手动添加
    echo -e "${Warning} 无法自动修改配置 (需要 jq 工具)"
    echo -e "${Tip} 请手动添加以下配置到 $config_file:"
    echo -e ""
    echo -e "${Cyan}"
    cat <<MANUAL_EOF
在 "endpoints" 数组中添加:
{
  "type": "wireguard",
  "tag": "warp-out",
  "address": ["172.16.0.2/32", "${warp_ipv6}/128"],
  "private_key": "${WARP_PRIVATE_KEY}",
  "peers": [{
    "address": "${ep_ip}",
    "port": ${ep_port},
    "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
    "allowed_ips": ["0.0.0.0/0", "::/0"],
    "reserved": ${warp_reserved}
  }]
}

并将 "route" 中的 "final" 改为 "warp-out"
MANUAL_EOF
    echo -e "${Reset}"
    
    return 1
}

# 为 Xray 添加 WARP 出站
add_warp_outbound_xray() {
    local config_file="$1"
    
    echo -e "${Info} 为 Xray 配置添加 WARP 出站..."
    echo -e " 配置文件: ${Cyan}$config_file${Reset}"
    echo -e ""
    
    # 确保有 WARP 配置
    if [ -z "$WARP_PRIVATE_KEY" ]; then
        if ! load_warp_config; then
            echo -e "${Info} 正在获取 WARP 配置..."
            init_warp_config
        fi
    fi
    
    if [ -z "$WARP_PRIVATE_KEY" ]; then
        echo -e "${Error} 无法获取 WARP 配置"
        return 1
    fi
    
    # 备份原配置
    local backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$config_file" "$backup_file"
    echo -e "${Info} 原配置已备份: $backup_file"
    
    # 获取 Endpoint
    local warp_endpoint=$(get_current_endpoint)
    local ep_ip=""
    local ep_port="2408"
    
    if echo "$warp_endpoint" | grep -q "]:"; then
        ep_ip=$(echo "$warp_endpoint" | sed 's/\]:.*/]/' | sed 's/^\[//' | sed 's/\]$//')
        ep_port=$(echo "$warp_endpoint" | sed 's/.*\]://')
    elif echo "$warp_endpoint" | grep -q ":"; then
        ep_ip=$(echo "$warp_endpoint" | cut -d: -f1)
        ep_port=$(echo "$warp_endpoint" | cut -d: -f2)
    else
        ep_ip="$warp_endpoint"
    fi
    
    local warp_ipv6="${WARP_IPV6:-2606:4700:110:8f1a:c53:a4c5:2249:1546}"
    # Xray 的 reserved 需要是字符串格式
    local warp_reserved_xray=$(echo "$WARP_RESERVED" | tr -d '[]' | tr ',' ':')
    [ -z "$warp_reserved_xray" ] && warp_reserved_xray="0:0:0"
    
    echo -e "${Info} WARP Endpoint: ${Cyan}${ep_ip}:${ep_port}${Reset}"
    
    # 尝试安装 jq
    install_jq
    
    # 使用 jq 修改配置
    if command -v jq &>/dev/null; then
        # 构造 Xray WireGuard 出站配置
        local warp_outbound_json=$(cat <<WARP_XRAY_EOF
{
  "tag": "warp-out",
  "protocol": "wireguard",
  "settings": {
    "secretKey": "${WARP_PRIVATE_KEY}",
    "address": ["172.16.0.2/32", "${warp_ipv6}/128"],
    "peers": [{
      "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "allowedIPs": ["0.0.0.0/0", "::/0"],
      "endpoint": "${ep_ip}:${ep_port}"
    }],
    "reserved": [$(echo "$WARP_RESERVED" | tr -d '[]')]
  }
}
WARP_XRAY_EOF
)
        
        local new_config=$(jq --argjson warp_out "$warp_outbound_json" '
            # 确保有 outbounds 数组
            .outbounds = (.outbounds // []) |
            
            # 移除已有的 warp-out (如果有)
            .outbounds = [.outbounds[] | select(.tag != "warp-out")] |
            
            # 添加 WARP 出站
            .outbounds = .outbounds + [$warp_out] |
            
            # 确保有路由规则
            .routing = (.routing // {}) |
            .routing.rules = (.routing.rules // []) |
            
            # 添加默认规则使用 WARP (如果没有指定 outboundTag 的规则)
            # 这不会影响已有的分流规则
            .routing.domainStrategy = (.routing.domainStrategy // "AsIs")
        ' "$config_file" 2>/dev/null)
        
        if [ -n "$new_config" ] && echo "$new_config" | jq empty 2>/dev/null; then
            echo "$new_config" > "$config_file"
            echo -e "${Info} Xray 配置已更新"
            echo -e ""
            echo -e "${Warning} 注意: Xray 配置已添加 WARP 出站"
            echo -e "${Tip} 如需让所有流量走 WARP，请在路由规则中添加:"
            echo -e "    {\"outboundTag\": \"warp-out\", \"type\": \"field\", \"network\": \"tcp,udp\"}"
            return 0
        else
            echo -e "${Error} jq 处理失败"
        fi
    fi
    
    # 备用方案
    echo -e "${Warning} 无法自动修改配置 (需要 jq 工具)"
    echo -e "${Tip} 请手动添加以下出站配置到 $config_file 的 outbounds 数组:"
    echo -e ""
    echo -e "${Cyan}"
    cat <<MANUAL_XRAY_EOF
{
  "tag": "warp-out",
  "protocol": "wireguard",
  "settings": {
    "secretKey": "${WARP_PRIVATE_KEY}",
    "address": ["172.16.0.2/32", "${warp_ipv6}/128"],
    "peers": [{
      "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "allowedIPs": ["0.0.0.0/0", "::/0"],
      "endpoint": "${ep_ip}:${ep_port}"
    }],
    "reserved": [$(echo "$WARP_RESERVED" | tr -d '[]')]
  }
}
MANUAL_XRAY_EOF
    echo -e "${Reset}"
    
    return 1
}

# 配置现有节点的 WARP 出站菜单
configure_existing_warp_outbound() {
    echo -e ""
    echo -e "${Cyan}========== 为现有节点添加 WARP 出站 ==========${Reset}"
    echo -e ""
    echo -e "${Tip} 此功能将在不影响现有节点的情况下，添加 WARP 出站"
    echo -e "${Tip} 流量将通过 WARP 出站，IP 变为 Cloudflare 的 IP"
    echo -e ""
    
    # 检测可用配置
    local configs_str=$(detect_proxy_configs)
    
    if [ -z "$configs_str" ]; then
        echo -e "${Warning} 未检测到任何代理配置文件"
        echo -e "${Tip} 支持的配置路径:"
        echo -e "   Singbox: ~/.vps-play/singbox/config.json, /etc/sing-box/config.json"
        echo -e "   Xray:    ~/.vps-play/xui/config.json, /etc/xray/config.json"
        echo -e ""
        
        read -p "手动输入配置文件路径 (或回车返回): " custom_path
        if [ -z "$custom_path" ]; then
            return 0
        fi
        
        if [ ! -f "$custom_path" ]; then
            echo -e "${Error} 文件不存在: $custom_path"
            return 1
        fi
        
        # 判断类型
        if grep -q '"inbounds"' "$custom_path" 2>/dev/null; then
            if grep -q '"endpoints"' "$custom_path" 2>/dev/null || grep -q '"type".*:.*"hysteria2\|anytls\|tuic"' "$custom_path" 2>/dev/null; then
                configs_str="singbox:$custom_path"
            else
                configs_str="xray:$custom_path"
            fi
        else
            echo -e "${Warning} 无法识别配置类型，尝试作为 Singbox 处理"
            configs_str="singbox:$custom_path"
        fi
    fi
    
    # 转换为数组
    IFS=' ' read -ra configs <<< "$configs_str"
    
    echo -e "${Info} 检测到以下配置文件:"
    echo -e ""
    
    local i=1
    for config in "${configs[@]}"; do
        local type=$(echo "$config" | cut -d: -f1)
        local path=$(echo "$config" | cut -d: -f2-)
        local type_label=""
        case "$type" in
            singbox) type_label="${Green}Singbox${Reset}" ;;
            xray) type_label="${Yellow}Xray${Reset}" ;;
        esac
        echo -e " ${Green}${i}.${Reset} [$type_label] $path"
        i=$((i + 1))
    done
    
    echo -e " ${Green}0.${Reset} 返回"
    echo -e ""
    
    read -p "选择要配置的文件 [0-$((i-1))]: " choice
    
    if [ "$choice" = "0" ] || [ -z "$choice" ]; then
        return 0
    fi
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#configs[@]}" ]; then
        echo -e "${Error} 无效选择"
        return 1
    fi
    
    local selected="${configs[$((choice-1))]}"
    local type=$(echo "$selected" | cut -d: -f1)
    local path=$(echo "$selected" | cut -d: -f2-)
    
    echo -e ""
    
    # 询问是否先进行 Endpoint 优选
    local warp_endpoint_file="$HOME/.vps-play/warp/data/endpoint"
    if [ ! -f "$warp_endpoint_file" ]; then
        echo -e "${Tip} 尚未进行 Endpoint 优选"
        read -p "是否先进行 Endpoint 优选? [y/N]: " do_optimize
        if [[ "$do_optimize" =~ ^[Yy]$ ]]; then
            run_endpoint_optimize false
        fi
    fi
    
    # 添加 WARP 出站
    case "$type" in
        singbox)
            add_warp_outbound_singbox "$path"
            ;;
        xray)
            add_warp_outbound_xray "$path"
            ;;
    esac
    
    local result=$?
    
    if [ $result -eq 0 ]; then
        echo -e ""
        echo -e "${Green}========== 配置完成 ==========${Reset}"
        echo -e ""
        
        # 询问是否重启服务
        read -p "是否重启服务使配置生效? [Y/n]: " restart_now
        if [[ ! $restart_now =~ ^[Nn]$ ]]; then
            case "$type" in
                singbox)
                    if pgrep -f "sing-box" >/dev/null 2>&1; then
                        pkill -f "sing-box"
                        sleep 1
                    fi
                    if [ -f "$SINGBOX_BIN" ]; then
                        cd "$SINGBOX_DIR"
                        nohup "$SINGBOX_BIN" run -c "$path" > "$SINGBOX_DIR/sing-box.log" 2>&1 &
                        echo -e "${Info} Singbox 已重启"
                    fi
                    ;;
                xray)
                    if command -v systemctl &>/dev/null; then
                        systemctl restart xray 2>/dev/null || systemctl restart x-ui 2>/dev/null
                        echo -e "${Info} 已尝试重启 Xray/X-UI 服务"
                    else
                        echo -e "${Tip} 请手动重启 Xray 服务"
                    fi
                    ;;
            esac
        fi
    fi
    
    return $result
}

# ==================== 主菜单 ====================
show_warp_menu() {
    check_system
    
    # Serv00/HostUno 环境检测
    local is_serv00=false
    if [ -f /etc/os-release ]; then
        grep -qi "serv00\|hostuno" /etc/os-release 2>/dev/null && is_serv00=true
    fi
    hostname 2>/dev/null | grep -qiE "serv00|hostuno" && is_serv00=true
    command -v devil &>/dev/null && is_serv00=true
    
    if [ "$is_serv00" = true ]; then
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╦ ╦╔═╗╦═╗╔═╗
    ║║║╠═╣╠╦╝╠═╝
    ╚╩╝╩ ╩╩╚═╩  
EOF
        echo -e "${Reset}"
        echo -e "${Red}========================================${Reset}"
        echo -e "${Error} Serv00/HostUno 环境不支持 WARP"
        echo -e "${Red}========================================${Reset}"
        echo -e ""
        echo -e " 原因: WARP 需要 TUN/TAP 或 root 权限"
        echo -e "       Serv00 是共享主机，无法满足这些要求"
        echo -e ""
        echo -e "${Tip} 替代方案:"
        echo -e "  ${Green}1.${Reset} 使用 ${Cyan}Cloudflared 隧道${Reset} (主菜单选项 6)"
        echo -e "  ${Green}2.${Reset} 使用外部 WARP Socks5 代理服务"
        echo -e ""
        read -p "按回车返回主菜单..."
        return 0
    fi
    
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╦ ╦╔═╗╦═╗╔═╗
    ║║║╠═╣╠╦╝╠═╝
    ╚╩╝╩ ╩╩╚═╩  
    Cloudflare WARP
    (Sing-box WireGuard 模式)
EOF
        echo -e "${Reset}"
        
        # 显示状态
        if pgrep -f "sing-box" >/dev/null 2>&1; then
            echo -e " 状态: ${Green}运行中${Reset}"
            local current_ep=$(get_current_endpoint)
            echo -e " Endpoint: ${Cyan}$current_ep${Reset}"
        else
            echo -e " 状态: ${Yellow}未运行${Reset}"
        fi
        
        if [ -f "$WARP_DATA_DIR/private_key" ]; then
            echo -e " 配置: ${Green}已初始化${Reset}"
        else
            echo -e " 配置: ${Red}未初始化${Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== WARP 管理 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  一键安装 WARP ${Cyan}(推荐)${Reset}"
        echo -e " ${Green}2.${Reset}  卸载 WARP"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}3.${Reset}  启动 WARP"
        echo -e " ${Green}4.${Reset}  停止 WARP"
        echo -e " ${Green}5.${Reset}  重启 WARP"
        echo -e " ${Green}6.${Reset}  查看状态"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}7.${Reset}  ${Yellow}Endpoint IP 优选${Reset}"
        echo -e " ${Green}8.${Reset}  ${Cyan}为现有节点配置 WARP 出站${Reset}"
        echo -e " ${Green}9.${Reset}  重新获取 WARP 配置"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}10.${Reset} 查看当前 IP"
        echo -e " ${Green}11.${Reset} 流媒体解锁检测"
        echo -e " ${Green}12.${Reset} 查看运行日志"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}========================================================${Reset}"
        
        read -p " 请选择 [0-12]: " choice
        
        case "$choice" in
            1) quick_install ;;
            2) uninstall_warp ;;
            3) start_warp_singbox ;;
            4) stop_warp_singbox ;;
            5) restart_warp_singbox ;;
            6) status_warp_singbox ;;
            7) endpoint_optimize_menu ;;
            8) configure_existing_warp_outbound ;;
            9) 
                init_warp_config
                generate_warp_singbox_config
                read -p "是否重启 WARP 使配置生效? [Y/n]: " restart_now
                [[ ! $restart_now =~ ^[Nn]$ ]] && restart_warp_singbox
                ;;
            10) show_ip ;;
            11) check_streaming ;;
            12) view_logs ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# ==================== 主程序 ====================
if [ "${BASH_SOURCE[0]}" = "${0}" ] || [ "$0" = "bash" ]; then
    show_warp_menu
fi
