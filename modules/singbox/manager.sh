#!/bin/bash
# sing-box 模块 - VPS-play
# 多协议代理节点管理
#
# Copyright (C) 2025 VPS-play Contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/singbox"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"
[ -z "$VPSPLAY_DIR" ] && VPSPLAY_DIR="$HOME/vps-play"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/port_manager.sh" ] && source "$VPSPLAY_DIR/utils/port_manager.sh"
[ -f "$VPSPLAY_DIR/utils/process_manager.sh" ] && source "$VPSPLAY_DIR/utils/process_manager.sh"
[ -f "$VPSPLAY_DIR/utils/network.sh" ] && source "$VPSPLAY_DIR/utils/network.sh"

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
SINGBOX_DIR="$HOME/.vps-play/singbox"
SINGBOX_BIN="$SINGBOX_DIR/sing-box"
SINGBOX_CONF="$SINGBOX_DIR/config.json"
SINGBOX_LOG="$SINGBOX_DIR/sing-box.log"
CERT_DIR="$SINGBOX_DIR/cert"
CONFIG_DIR="$SINGBOX_DIR/config"

# 流量统计 API 端口 (clash_api)
SINGBOX_API_PORT=9090

# sing-box 版本
SINGBOX_VERSION="1.12.0"
SINGBOX_REPO="https://github.com/SagerNet/sing-box"

mkdir -p "$SINGBOX_DIR" "$CERT_DIR" "$CONFIG_DIR"

# ==================== 参数持久化存储 (参照argosbx) ====================
DATA_DIR="$SINGBOX_DIR/data"
LINKS_FILE="$SINGBOX_DIR/links.txt"
mkdir -p "$DATA_DIR"

# 初始化/获取 UUID (参照argosbx的insuuid函数, 修复FreeBSD兼容性)
init_uuid() {
    # 首先尝试从文件读取（如果文件存在且非空）
    if [ -s "$DATA_DIR/uuid" ]; then
        uuid=$(cat "$DATA_DIR/uuid")
    fi
    
    # 如果 uuid 为空，则生成新的
    if [ -z "$uuid" ]; then
        # 方法1: 使用 sing-box 生成
        if [ -x "$SINGBOX_BIN" ]; then
            uuid=$("$SINGBOX_BIN" generate uuid 2>/dev/null)
        fi
        # 方法2: Linux /proc
        [ -z "$uuid" ] && uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
        # 方法3: uuidgen
        [ -z "$uuid" ] && uuid=$(uuidgen 2>/dev/null)
        # 方法4: 手动生成 (FreeBSD兼容，使用 LC_ALL=C 避免 Illegal byte sequence)
        if [ -z "$uuid" ]; then
            uuid=$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 8)-$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 4)-$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 4)-$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 4)-$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 12)
        fi
        # 方法5: 使用 od 作为最后备用 (FreeBSD)
        if [ -z "$uuid" ] || [ ${#uuid} -lt 32 ]; then
            uuid=$(od -An -tx1 -N 16 /dev/urandom 2>/dev/null | tr -d ' \n' | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/')
        fi
        
        # 保存到文件
        if [ -n "$uuid" ]; then
            if [ ! -d "$DATA_DIR" ]; then
                mkdir -p "$DATA_DIR"
            fi
            echo "$uuid" > "$DATA_DIR/uuid"
        fi
    fi
    
    # 最终验证
    if [ -z "$uuid" ]; then
        echo -e "${Error} UUID 生成失败"
        return 1
    fi
    
    echo -e "${Info} UUID/密码：${Cyan}$uuid${Reset}"
}

# 保存端口到文件
save_port() {
    local proto=$1
    local port=$2
    echo "$port" > "$DATA_DIR/port_${proto}"
}

# 读取端口
load_port() {
    local proto=$1
    cat "$DATA_DIR/port_${proto}" 2>/dev/null
}

# 获取服务器IP (参照argosbx的ipbest函数)
get_server_ip() {
    local serip
    serip=$(curl -s4m5 -k https://icanhazip.com 2>/dev/null || curl -s6m5 -k https://icanhazip.com 2>/dev/null)
    [ -z "$serip" ] && serip=$(curl -s4m5 ip.sb 2>/dev/null || curl -s6m5 ip.sb 2>/dev/null)
    [ -z "$serip" ] && serip="$PUBLIC_IP"
    
    if echo "$serip" | grep -q ':'; then
        server_ip="[$serip]"
    else
        server_ip="$serip"
    fi
    echo "$server_ip" > "$DATA_DIR/server_ip"
    echo "$server_ip"
}

# 生成 experimental 配置块 (可选，目前不使用)
# 流量统计已改为读取 VPS 系统网络接口流量
get_experimental_config() {
    # 返回空，不添加 experimental 配置
    echo ""
}

# ==================== WARP 内置支持 (参照 argosbx) ====================
WARP_DATA_DIR="$SINGBOX_DIR/warp"
mkdir -p "$WARP_DATA_DIR"

# 全局变量，标记是否启用 WARP 出站
WARP_ENABLED=false

# 初始化/获取 WARP 配置 (直接采用 argosbx 的方案)
init_warp_config() {
    echo -e "${Info} 获取 WARP 配置..."
    
    # 尝试从勇哥的 API 获取预注册配置
    local warpurl=""
    warpurl=$(curl -sm5 -k https://ygkkk-warp.renky.eu.org 2>/dev/null) || \
    warpurl=$(wget -qO- --timeout=5 https://ygkkk-warp.renky.eu.org 2>/dev/null)
    
    if echo "$warpurl" | grep -q ygkkk; then
        WARP_PRIVATE_KEY=$(echo "$warpurl" | awk -F'：' '/Private_key/{print $2}' | xargs)
        WARP_IPV6=$(echo "$warpurl" | awk -F'：' '/IPV6/{print $2}' | xargs)
        WARP_RESERVED=$(echo "$warpurl" | awk -F'：' '/reserved/{print $2}' | xargs)
        echo -e "${Info} WARP 配置获取成功 (远程)"
    else
        # 备用硬编码配置 (和 argosbx 一样)
        WARP_IPV6='2606:4700:110:8d8d:1845:c39f:2dd5:a03a'
        WARP_PRIVATE_KEY='52cuYFgCJXp0LAq7+nWJIbCXXgU9eGggOc+Hlfz5u6A='
        WARP_RESERVED='[215, 69, 233]'
        echo -e "${Info} WARP 配置获取成功 (备用)"
    fi
    
    # 保存配置供后续使用 (确保目录存在)
    mkdir -p "$WARP_DATA_DIR"
    echo "$WARP_PRIVATE_KEY" > "$WARP_DATA_DIR/private_key"
    echo "$WARP_RESERVED" > "$WARP_DATA_DIR/reserved"
    echo "$WARP_IPV6" > "$WARP_DATA_DIR/ipv6"
    
    return 0
}

# 询问是否启用 WARP 出站
ask_warp_outbound() {
    echo -e ""
    echo -e "${Cyan}是否启用 WARP 出站代理?${Reset}"
    echo -e "${Tip} 启用后，节点流量将通过 Cloudflare WARP 出站"
    echo -e "${Tip} 可用于解锁流媒体、隐藏真实 IP 等"
    echo -e ""
    read -p "启用 WARP 出站? [y/N]: " enable_warp
    
    if [[ "$enable_warp" =~ ^[Yy]$ ]]; then
        if init_warp_config; then
            WARP_ENABLED=true
            echo -e "${Info} WARP 出站已启用"
            
            # 智能优选: 自动测试并找到可用的 Endpoint
            smart_warp_optimize
        else
            WARP_ENABLED=false
            echo -e "${Warning} WARP 配置失败，将使用直连出站"
        fi
    else
        WARP_ENABLED=false
    fi
}

# ==================== WARP 智能优选 ====================
# CloudflareWarpSpeedTest 版本和下载地址
WARP_SPEEDTEST_VERSION="1.5.15"
WARP_SPEEDTEST_BIN="$SINGBOX_DIR/CloudflareWarpSpeedTest"
WARP_SPEEDTEST_RESULT="$SINGBOX_DIR/warp_result.csv"

# 下载 CloudflareWarpSpeedTest 工具
download_warp_speedtest() {
    if [ -f "$WARP_SPEEDTEST_BIN" ] && [ -x "$WARP_SPEEDTEST_BIN" ]; then
        return 0
    fi
    
    echo -e "${Info} 下载 WARP Endpoint 优选工具..."
    
    local os_type=""
    local arch_type=""
    
    case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
        linux) os_type="linux" ;;
        darwin) os_type="darwin" ;;
        freebsd) os_type="freebsd" ;;
        *) os_type="linux" ;;
    esac
    
    case "$(uname -m)" in
        x86_64|amd64) arch_type="amd64" ;;
        aarch64|arm64) arch_type="arm64" ;;
        armv7*) arch_type="armv7" ;;
        i686|i386) arch_type="386" ;;
        *) arch_type="amd64" ;;
    esac
    
    local download_url="https://github.com/peanut996/CloudflareWarpSpeedTest/releases/download/v${WARP_SPEEDTEST_VERSION}/CloudflareWarpSpeedTest-v${WARP_SPEEDTEST_VERSION}-${os_type}-${arch_type}.tar.gz"
    
    local tmp_file="/tmp/warp_speedtest.tar.gz"
    
    if curl -sL -o "$tmp_file" "$download_url" 2>/dev/null || wget -qO "$tmp_file" "$download_url" 2>/dev/null; then
        tar -xzf "$tmp_file" -C "$SINGBOX_DIR" 2>/dev/null
        # 二进制文件可能在子目录中，查找并移动
        local bin_path=$(find "$SINGBOX_DIR" -name "CloudflareWarpSpeedTest" -type f 2>/dev/null | head -n1)
        if [ -n "$bin_path" ] && [ "$bin_path" != "$WARP_SPEEDTEST_BIN" ]; then
            mv "$bin_path" "$WARP_SPEEDTEST_BIN"
        fi
        chmod +x "$WARP_SPEEDTEST_BIN"
        rm -f "$tmp_file"
        echo -e "${Info} 优选工具下载完成"
        return 0
    else
        echo -e "${Error} 优选工具下载失败"
        return 1
    fi
}

# 测试 WARP 是否能连通 Google (通过 sing-box 代理)
test_warp_connectivity() {
    local socks_port="${1:-1080}"
    local timeout="${2:-10}"
    
    # 使用 curl 通过 SOCKS5 代理测试 Google
    if curl -x "socks5h://127.0.0.1:${socks_port}" -sI -m "$timeout" "https://www.google.com" 2>/dev/null | grep -q "200"; then
        return 0
    fi
    
    # 备用: 测试 Cloudflare
    if curl -x "socks5h://127.0.0.1:${socks_port}" -sI -m "$timeout" "https://www.cloudflare.com" 2>/dev/null | grep -q "200"; then
        return 0
    fi
    
    return 1
}

# 运行 WARP Endpoint 优选
run_warp_speedtest() {
    if [ ! -f "$WARP_SPEEDTEST_BIN" ]; then
        download_warp_speedtest || return 1
    fi
    
    echo -e "${Info} 运行 Endpoint 优选 (约需 1-2 分钟)..."
    
    # 运行优选 (使用当前 WARP 配置)
    cd "$SINGBOX_DIR"
    "$WARP_SPEEDTEST_BIN" \
        -n 100 \
        -t 5 \
        -c 500 \
        -tl 300 \
        -tlr 0.5 \
        -p 20 \
        -pri "$WARP_PRIVATE_KEY" \
        -reserved "$WARP_RESERVED" \
        -o "$WARP_SPEEDTEST_RESULT" 2>/dev/null
    
    if [ -f "$WARP_SPEEDTEST_RESULT" ] && [ -s "$WARP_SPEEDTEST_RESULT" ]; then
        local count=$(tail -n +2 "$WARP_SPEEDTEST_RESULT" | wc -l)
        echo -e "${Info} 优选完成，找到 ${Cyan}$count${Reset} 个可用 Endpoint"
        return 0
    else
        echo -e "${Warning} 优选未找到可用 Endpoint"
        return 1
    fi
}

# 从优选结果获取第 N 个最佳 Endpoint
get_nth_endpoint() {
    local n=${1:-1}
    
    if [ ! -f "$WARP_SPEEDTEST_RESULT" ]; then
        return 1
    fi
    
    # CSV 格式: IP:Port,Latency,LossRate
    local line=$(tail -n +2 "$WARP_SPEEDTEST_RESULT" | sed -n "${n}p")
    if [ -n "$line" ]; then
        echo "$line" | cut -d',' -f1
        return 0
    fi
    return 1
}

# 更新 sing-box 配置中的 Endpoint
update_singbox_warp_endpoint() {
    local new_endpoint="$1"
    
    if [ ! -f "$SINGBOX_CONF" ] || [ -z "$new_endpoint" ]; then
        return 1
    fi
    
    # 解析 IP 和端口
    local ep_ip=""
    local ep_port="2408"
    
    if echo "$new_endpoint" | grep -q "]:"; then
        # IPv6 格式 [ip]:port
        ep_ip=$(echo "$new_endpoint" | sed 's/\]:.*/:/' | sed 's/^\[//' | sed 's/:$//')
        ep_port=$(echo "$new_endpoint" | sed 's/.*]://')
    elif echo "$new_endpoint" | grep -q ":"; then
        # IPv4 格式 ip:port
        ep_ip=$(echo "$new_endpoint" | cut -d: -f1)
        ep_port=$(echo "$new_endpoint" | cut -d: -f2)
    else
        ep_ip="$new_endpoint"
    fi
    
    # 使用 jq 或 sed 更新配置
    if command -v jq &>/dev/null; then
        local tmp_conf="${SINGBOX_CONF}.tmp"
        jq --arg ip "$ep_ip" --argjson port "$ep_port" \
            '.endpoints[0].peers[0].address = $ip | .endpoints[0].peers[0].port = $port' \
            "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
    else
        # 使用 sed 替换
        sed -i "s/\"address\": *\"[^\"]*\"/\"address\": \"$ep_ip\"/g" "$SINGBOX_CONF"
        sed -i "s/\"port\": *[0-9]*/\"port\": $ep_port/g" "$SINGBOX_CONF"
    fi
    
    # 保存到 endpoint 文件
    mkdir -p "$WARP_DATA_DIR"
    echo "$new_endpoint" > "$WARP_DATA_DIR/endpoint"
    
    return 0
}

# 禁用 WARP 出站，回退直连
disable_warp_outbound() {
    echo -e "${Warning} WARP 连通失败，回退到直连模式..."
    WARP_ENABLED=false
    
    # 如果配置文件已存在，移除 WARP 相关配置
    if [ -f "$SINGBOX_CONF" ] && command -v jq &>/dev/null; then
        local tmp_conf="${SINGBOX_CONF}.tmp"
        # 移除 endpoints 和 route，只保留 direct outbound
        jq 'del(.endpoints) | del(.route) | .outbounds = [{"type":"direct","tag":"direct"}]' \
            "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
    fi
}

# 智能 WARP 优选主流程 (对齐 argosbx: 先用默认 endpoint，失败后才优选)
smart_warp_optimize() {
    echo -e ""
    echo -e "${Cyan}========== WARP 配置 ==========${Reset}"
    
    # 检查是否已有保存的 Endpoint
    local warp_endpoint_file="$WARP_DATA_DIR/endpoint"
    if [ -f "$warp_endpoint_file" ]; then
        local saved_ep=$(cat "$warp_endpoint_file" 2>/dev/null)
        if [ -n "$saved_ep" ]; then
            echo -e "${Info} 使用已保存的 Endpoint: ${Cyan}$saved_ep${Reset}"
            echo -e "${Cyan}=================================${Reset}"
            return 0
        fi
    fi
    
    # 使用默认 endpoint (对齐 argosbx: engage.cloudflareclient.com:2408)
    # 根据网络环境选择 IPv4 或 IPv6
    local default_ep=""
    local has_ipv4=false
    local has_ipv6=false
    
    # 检测网络环境
    curl -s4m2 https://icanhazip.com -k >/dev/null 2>&1 && has_ipv4=true
    curl -s6m2 https://icanhazip.com -k >/dev/null 2>&1 && has_ipv6=true
    
    if [ "$has_ipv6" = true ] && [ "$has_ipv4" = false ]; then
        # 纯 IPv6 环境
        default_ep="[2606:4700:d0::a29f:c001]:2408"
        echo -e "${Info} 检测到纯 IPv6 环境"
    else
        # IPv4 或双栈环境
        default_ep="engage.cloudflareclient.com:2408"
    fi
    
    # 保存默认 endpoint
    mkdir -p "$WARP_DATA_DIR"
    echo "$default_ep" > "$WARP_DATA_DIR/endpoint"
    
    echo -e "${Info} 使用默认 Endpoint: ${Cyan}$default_ep${Reset}"
    echo -e "${Tip} 启动后将自动测试连通性，失败时触发优选"
    echo -e "${Cyan}=================================${Reset}"
    echo -e ""
}

# 节点安装后验证 WARP 连通性 (在服务启动后调用)
verify_warp_after_start() {
    if [ "$WARP_ENABLED" != true ]; then
        return 0
    fi
    
    local max_attempts=5
    local attempt=0
    
    echo -e ""
    echo -e "${Info} 验证 WARP 连通性..."
    sleep 2  # 等待服务完全启动
    
    # 首次测试
    if test_warp_connectivity; then
        echo -e "${Info} ${Green}WARP 连通正常!${Reset}"
        return 0
    fi
    
    echo -e "${Warning} 当前 Endpoint 无法连通 Google"
    
    # 检查优选结果文件
    if [ ! -f "$WARP_SPEEDTEST_RESULT" ]; then
        echo -e "${Info} 运行 Endpoint 优选..."
        run_warp_speedtest || {
            echo -e "${Warning} 优选失败，保持当前配置"
            return 1
        }
    fi
    
    # 循环尝试前 5 个 Endpoint
    while [ $attempt -lt $max_attempts ]; do
        ((attempt++))
        local ep=$(get_nth_endpoint $attempt)
        
        if [ -z "$ep" ]; then
            echo -e "${Warning} 已尝试所有可用 Endpoint"
            break
        fi
        
        local delay=$(tail -n +2 "$WARP_SPEEDTEST_RESULT" | sed -n "${attempt}p" | cut -d',' -f2)
        echo -e "${Info} 尝试 Endpoint #$attempt: ${Cyan}$ep${Reset} (延迟: ${delay}ms)"
        
        # 更新配置并重启
        update_singbox_warp_endpoint "$ep"
        restart_singbox_quiet
        sleep 2
        
        # 测试
        if test_warp_connectivity; then
            echo -e "${Info} ${Green}连通成功!${Reset}"
            echo -e "${Info} 已保存最佳 Endpoint: ${Cyan}$ep${Reset}"
            return 0
        fi
        
        echo -e "${Warning} 尝试 #$attempt 失败"
    done
    
    # 全部失败，回退直连
    echo -e "${Error} 所有 Endpoint 均无法连通"
    disable_warp_outbound
    restart_singbox_quiet
    echo -e "${Info} 已回退到直连模式"
    return 1
}

# 静默重启 sing-box
restart_singbox_quiet() {
    if command -v systemctl &>/dev/null; then
        systemctl restart sing-box 2>/dev/null
    else
        pkill -f "sing-box" 2>/dev/null
        sleep 1
        nohup "$SINGBOX_BIN" run -c "$SINGBOX_CONF" >/dev/null 2>&1 &
    fi
}


# 获取 WARP Endpoint 配置 (优先使用 WARP 模块的优选结果)
# 获取 WARP Endpoint 配置 (优先使用 WARP 模块的优选结果)
get_warp_endpoint() {
    # 优先读取 WARP 模块保存的优选 Endpoint
    local warp_endpoint_file="$HOME/.vps-play/warp/data/endpoint"
    if [ -f "$warp_endpoint_file" ]; then
        local saved_ep=$(cat "$warp_endpoint_file" 2>/dev/null)
        if [ -n "$saved_ep" ]; then
            echo "$saved_ep"
            return 0
        fi
    fi
    
    # 回退: 检测网络环境选择默认 Endpoint
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

# 生成 outbounds 和 route 配置
# 参数: $1 = 是否启用 WARP (true/false)
# 参照 argosbx 的实现：
# - 不启用 WARP: 只有 direct outbound，无 route 配置
# - 启用 WARP: outbounds (direct) + endpoints (warp-out) + route (final指向warp-out)
get_outbounds_config() {
    local enable_warp=${1:-false}
    
    if [ "$enable_warp" = true ] && [ -n "$WARP_PRIVATE_KEY" ]; then
        local warp_endpoint=$(get_warp_endpoint)
        local warp_ipv6="${WARP_IPV6:-2606:4700:110:8f1a:c53:a4c5:2249:1546}"
        local warp_reserved="${WARP_RESERVED:-[0,0,0]}"
        
        # 解析 Endpoint IP 和端口
        local ep_ip=""
        local ep_port="2408"
        
        if echo "$warp_endpoint" | grep -q "]:"; then
            # IPv6 格式 [ip]:port
            ep_ip=$(echo "$warp_endpoint" | sed 's/\]:.*/]/' | sed 's/^\[//' | sed 's/\]$//')
            ep_port=$(echo "$warp_endpoint" | sed 's/.*\]://')
        elif echo "$warp_endpoint" | grep -q ":"; then
            # IPv4 格式 ip:port
            ep_ip=$(echo "$warp_endpoint" | cut -d: -f1)
            ep_port=$(echo "$warp_endpoint" | cut -d: -f2)
        else
            ep_ip="$warp_endpoint"
        fi
        
        # 使用 Sing-box 1.12+ 的 endpoints 字段 (argosbx 方案)
        cat << WARP_EOF
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
        "action": "resolve",
        "strategy": "prefer_ipv4"
      }
    ],
    "final": "warp-out"
  }
WARP_EOF
    else
        # 默认直连出站 (参照 argosbx: 不启用 WARP 时无 route 配置)
        cat << DIRECT_EOF
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
DIRECT_EOF
    fi
}

# ==================== 系统检测 ====================
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Alpine")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "apk update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "apk add")

detect_system() {
    if [ -z "$OS_DISTRO" ]; then
        for i in /etc/os-release /etc/lsb-release /etc/redhat-release; do
            [ -f "$i" ] && SYS=$(cat "$i" | tr '[:upper:]' '[:lower:]')
        done
        
        for ((int = 0; int < ${#REGEX[@]}; int++)); do
            if [[ $SYS =~ ${REGEX[int]} ]]; then
                SYSTEM="${RELEASE[int]}"
                PKG_UPDATE="${PACKAGE_UPDATE[int]}"
                PKG_INSTALL="${PACKAGE_INSTALL[int]}"
                break
            fi
        done
    fi
}

# ==================== 获取 IP ====================
get_ip() {
    ip=$(curl -s4m5 ip.sb 2>/dev/null) || ip=$(curl -s6m5 ip.sb 2>/dev/null)
    [ -z "$ip" ] && ip="$PUBLIC_IP"
    echo "$ip"
}

# ==================== 证书管理 ====================
generate_self_signed_cert() {
    local domain=${1:-www.bing.com}
    
    echo -e "${Info} 生成自签名证书 (域名: $domain)..."
    
    if [ ! -d "$CERT_DIR" ]; then
        mkdir -p "$CERT_DIR"
    fi
    
    # 参照 argosbx: 使用 openssl 生成 EC 证书
    if command -v openssl >/dev/null 2>&1; then
        openssl ecparam -genkey -name prime256v1 -out "$CERT_DIR/private.key" >/dev/null 2>&1
        openssl req -new -x509 -days 36500 -key "$CERT_DIR/private.key" -out "$CERT_DIR/cert.pem" -subj "/CN=$domain" >/dev/null 2>&1
    fi
    
    # 如果生成失败，从 GitHub 下载备份证书 (参照 argosbx)
    if [ ! -f "$CERT_DIR/private.key" ] || [ ! -f "$CERT_DIR/cert.pem" ]; then
        echo -e "${Warning} 本地证书生成失败，正在下载备用证书..."
        
        if command -v curl >/dev/null 2>&1; then
            curl -Ls -o "$CERT_DIR/private.key" "https://github.com/yonggekkk/argosbx/releases/download/argosbx/private.key" 2>/dev/null
            curl -Ls -o "$CERT_DIR/cert.pem" "https://github.com/yonggekkk/argosbx/releases/download/argosbx/cert.pem" 2>/dev/null
        elif command -v wget >/dev/null 2>&1; then
            timeout 3 wget -q -O "$CERT_DIR/private.key" "https://github.com/yonggekkk/argosbx/releases/download/argosbx/private.key" --tries=2 2>/dev/null
            timeout 3 wget -q -O "$CERT_DIR/cert.pem" "https://github.com/yonggekkk/argosbx/releases/download/argosbx/cert.pem" --tries=2 2>/dev/null
        fi
    fi
    
    if [ -f "$CERT_DIR/cert.pem" ] && [ -f "$CERT_DIR/private.key" ]; then
        chmod 644 "$CERT_DIR/cert.pem" "$CERT_DIR/private.key"
        echo -e "${Info} 证书准备完成"
        echo -e " 证书路径: ${Cyan}$CERT_DIR/cert.pem${Reset}"
        echo -e " 私钥路径: ${Cyan}$CERT_DIR/private.key${Reset}"
        return 0
    else
        echo -e "${Error} 证书生成/下载失败"
        return 1
    fi
}

apply_acme_cert() {
    echo -e "${Info} 使用 ACME 申请真实证书"
    
    read -p "请输入域名: " domain
    [ -z "$domain" ] && { echo -e "${Error} 域名不能为空"; return 1; }
    
    # 检查域名解析
    local domain_ip=$(dig +short "$domain" 2>/dev/null | head -1)
    local server_ip=$(get_ip)
    
    if [ "$domain_ip" != "$server_ip" ]; then
        echo -e "${Warning} 域名解析的 IP ($domain_ip) 与服务器 IP ($server_ip) 不匹配"
        read -p "是否继续? [y/N]: " continue_acme
        [[ ! $continue_acme =~ ^[Yy]$ ]] && return 1
    fi
    
    # 安装 acme.sh
    if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        echo -e "${Info} 安装 acme.sh..."
        curl https://get.acme.sh | sh -s email=$(date +%s)@gmail.com
    fi
    
    # 申请证书
    echo -e "${Info} 申请证书..."
    ~/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 --insecure
    ~/.acme.sh/acme.sh --install-cert -d "$domain" \
        --key-file "$CERT_DIR/private.key" \
        --fullchain-file "$CERT_DIR/cert.pem" \
        --ecc
    
    if [ -f "$CERT_DIR/cert.pem" ] && [ -s "$CERT_DIR/cert.pem" ]; then
        echo "$domain" > "$CERT_DIR/domain.txt"
        echo -e "${Info} 证书申请成功"
        return 0
    else
        echo -e "${Error} 证书申请失败"
        return 1
    fi
}

cert_menu() {
    echo -e ""
    echo -e "${Info} 证书申请方式:"
    echo -e " ${Green}1.${Reset} 自签名证书 (默认，推荐)"
    echo -e " ${Green}2.${Reset} ACME 申请真实证书"
    echo -e " ${Green}3.${Reset} 使用已有证书"
    
    read -p "请选择 [1-3]: " cert_choice
    cert_choice=${cert_choice:-1}
    
    case "$cert_choice" in
        1)
            read -p "伪装域名 [www.bing.com]: " fake_domain
            fake_domain=${fake_domain:-www.bing.com}
            if ! generate_self_signed_cert "$fake_domain"; then
                return 1
            fi
            CERT_DOMAIN="$fake_domain"
            ;;
        2)
            if ! apply_acme_cert; then
                return 1
            fi
            CERT_DOMAIN=$(cat "$CERT_DIR/domain.txt" 2>/dev/null)
            ;;
        3)
            read -p "证书路径: " custom_cert
            read -p "私钥路径: " custom_key
            if [ -f "$custom_cert" ] && [ -f "$custom_key" ]; then
                cp "$custom_cert" "$CERT_DIR/cert.pem"
                cp "$custom_key" "$CERT_DIR/private.key"
                read -p "证书域名: " CERT_DOMAIN
            else
                echo -e "${Error} 证书文件不存在"
                return 1
            fi
            ;;
    esac
}

# ==================== 端口配置 ====================
config_port() {
    local proto_name=$1
    local default_port=$2
    
    echo -e "" >&2
    # read -p 输出默认就是 stderr，所以不用改
    read -p "设置 $proto_name 端口 [留空随机]: " port
    
    if [ -z "$port" ]; then
        port=$(shuf -i 10000-65535 -n 1)
    fi
    
    # 检查端口是否被占用
    while ss -tunlp 2>/dev/null | grep -qw ":$port "; do
        echo -e "${Warning} 端口 $port 已被占用" >&2
        port=$(shuf -i 10000-65535 -n 1)
        echo -e "${Info} 自动分配新端口: $port" >&2
    done
    
    echo -e "${Info} 使用端口: ${Cyan}$port${Reset}" >&2
    echo "$port"
}

# ==================== 下载安装 ====================
# 获取当前安装版本
get_version() {
    if [ -f "$SINGBOX_BIN" ]; then
        $SINGBOX_BIN version 2>/dev/null | head -n1 | awk '{print $3}'
    else
        echo ""
    fi
}

# 版本比较函数 (大于等于)
version_ge() {
    # 如果版本相同
    [ "$1" = "$2" ] && return 0
    
    # 尝试使用 sort -V
    if sort -V </dev/null >/dev/null 2>&1; then
        [ "$(echo -e "$1\n$2" | sort -V | head -n1)" = "$2" ]
    else
        # 手动解析版本号 (awk)
        # 假设版本号格式为 x.y.z
        local v1=$(echo "$1" | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }')
        local v2=$(echo "$2" | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }')
        [ "$v1" -ge "$v2" ] 2>/dev/null
    fi
}

download_singbox() {
    local target_version=${1:-$SINGBOX_VERSION}
    echo -e "${Info} 正在下载 sing-box v${target_version}..."
    
    # 确保目录存在
    mkdir -p "$SINGBOX_DIR" "$CERT_DIR" "$CONFIG_DIR"
    
    # 直接使用 uname 检测系统类型 (修复 Serv00/FreeBSD 检测)
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
    
    # 下载并解压
    echo -e "${Info} 下载地址: $download_url"
    
    local download_success=false
    
    # 尝试使用 wget 下载
    if command -v wget >/dev/null 2>&1; then
        if wget -q -O sing-box.tar.gz "$download_url"; then
            download_success=true
        else
             echo -e "${Warning} wget 下载失败，尝试 curl..."
        fi
    fi
    
    # 尝试使用 curl 下载 (如果 wget 失败或未安装)
    if [ "$download_success" = false ] && command -v curl >/dev/null 2>&1; then
        if curl -sL "$download_url" -o sing-box.tar.gz; then
            download_success=true
        else
            echo -e "${Error} curl 下载失败"
        fi
    fi
    
    if [ "$download_success" = false ]; then
        echo -e "${Error} 无法下载 sing-box，请检查网络连接或安装 wget/curl"
        [ -f "${SINGBOX_BIN}.bak" ] && mv "${SINGBOX_BIN}.bak" "$SINGBOX_BIN"
        return 1
    fi
    
    # 检查文件大小 (避免下载到空文件)
    if [ ! -s sing-box.tar.gz ]; then
        echo -e "${Error} 下载的文件为空"
        rm -f sing-box.tar.gz
        [ -f "${SINGBOX_BIN}.bak" ] && mv "${SINGBOX_BIN}.bak" "$SINGBOX_BIN"
        return 1
    fi

    # 简单检查文件头是否为 gzip (1f 8b)
    # 使用 hexdump 或 od，如果都没有则尝试直接解压
    local is_gzip=true
    if command -v head >/dev/null 2>&1 && command -v od >/dev/null 2>&1; then
        local magic=$(head -c 2 sing-box.tar.gz | od -An -t x1 | tr -d ' \n')
        if [ "$magic" != "1f8b" ]; then
            echo -e "${Error} 下载的文件不是有效的 gzip 文件 (Magic: $magic)"
            # 可能是 HTML 错误页面，显示前几行
            echo -e "${Info} 文件内容预览:"
            head -n 5 sing-box.tar.gz
            is_gzip=false
        fi
    fi

    if [ "$is_gzip" = false ]; then
        rm -f sing-box.tar.gz
        [ -f "${SINGBOX_BIN}.bak" ] && mv "${SINGBOX_BIN}.bak" "$SINGBOX_BIN"
        return 1
    fi
    
    # 解压 (FreeBSD 兼容)
    local extract_success=false
    if command -v gtar >/dev/null 2>&1; then
        gtar -xzf sing-box.tar.gz --strip-components=1 && extract_success=true
    else
        tar -xzf sing-box.tar.gz --strip-components=1 && extract_success=true
    fi
    
    if [ "$extract_success" = false ]; then
        echo -e "${Error} 解压失败"
        rm -f sing-box.tar.gz
        [ -f "${SINGBOX_BIN}.bak" ] && mv "${SINGBOX_BIN}.bak" "$SINGBOX_BIN"
        return 1
    fi
    
    rm -f sing-box.tar.gz
    chmod +x sing-box 2>/dev/null
    
    if [ -f "$SINGBOX_BIN" ] && [ -x "$SINGBOX_BIN" ]; then
        echo -e "${Info} sing-box 下载完成"
        $SINGBOX_BIN version
    else
        echo -e "${Error} 安装失败，还原旧版本..."
        [ -f "${SINGBOX_BIN}.bak" ] && mv "${SINGBOX_BIN}.bak" "$SINGBOX_BIN"
        return 1
    fi
}

# ==================== Hysteria2 配置 ====================
install_hysteria2() {
    echo -e ""
    echo -e "${Cyan}========== 安装 Hysteria2 节点 ==========${Reset}"
    
    # 确保 sing-box 已安装
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 初始化 UUID 作为密码
    init_uuid
    local password="$uuid"
    
    # 配置证书
    cert_menu
    
    # 配置端口 (尝试读取已保存的端口)
    local saved_port=$(load_port "hy2")
    if [ -n "$saved_port" ]; then
        echo -e "${Info} 检测到已保存的端口: $saved_port"
        read -p "使用此端口? [Y/n]: " use_saved
        if [[ ! $use_saved =~ ^[Nn]$ ]]; then
            port="$saved_port"
        else
            port=$(config_port "Hysteria2")
        fi
    else
        port=$(config_port "Hysteria2")
    fi
    
    # 保存端口
    save_port "hy2" "$port"
    echo -e "${Info} Hysteria2 端口: ${Cyan}$port${Reset}"
    
    # 端口跳跃
    echo -e ""
    echo -e "${Info} 是否启用端口跳跃?"
    echo -e " ${Green}1.${Reset} 否，单端口 (默认)"
    echo -e " ${Green}2.${Reset} 是，端口跳跃"
    read -p "请选择 [1-2]: " jump_choice
    
    local port_hopping=""
    if [ "$jump_choice" = "2" ]; then
        read -p "起始端口: " start_port
        read -p "结束端口: " end_port
        if [ -n "$start_port" ] && [ -n "$end_port" ]; then
            # 设置 iptables 规则
            iptables -t nat -A PREROUTING -p udp --dport ${start_port}:${end_port} -j REDIRECT --to-ports $port 2>/dev/null
            ip6tables -t nat -A PREROUTING -p udp --dport ${start_port}:${end_port} -j REDIRECT --to-ports $port 2>/dev/null
            port_hopping="${start_port}-${end_port}"
            echo "$port_hopping" > "$DATA_DIR/hy2_hopping"
            echo -e "${Info} 端口跳跃已配置: $port_hopping -> $port"
        fi
    fi
    
    # 询问是否启用 WARP 出站
    ask_warp_outbound
    
    # 生成配置
    local exp_config=$(get_experimental_config)
    local outbounds_config=$(get_outbounds_config "$WARP_ENABLED")
    
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
${exp_config}  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-sb",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "password": "$password"
        }
      ],
      "ignore_client_bandwidth": false,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$CERT_DIR/cert.pem",
        "key_path": "$CERT_DIR/private.key"
      }
    }
  ],
${outbounds_config}
}
EOF

    echo -e ""
    echo -e "${Green}========== Hysteria2 安装完成 ==========${Reset}"
    
    # 显示节点信息
    display_all_nodes
    
    # 询问是否启动
    read -p "是否立即启动? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}


# ==================== AnyTLS 配置 ====================
install_anytls() {
    echo -e ""
    echo -e "${Cyan}========== 安装 AnyTLS 节点 ==========${Reset}"
    
    # 1. 版本检查与升级
    local min_ver="1.12.0"
    local current_ver=""
    
    if [ -f "$SINGBOX_BIN" ]; then
        current_ver=$($SINGBOX_BIN version 2>/dev/null | head -n1 | awk '{print $3}')
    fi
    
    if [ -z "$current_ver" ] || ! version_ge "$current_ver" "$min_ver"; then
        echo -e "${Warning} AnyTLS 需要 sing-box v${min_ver}+ (当前: ${current_ver:-未安装})"
        echo -e "${Info} 正在自动升级内核..."
        download_singbox "$min_ver"
        if [ $? -ne 0 ]; then
             echo -e "${Error} 内核升级失败，无法安装 AnyTLS"
             return 1
        fi
    fi
    
    # 2. 初始化 UUID 作为密码
    init_uuid
    local password="$uuid"
    
    # 3. 配置端口 (尝试读取已保存的端口)
    local saved_port=$(load_port "anytls")
    if [ -n "$saved_port" ]; then
        echo -e "${Info} 检测到已保存的端口: $saved_port"
        read -p "使用此端口? [Y/n]: " use_saved
        if [[ ! $use_saved =~ ^[Nn]$ ]]; then
            port="$saved_port"
        else
            port=$(config_port "AnyTLS")
        fi
    else
        port=$(config_port "AnyTLS")
    fi
    
    # 保存端口
    save_port "anytls" "$port"
    echo -e "${Info} AnyTLS 端口: ${Cyan}$port${Reset}"
    
    # 4. 生成自签证书（参照 argosbx 统一证书管理）
    echo -e "${Info} 生成自签证书..."
    if ! generate_self_signed_cert "bing.com"; then
        echo -e "${Error} 证书准备失败"
        return 1
    fi
    
    # 5. 询问是否启用 WARP 出站
    ask_warp_outbound
    
    # 6. 生成配置文件
    local outbounds_config=$(get_outbounds_config "$WARP_ENABLED")
    
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-sb",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "password": "$password"
        }
      ],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "certificate_path": "$CERT_DIR/cert.pem",
        "key_path": "$CERT_DIR/private.key"
      }
    }
  ],
${outbounds_config}
}
EOF

    echo -e ""
    echo -e "${Green}========== AnyTLS 安装完成 ==========${Reset}"
    
    # 显示节点信息
    display_all_nodes
    
    # 询问是否启动
    read -p "是否立即启动? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# ==================== Any-Reality 配置 (AnyTLS + Reality) ====================
install_any_reality() {
    echo -e ""
    echo -e "${Cyan}========== 安装 Any-Reality 节点 ==========${Reset}"
    echo -e "${Info} Any-Reality 是 AnyTLS 协议与 Reality 的组合"
    
    # 1. 版本检查与升级
    local min_ver="1.12.0"
    local current_ver=""
    
    if [ -f "$SINGBOX_BIN" ]; then
        current_ver=$($SINGBOX_BIN version 2>/dev/null | head -n1 | awk '{print $3}')
    fi
    
    if [ -z "$current_ver" ] || ! version_ge "$current_ver" "$min_ver"; then
        echo -e "${Warning} Any-Reality 需要 sing-box v${min_ver}+ (当前: ${current_ver:-未安装})"
        echo -e "${Info} 正在自动升级内核..."
        download_singbox "$min_ver"
        if [ $? -ne 0 ]; then
             echo -e "${Error} 内核升级失败，无法安装 Any-Reality"
             return 1
        fi
    fi
    
    # 2. 初始化 UUID 作为密码
    init_uuid
    local password="$uuid"
    
    # 3. 配置端口 (尝试读取已保存的端口)
    local saved_port=$(load_port "anyreality")
    if [ -n "$saved_port" ]; then
        echo -e "${Info} 检测到已保存的端口: $saved_port"
        read -p "使用此端口? [Y/n]: " use_saved
        if [[ ! $use_saved =~ ^[Nn]$ ]]; then
            port="$saved_port"
        else
            port=$(config_port "Any-Reality")
        fi
    else
        port=$(config_port "Any-Reality")
    fi
    
    # 保存端口
    save_port "anyreality" "$port"
    echo -e "${Info} Any-Reality 端口: ${Cyan}$port${Reset}"
    
    # 4. Reality 配置
    echo -e ""
    read -p "目标网站 (dest) [apple.com]: " dest
    dest=${dest:-apple.com}
    echo "$dest" > "$DATA_DIR/ym_vl_re"
    
    read -p "Server Name [${dest}]: " server_name
    server_name=${server_name:-$dest}
    
    # 5. 生成 Reality 密钥对 (参照argosbx)
    echo -e "${Info} 生成 Reality 密钥对..."
    mkdir -p "$CERT_DIR/reality"
    
    if [ -e "$CERT_DIR/reality/private_key" ]; then
        # 已存在，读取
        private_key=$(cat "$CERT_DIR/reality/private_key")
        public_key=$(cat "$CERT_DIR/reality/public_key")
        short_id=$(cat "$CERT_DIR/reality/short_id")
        echo -e "${Info} 使用已存在的 Reality 密钥"
    else
        # 生成新密钥对
        local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
        private_key=$(echo "$keypair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
        public_key=$(echo "$keypair" | awk '/PublicKey/ {print $2}' | tr -d '"')
        short_id=$($SINGBOX_BIN generate rand --hex 4 2>/dev/null || head /dev/urandom | tr -dc a-f0-9 | head -c 8)
        
        # 保存
        echo "$private_key" > "$CERT_DIR/reality/private_key"
        echo "$public_key" > "$CERT_DIR/reality/public_key"
        echo "$short_id" > "$CERT_DIR/reality/short_id"
        echo -e "${Info} Reality 密钥生成完成"
    fi
    
    # 6. 询问是否启用 WARP 出站
    ask_warp_outbound
    
    # 7. 生成配置文件
    local outbounds_config=$(get_outbounds_config "$WARP_ENABLED")
    
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anyreality-sb",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "password": "$password"
        }
      ],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "server_name": "$server_name",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$dest",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    }
  ],
${outbounds_config}
}
EOF

    echo -e ""
    echo -e "${Green}========== Any-Reality 安装完成 ==========${Reset}"
    
    # 显示节点信息
    display_all_nodes
    
    # 询问是否启动
    read -p "是否立即启动? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# ==================== TUIC 配置 ====================
install_tuic() {
    echo -e ""
    echo -e "${Cyan}========== 安装 TUIC 节点 ==========${Reset}"
    
    # 确保 sing-box 已安装
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 初始化 UUID 
    init_uuid
    local tuic_uuid="$uuid"
    local password="$uuid"   # TUIC 的 password 和 uuid 相同 (参照argosbx)
    
    # 配置证书
    cert_menu
    
    # 配置端口 (尝试读取已保存的端口)
    local saved_port=$(load_port "tuic")
    if [ -n "$saved_port" ]; then
        echo -e "${Info} 检测到已保存的端口: $saved_port"
        read -p "使用此端口? [Y/n]: " use_saved
        if [[ ! $use_saved =~ ^[Nn]$ ]]; then
            port="$saved_port"
        else
            port=$(config_port "TUIC")
        fi
    else
        port=$(config_port "TUIC")
    fi
    
    # 保存端口
    save_port "tuic" "$port"
    echo -e "${Info} TUIC 端口: ${Cyan}$port${Reset}"
    
    # 拥塞控制
    echo -e ""
    echo -e "${Info} 选择拥塞控制算法:"
    echo -e " ${Green}1.${Reset} bbr (默认)"
    echo -e " ${Green}2.${Reset} cubic"
    echo -e " ${Green}3.${Reset} new_reno"
    read -p "请选择 [1-3]: " cc_choice
    
    local congestion="bbr"
    case "$cc_choice" in
        2) congestion="cubic" ;;
        3) congestion="new_reno" ;;
    esac
    
    # 询问是否启用 WARP 出站
    ask_warp_outbound
    
    # 生成配置
    local exp_config=$(get_experimental_config)
    local outbounds_config=$(get_outbounds_config "$WARP_ENABLED")
    
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
${exp_config}  "inbounds": [
    {
      "type": "tuic",
      "tag": "tuic5-sb",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "uuid": "$tuic_uuid",
          "password": "$password"
        }
      ],
      "congestion_control": "$congestion",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$CERT_DIR/cert.pem",
        "key_path": "$CERT_DIR/private.key"
      }
    }
  ],
${outbounds_config}
}
EOF

    echo -e ""
    echo -e "${Green}========== TUIC 安装完成 ==========${Reset}"
    
    # 显示节点信息
    display_all_nodes
    
    # 询问是否启动
    read -p "是否立即启动? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# ==================== VLESS Reality 配置 ====================
install_vless_reality() {
    echo -e ""
    echo -e "${Cyan}========== 安装 VLESS Reality 节点 ==========${Reset}"
    
    # 确保 sing-box 已安装
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 初始化 UUID
    init_uuid
    local vless_uuid="$uuid"
    
    # 配置端口 (尝试读取已保存的端口)
    local saved_port=$(load_port "vless")
    if [ -n "$saved_port" ]; then
        echo -e "${Info} 检测到已保存的端口: $saved_port"
        read -p "使用此端口? [Y/n]: " use_saved
        if [[ ! $use_saved =~ ^[Nn]$ ]]; then
            port="$saved_port"
        else
            port=$(config_port "VLESS Reality")
        fi
    else
        port=$(config_port "VLESS Reality")
    fi
    
    # 保存端口
    save_port "vless" "$port"
    echo -e "${Info} VLESS Reality 端口: ${Cyan}$port${Reset}"
    
    # Reality 配置
    echo -e ""
    read -p "目标网站 (dest) [apple.com]: " dest
    dest=${dest:-apple.com}
    echo "$dest" > "$DATA_DIR/ym_vl_re"
    
    read -p "Server Name [${dest}]: " server_name
    server_name=${server_name:-$dest}
    
    # 生成 Reality 密钥对 (参照argosbx，复用已有密钥)
    echo -e "${Info} 生成 Reality 密钥对..."
    mkdir -p "$CERT_DIR/reality"
    
    if [ -e "$CERT_DIR/reality/private_key" ]; then
        private_key=$(cat "$CERT_DIR/reality/private_key")
        public_key=$(cat "$CERT_DIR/reality/public_key")
        short_id=$(cat "$CERT_DIR/reality/short_id")
        echo -e "${Info} 使用已存在的 Reality 密钥"
    else
        local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
        private_key=$(echo "$keypair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
        public_key=$(echo "$keypair" | awk '/PublicKey/ {print $2}' | tr -d '"')
        short_id=$($SINGBOX_BIN generate rand --hex 4 2>/dev/null || head /dev/urandom | tr -dc a-f0-9 | head -c 8)
        
        echo "$private_key" > "$CERT_DIR/reality/private_key"
        echo "$public_key" > "$CERT_DIR/reality/public_key"
        echo "$short_id" > "$CERT_DIR/reality/short_id"
        echo -e "${Info} Reality 密钥生成完成"
    fi
    
    # 询问是否启用 WARP 出站
    ask_warp_outbound
    
    # 生成配置
    local outbounds_config=$(get_outbounds_config "$WARP_ENABLED")
    
    cat > "$SINGBOX_CONF" << EOF
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
      "users": [
        {
          "uuid": "$vless_uuid",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$server_name",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$dest",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    }
  ],
${outbounds_config}
}
EOF

    echo -e ""
    echo -e "${Green}========== VLESS Reality 安装完成 ==========${Reset}"
    
    # 显示节点信息
    display_all_nodes
    
    # 询问是否启动
    read -p "是否立即启动? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# ==================== 服务管理 ====================
start_singbox() {
    if [ ! -f "$SINGBOX_BIN" ]; then
        echo -e "${Error} sing-box 未安装"
        return 1
    fi
    
    if [ ! -f "$SINGBOX_CONF" ]; then
        echo -e "${Error} 配置文件不存在"
        return 1
    fi
    
    echo -e "${Info} 启动 sing-box..."
    
    # 使用 systemd 或 OpenRC 或 nohup
    if [ "$HAS_SYSTEMD" = true ] && [ "$HAS_ROOT" = true ]; then
        # 创建 systemd 服务
        cat > /etc/systemd/system/sing-box.service << EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
Type=simple
ExecStart=$SINGBOX_BIN run -c $SINGBOX_CONF
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable sing-box
        systemctl start sing-box
        
        sleep 2
        if systemctl is-active sing-box &>/dev/null; then
            echo -e "${Info} sing-box 启动成功 (systemd)"
        else
            echo -e "${Error} 启动失败"
            echo -e "${Info} 配置检查结果："
            echo -e "===================="
            "$SINGBOX_BIN" check -c "$SINGBOX_CONF" 2>&1 || true
            echo -e "===================="
            echo -e "${Info} systemd 状态："
            systemctl status sing-box --no-pager
        fi
    elif [ "$HAS_OPENRC" = true ] && [ "$HAS_ROOT" = true ]; then
        # 创建 OpenRC 服务 (Alpine Linux)
        cat > /etc/init.d/sing-box << 'OPENRC_EOF'
#!/sbin/openrc-run

name="sing-box"
description="sing-box service"
command="SINGBOX_BIN_PLACEHOLDER"
command_args="run -c SINGBOX_CONF_PLACEHOLDER"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"
output_log="/var/log/sing-box.log"
error_log="/var/log/sing-box.log"

depend() {
    need net
    after firewall
}
OPENRC_EOF
        # 替换占位符
        sed -i "s|SINGBOX_BIN_PLACEHOLDER|$SINGBOX_BIN|g" /etc/init.d/sing-box
        sed -i "s|SINGBOX_CONF_PLACEHOLDER|$SINGBOX_CONF|g" /etc/init.d/sing-box
        
        chmod +x /etc/init.d/sing-box
        rc-update add sing-box default 2>/dev/null
        rc-service sing-box start
        
        sleep 2
        if rc-service sing-box status &>/dev/null; then
            echo -e "${Info} sing-box 启动成功 (OpenRC)"
        else
            echo -e "${Error} 启动失败"
            echo -e "${Info} 配置检查结果："
            "$SINGBOX_BIN" check -c "$SINGBOX_CONF" 2>&1 || true
        fi
    else
        # 使用 nohup
        start_process "singbox" "$SINGBOX_BIN run -c $SINGBOX_CONF" "$SINGBOX_DIR"
    fi
}

stop_singbox() {
    if [ ! -f "$SINGBOX_BIN" ]; then
        echo -e "${Warning} sing-box 未安装"
        return 1
    fi
    
    if ! pgrep -f "sing-box" &>/dev/null; then
        echo -e "${Warning} sing-box 未在运行"
        return 0
    fi
    
    echo -e "${Info} 停止 sing-box..."
    
    if [ "$HAS_SYSTEMD" = true ] && [ "$HAS_ROOT" = true ]; then
        systemctl stop sing-box 2>/dev/null
    elif [ "$HAS_OPENRC" = true ] && [ "$HAS_ROOT" = true ]; then
        rc-service sing-box stop 2>/dev/null
    else
        stop_process "singbox"
    fi
    
    pkill -f "sing-box" 2>/dev/null
    echo -e "${Info} sing-box 已停止"
}

restart_singbox() {
    stop_singbox
    sleep 1
    start_singbox
}

status_singbox() {
    if [ ! -f "$SINGBOX_BIN" ]; then
        echo -e "${Warning} sing-box 未安装"
        echo -e "${Tip} 请先选择 [1-3] 安装节点"
        return 1
    fi
    
    echo -e "${Info} sing-box 状态:"
    
    if pgrep -f "sing-box" &>/dev/null; then
        echo -e "  运行状态: ${Green}运行中${Reset}"
        echo -e "  进程 PID: $(pgrep -f 'sing-box' | head -1)"
    else
        echo -e "  运行状态: ${Red}已停止${Reset}"
    fi
    
    if [ -f "$SINGBOX_CONF" ]; then
        echo -e "  配置文件: ${Cyan}$SINGBOX_CONF${Reset}"
    fi
}

# ==================== 统一节点信息输出 (参照argosbx的cip函数) ====================
display_all_nodes() {
    local server_ip=$(get_server_ip)
    local uuid=$(cat "$DATA_DIR/uuid" 2>/dev/null)
    local hostname=$(hostname 2>/dev/null || echo "vps")
    
    rm -f "$LINKS_FILE"
    
    echo -e ""
    echo -e "${Green}*********************************************************${Reset}"
    echo -e "${Green}*             VPS-play 节点配置信息                     *${Reset}"
    echo -e "${Green}*********************************************************${Reset}"
    echo -e ""
    echo -e " 服务器IP: ${Cyan}$server_ip${Reset}"
    echo -e " UUID/密码: ${Cyan}$uuid${Reset}"
    echo -e ""
    
    # 检测并显示 Hysteria2 节点
    if [ -f "$SINGBOX_CONF" ] && grep -q '"type": "hysteria2"' "$SINGBOX_CONF" 2>/dev/null; then
        local hy2_port=$(load_port "hy2")
        [ -z "$hy2_port" ] && hy2_port=$(grep -A5 '"hysteria2"' "$SINGBOX_CONF" | grep "listen_port" | grep -o '[0-9]*' | head -1)
        local hy2_password=$(grep -A10 '"hysteria2"' "$SINGBOX_CONF" | grep '"password"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$hy2_password" ] && hy2_password="$uuid"
        
        echo -e "💣【 Hysteria2 】节点信息如下："
        local hy2_link="hysteria2://${hy2_password}@${server_ip}:${hy2_port}?security=tls&alpn=h3&insecure=1&sni=www.bing.com#${hostname}-hy2"
        echo "$hy2_link" >> "$LINKS_FILE"
        echo -e "${Yellow}$hy2_link${Reset}"
        echo -e ""
    fi
    
    # 检测并显示 TUIC 节点
    if [ -f "$SINGBOX_CONF" ] && grep -q '"type": "tuic"' "$SINGBOX_CONF" 2>/dev/null; then
        local tuic_port=$(load_port "tuic")
        [ -z "$tuic_port" ] && tuic_port=$(grep -A5 '"tuic"' "$SINGBOX_CONF" | grep "listen_port" | grep -o '[0-9]*' | head -1)
        local tuic_uuid=$(grep -A10 '"tuic"' "$SINGBOX_CONF" | grep '"uuid"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$tuic_uuid" ] && tuic_uuid="$uuid"
        local tuic_password="$tuic_uuid"
        
        echo -e "💣【 TUIC 】节点信息如下："
        local tuic_link="tuic://${tuic_uuid}:${tuic_password}@${server_ip}:${tuic_port}?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1&allowInsecure=1#${hostname}-tuic"
        echo "$tuic_link" >> "$LINKS_FILE"
        echo -e "${Yellow}$tuic_link${Reset}"
        echo -e ""
    fi
    
    # 检测并显示 AnyTLS 节点 (不含 reality)
    if [ -f "$SINGBOX_CONF" ] && grep -q '"type": "anytls"' "$SINGBOX_CONF" 2>/dev/null && ! grep -q '"anyreality' "$SINGBOX_CONF" 2>/dev/null; then
        local an_port=$(load_port "anytls")
        [ -z "$an_port" ] && an_port=$(grep -A5 '"anytls"' "$SINGBOX_CONF" | grep "listen_port" | grep -o '[0-9]*' | head -1)
        local an_password=$(grep -A10 '"anytls"' "$SINGBOX_CONF" | grep '"password"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$an_password" ] && an_password="$uuid"
        
        echo -e "💣【 AnyTLS 】节点信息如下："
        local an_link="anytls://${an_password}@${server_ip}:${an_port}?insecure=1&allowInsecure=1#${hostname}-anytls"
        echo "$an_link" >> "$LINKS_FILE"
        echo -e "${Yellow}$an_link${Reset}"
        echo -e ""
    fi
    
    # 检测并显示 Any-Reality 节点
    if [ -f "$SINGBOX_CONF" ] && grep -q '"anyreality' "$SINGBOX_CONF" 2>/dev/null; then
        local ar_port=$(load_port "anyreality")
        [ -z "$ar_port" ] && ar_port=$(grep -A5 '"anyreality' "$SINGBOX_CONF" | grep "listen_port" | grep -o '[0-9]*' | head -1)
        local ar_password=$(grep -A10 '"anyreality' "$SINGBOX_CONF" | grep '"password"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$ar_password" ] && ar_password="$uuid"
        local public_key=$(cat "$CERT_DIR/reality/public_key" 2>/dev/null)
        local short_id=$(cat "$CERT_DIR/reality/short_id" 2>/dev/null)
        local sni=$(grep -A20 '"anyreality' "$SINGBOX_CONF" | grep '"server_name"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$sni" ] && sni="apple.com"
        
        echo -e "💣【 Any-Reality 】节点信息如下："
        local ar_link="anytls://${ar_password}@${server_ip}:${ar_port}?security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#${hostname}-any-reality"
        echo "$ar_link" >> "$LINKS_FILE"
        echo -e "${Yellow}$ar_link${Reset}"
        echo -e ""
    fi
    
    # 检测并显示 VLESS Reality 节点
    if [ -f "$SINGBOX_CONF" ] && grep -q '"type": "vless"' "$SINGBOX_CONF" 2>/dev/null; then
        local vl_port=$(load_port "vless")
        [ -z "$vl_port" ] && vl_port=$(grep -A5 '"vless"' "$SINGBOX_CONF" | grep "listen_port" | grep -o '[0-9]*' | head -1)
        local vl_uuid=$(grep -A10 '"vless"' "$SINGBOX_CONF" | grep '"uuid"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$vl_uuid" ] && vl_uuid="$uuid"
        local public_key=$(cat "$CERT_DIR/reality/public_key" 2>/dev/null)
        local short_id=$(cat "$CERT_DIR/reality/short_id" 2>/dev/null)
        local sni=$(grep -A20 '"vless"' "$SINGBOX_CONF" | grep '"server_name"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$sni" ] && sni="apple.com"
        
        echo -e "💣【 VLESS-tcp-reality-vision 】节点信息如下："
        local vl_link="vless://${vl_uuid}@${server_ip}:${vl_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#${hostname}-vless-reality"
        echo "$vl_link" >> "$LINKS_FILE"
        echo -e "${Yellow}$vl_link${Reset}"
        echo -e ""
    fi
    
    # 检测并显示 Shadowsocks 节点
    if [ -f "$SINGBOX_CONF" ] && grep -q '"type": "shadowsocks"' "$SINGBOX_CONF" 2>/dev/null; then
        local ss_port=$(load_port "ss")
        [ -z "$ss_port" ] && ss_port=$(grep -A5 '"shadowsocks"' "$SINGBOX_CONF" | grep "listen_port" | grep -o '[0-9]*' | head -1)
        local ss_password=$(grep -A10 '"shadowsocks"' "$SINGBOX_CONF" | grep '"password"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        local ss_method=$(grep -A10 '"shadowsocks"' "$SINGBOX_CONF" | grep '"method"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$ss_method" ] && ss_method="2022-blake3-aes-128-gcm"
        
        echo -e "💣【 Shadowsocks-2022 】节点信息如下："
        local ss_link="ss://$(echo -n "${ss_method}:${ss_password}@${server_ip}:${ss_port}" | base64 -w0)#${hostname}-ss"
        echo "$ss_link" >> "$LINKS_FILE"
        echo -e "${Yellow}$ss_link${Reset}"
        echo -e ""
    fi
    
    echo -e "---------------------------------------------------------"
    echo -e "聚合节点信息已保存到: ${Cyan}$LINKS_FILE${Reset}"
    echo -e "可运行 ${Yellow}cat $LINKS_FILE${Reset} 查看"
    echo -e "========================================================="
}

# ==================== 节点信息 ====================
show_node_info() {
    while true; do
        clear
        
        # 使用统一的节点信息输出函数
        display_all_nodes
        
        # 操作菜单
        echo -e ""
        echo -e "${Info} 节点管理选项:"
        echo -e " ${Green}1.${Reset} 添加新节点 (保留现有节点)"
        echo -e " ${Green}2.${Reset} 重装现有节点 (重新生成配置)"
        echo -e " ${Green}3.${Reset} 修改节点参数"
        echo -e " ${Green}4.${Reset} 复制分享链接到剪贴板"
        echo -e " ${Green}0.${Reset} 返回"
        echo -e ""
        
        read -p " 请选择 [0-4]: " node_choice
        
        case "$node_choice" in
            1) add_node_to_existing ;;
            2) reinstall_existing_node ;;
            3) modify_node_params ;;
            4) copy_share_links ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        read -p "按回车继续..."
    done
}

# 添加新节点到现有配置
add_node_to_existing() {
    echo -e ""
    echo -e "${Cyan}========== 添加新节点 ==========${Reset}"
    echo -e "${Tip} 在当前运行的节点基础上添加新节点"
    echo -e ""
    echo -e " ${Green}1.${Reset} Hysteria2"
    echo -e " ${Green}2.${Reset} TUIC v5"
    echo -e " ${Green}3.${Reset} VLESS Reality"
    echo -e " ${Green}4.${Reset} AnyTLS"
    echo -e " ${Green}5.${Reset} Any-Reality"
    echo -e " ${Green}0.${Reset} 取消"
    echo -e ""
    
    read -p " 请选择要添加的协议 [0-5]: " add_choice
    
    case "$add_choice" in
        1) add_protocol_hy2 ;;
        2) add_protocol_tuic ;;
        3) add_protocol_vless ;;
        4) add_protocol_anytls ;;
        5) add_protocol_any_reality ;;
        0) return 0 ;;
        *) echo -e "${Error} 无效选择" ;;
    esac
}

# 添加 Hysteria2 协议到现有配置
add_protocol_hy2() {
    echo -e "${Info} 添加 Hysteria2 节点..."
    
    # 检查证书
    if [ ! -f "$CERT_DIR/cert.pem" ]; then
        echo -e "${Info} 需要配置 TLS 证书"
        cert_menu
    fi
    
    local port=$(config_port "Hysteria2")
    read -p "设置密码 [留空随机]: " password
    [ -z "$password" ] && password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    # 读取现有配置并添加新 inbound
    if [ -f "$SINGBOX_CONF" ]; then
        local server_ip=$(get_ip)
        local new_inbound="{\"type\":\"hysteria2\",\"tag\":\"hy2-add\",\"listen\":\"::\",\"listen_port\":${port},\"users\":[{\"password\":\"${password}\"}],\"tls\":{\"enabled\":true,\"alpn\":[\"h3\"],\"certificate_path\":\"${CERT_DIR}/cert.pem\",\"key_path\":\"${CERT_DIR}/private.key\"}}"
        
        # 使用 jq 添加 inbound
        if command -v jq &>/dev/null; then
            local tmp_conf="${SINGBOX_CONF}.tmp"
            jq ".inbounds += [$new_inbound]" "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
        else
            echo -e "${Warning} 需要 jq 来修改配置"
            echo -e "${Tip} 请安装: apt install jq 或 yum install jq 或 apk add jq"
            return 1
        fi
        
        # 生成链接
        local hy2_link="hysteria2://${password}@${server_ip}:${port}?sni=${CERT_DOMAIN:-www.bing.com}&insecure=1#Hy2-Add-${server_ip}"
        echo "$hy2_link" >> "$SINGBOX_DIR/combo_links.txt"
        
        # 更新节点信息
        echo -e "\n[Hysteria2-Added]\n端口: ${port}\n密码: ${password}" >> "$SINGBOX_DIR/node_info.txt"
        
        echo -e "${Info} Hysteria2 节点已添加"
        echo -e "${Yellow}${hy2_link}${Reset}"
        
        # 重启服务
        restart_singbox
    else
        echo -e "${Error} 配置文件不存在"
    fi
}

# 添加 AnyTLS 协议到现有配置
add_protocol_anytls() {
    echo -e "${Info} 添加 AnyTLS 节点..."
    
    # 版本检查
    if ! version_ge "$(get_version)" "1.12.0"; then
        echo -e "${Info} AnyTLS 需要升级 sing-box 到 1.12.0+"
        download_singbox "1.12.0"
    fi
    
    local port=$(config_port "AnyTLS")
    read -p "设置密码 [留空随机]: " password
    [ -z "$password" ] && password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    local cert_domain="bing.com"
    local internal_port=$(shuf -i 20000-60000 -n 1)
    
    # 生成自签证书
    if [ ! -f "$CERT_DIR/anytls.key" ]; then
        openssl req -x509 -newkey ec:<(openssl ecparam -name prime256v1) \
            -keyout "$CERT_DIR/anytls.key" -out "$CERT_DIR/anytls.crt" \
            -days 36500 -nodes -subj "/CN=$cert_domain" 2>/dev/null
    fi
    
    if [ -f "$SINGBOX_CONF" ]; then
        local server_ip=$(get_ip)
        local hostname=$(hostname)
        
        # 使用 jq 添加 inbound
        local anytls_inbound="{\"type\":\"anytls\",\"tag\":\"anytls-add\",\"listen\":\"::\",\"listen_port\":${port},\"users\":[{\"password\":\"${password}\"}],\"tls\":{\"enabled\":true,\"certificate_path\":\"${CERT_DIR}/anytls.crt\",\"key_path\":\"${CERT_DIR}/anytls.key\"},\"detour\":\"mixed-add\"}"
        local mixed_inbound="{\"type\":\"mixed\",\"tag\":\"mixed-add\",\"listen\":\"127.0.0.1\",\"listen_port\":${internal_port}}"
        
        if command -v jq &>/dev/null; then
            local tmp_conf="${SINGBOX_CONF}.tmp"
            jq ".inbounds += [$anytls_inbound, $mixed_inbound]" "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
        else
            echo -e "${Warning} 需要 jq 来修改配置"
            echo -e "${Tip} 请安装: apt install jq 或 yum install jq 或 apk add jq"
            return 1
        fi
        
        # 生成链接
        local anytls_link="anytls://${password}@${server_ip}:${port}?insecure=1&sni=${server_ip}&fp=chrome&alpn=h2,http/1.1&udp=1#anytls-add-${hostname}"
        echo "$anytls_link" >> "$SINGBOX_DIR/combo_links.txt"
        
        # 更新节点信息
        echo -e "\n[AnyTLS-Added]\n端口: ${port}\n密码: ${password}\nSNI: ${server_ip}" >> "$SINGBOX_DIR/node_info.txt"
        
        echo -e "${Info} AnyTLS 节点已添加"
        echo -e "${Yellow}${anytls_link}${Reset}"
        
        restart_singbox
    else
        echo -e "${Error} 配置文件不存在"
    fi
}

# 添加其他协议的占位函数
add_protocol_tuic() {
    echo -e "${Info} 添加 TUIC 节点..."
    
    # 检查证书
    if [ ! -f "$CERT_DIR/cert.pem" ]; then
        echo -e "${Info} 需要配置 TLS 证书"
        cert_menu
    fi
    
    local port=$(config_port "TUIC")
    read -p "设置密码 [留空随机]: " password
    [ -z "$password" ] && password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null)
    
    if [ -f "$SINGBOX_CONF" ]; then
        local server_ip=$(get_ip)
        local new_inbound="{\"type\":\"tuic\",\"tag\":\"tuic-add\",\"listen\":\"::\",\"listen_port\":${port},\"users\":[{\"uuid\":\"${uuid}\",\"password\":\"${password}\"}],\"congestion_control\":\"bbr\",\"tls\":{\"enabled\":true,\"alpn\":[\"h3\"],\"certificate_path\":\"${CERT_DIR}/cert.pem\",\"key_path\":\"${CERT_DIR}/private.key\"}}"
        
        if command -v jq &>/dev/null; then
            local tmp_conf="${SINGBOX_CONF}.tmp"
            jq ".inbounds += [$new_inbound]" "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
        else
            echo -e "${Warning} 需要 jq 来修改配置"
            echo -e "${Tip} 请安装: apt install jq 或 yum install jq 或 apk add jq"
            return 1
        fi
        
        # 生成链接
        local tuic_link="tuic://${uuid}:${password}@${server_ip}:${port}?sni=${CERT_DOMAIN:-www.bing.com}&congestion_control=bbr&alpn=h3&allow_insecure=1#TUIC-Add-${server_ip}"
        echo "$tuic_link" >> "$SINGBOX_DIR/combo_links.txt"
        
        echo -e "\n[TUIC-Added]\n端口: ${port}\nUUID: ${uuid}\n密码: ${password}" >> "$SINGBOX_DIR/node_info.txt"
        
        echo -e "${Info} TUIC 节点已添加"
        echo -e "${Yellow}${tuic_link}${Reset}"
        
        restart_singbox
    else
        echo -e "${Error} 配置文件不存在"
    fi
}

add_protocol_vless() {
    echo -e "${Info} 添加 VLESS Reality 节点..."
    
    local port=$(config_port "VLESS Reality")
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null)
    
    # 生成 Reality 密钥对
    local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
    local private_key=$(echo "$keypair" | grep -i "privatekey" | awk '{print $2}')
    local public_key=$(echo "$keypair" | grep -i "publickey" | awk '{print $2}')
    local short_id=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)
    local dest="www.apple.com"
    
    if [ -f "$SINGBOX_CONF" ]; then
        local server_ip=$(get_ip)
        local new_inbound="{\"type\":\"vless\",\"tag\":\"vless-add\",\"listen\":\"::\",\"listen_port\":${port},\"users\":[{\"uuid\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\"}],\"tls\":{\"enabled\":true,\"server_name\":\"${dest}\",\"reality\":{\"enabled\":true,\"handshake\":{\"server\":\"${dest}\",\"server_port\":443},\"private_key\":\"${private_key}\",\"short_id\":[\"${short_id}\"]}}}"
        
        if command -v jq &>/dev/null; then
            local tmp_conf="${SINGBOX_CONF}.tmp"
            jq ".inbounds += [$new_inbound]" "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
        else
            echo -e "${Warning} 需要 jq 来修改配置"
            return 1
        fi
        
        # 生成链接
        local vless_link="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${dest}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#VLESS-Reality-Add-${server_ip}"
        echo "$vless_link" >> "$SINGBOX_DIR/combo_links.txt"
        
        echo -e "\n[VLESS-Reality-Added]\n端口: ${port}\nUUID: ${uuid}\n公钥: ${public_key}\n短ID: ${short_id}" >> "$SINGBOX_DIR/node_info.txt"
        
        echo -e "${Info} VLESS Reality 节点已添加"
        echo -e "${Yellow}${vless_link}${Reset}"
        
        restart_singbox
    else
        echo -e "${Error} 配置文件不存在"
    fi
}

add_protocol_any_reality() {
    echo -e "${Info} 添加 Any-Reality 节点..."
    
    # 版本检查
    if ! version_ge "$(get_version)" "1.12.0"; then
        echo -e "${Info} Any-Reality 需要升级 sing-box 到 1.12.0+"
        download_singbox "1.12.0"
    fi
    
    local port=$(config_port "Any-Reality")
    read -p "设置密码 [留空随机]: " password
    [ -z "$password" ] && password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    # 生成 Reality 密钥对
    local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
    local private_key=$(echo "$keypair" | grep -i "privatekey" | awk '{print $2}')
    local public_key=$(echo "$keypair" | grep -i "publickey" | awk '{print $2}')
    local short_id=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)
    local server_name="www.apple.com"
    local internal_port=$(shuf -i 20000-60000 -n 1)
    
    if [ -f "$SINGBOX_CONF" ]; then
        local server_ip=$(get_ip)
        local hostname=$(hostname)
        
        local ar_inbound="{\"type\":\"anytls\",\"tag\":\"any-reality-add\",\"listen\":\"::\",\"listen_port\":${port},\"users\":[{\"password\":\"${password}\"}],\"tls\":{\"enabled\":true,\"server_name\":\"${server_name}\",\"reality\":{\"enabled\":true,\"handshake\":{\"server\":\"${server_name}\",\"server_port\":443},\"private_key\":\"${private_key}\",\"short_id\":[\"${short_id}\"]}},\"detour\":\"mixed-ar-add\"}"
        local mixed_inbound="{\"type\":\"mixed\",\"tag\":\"mixed-ar-add\",\"listen\":\"127.0.0.1\",\"listen_port\":${internal_port}}"
        
        if command -v jq &>/dev/null; then
            local tmp_conf="${SINGBOX_CONF}.tmp"
            jq ".inbounds += [$ar_inbound, $mixed_inbound]" "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
        else
            echo -e "${Warning} 需要 jq 来修改配置"
            return 1
        fi
        
        # 生成链接
        local ar_link="anytls://${password}@${server_ip}:${port}?security=reality&sni=${server_name}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#Any-Reality-Add-${hostname}"
        echo "$ar_link" >> "$SINGBOX_DIR/combo_links.txt"
        
        echo -e "\n[Any-Reality-Added]\n端口: ${port}\n密码: ${password}\nSNI: ${server_name}\n公钥: ${public_key}\n短ID: ${short_id}" >> "$SINGBOX_DIR/node_info.txt"
        
        echo -e "${Info} Any-Reality 节点已添加"
        echo -e "${Yellow}${ar_link}${Reset}"
        
        restart_singbox
    else
        echo -e "${Error} 配置文件不存在"
    fi
}

# 重装现有节点
reinstall_existing_node() {
    echo -e ""
    
    if [ ! -f "$SINGBOX_CONF" ]; then
        echo -e "${Warning} 当前没有配置，请先安装节点"
        return 1
    fi
    
    # 读取当前配置，检测协议类型
    local protocols=$(grep -o '"type": *"[^"]*"' "$SINGBOX_CONF" | grep -v direct | grep -v mixed | cut -d'"' -f4 | sort -u)
    local proto_count=$(echo "$protocols" | wc -w)
    
    echo -e "${Cyan}========== 重装节点 ==========${Reset}"
    echo -e "${Info} 检测到以下协议 (共 $proto_count 个):"
    echo -e ""
    
    local i=1
    local proto_array=()
    for proto in $protocols; do
        proto_array+=("$proto")
        echo -e " ${Green}$i.${Reset} $proto"
        ((i++))
    done
    
    echo -e ""
    echo -e "${Yellow}==================== 重装选项 ====================${Reset}"
    echo -e " ${Green}A.${Reset} 重装全部节点 (删除所有配置重新安装)"
    echo -e " ${Green}S.${Reset} 重装单个节点 (只重装选择的协议，保留其他)"
    echo -e " ${Green}C.${Reset} 自定义组合重装 (选择多个协议重装)"
    echo -e " ${Green}N.${Reset} 安装全新的协议组合"
    echo -e " ${Green}0.${Reset} 取消"
    echo -e "${Yellow}=================================================${Reset}"
    
    read -p " 请选择 [A/S/C/N/0]: " reinstall_mode
    
    case "${reinstall_mode^^}" in
        A|ALL)
            reinstall_all_nodes "$protocols"
            ;;
        S|SINGLE)
            reinstall_single_node "${proto_array[@]}"
            ;;
        C|CUSTOM)
            reinstall_custom_nodes "${proto_array[@]}"
            ;;
        N|NEW)
            echo -e "${Warning} 这将删除所有现有配置，是否继续? [y/N]"
            read -p "" confirm
            if [[ $confirm =~ ^[Yy]$ ]]; then
                stop_singbox
                rm -f "$SINGBOX_CONF" "$SINGBOX_DIR/node_info.txt" "$SINGBOX_DIR"/*_link.txt "$SINGBOX_DIR"/combo_links.txt
                install_combo
            fi
            ;;
        0) return 0 ;;
        *) echo -e "${Error} 无效选择" ;;
    esac
}

# 重装全部节点
reinstall_all_nodes() {
    local protocols=$1
    
    echo -e ""
    echo -e "${Warning} 重装全部将删除所有配置并重新安装，是否继续? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    stop_singbox
    rm -f "$SINGBOX_CONF" "$SINGBOX_DIR/node_info.txt" "$SINGBOX_DIR"/*_link.txt "$SINGBOX_DIR"/combo_links.txt
    
    echo -e "${Info} 正在重装所有协议..."
    
    for proto in $protocols; do
        echo -e "${Info} 正在安装 $proto..."
        case "$proto" in
            hysteria2) install_hysteria2 ;;
            tuic) install_tuic ;;
            vless) install_vless_reality ;;
            anytls) install_anytls ;;
        esac
    done
    
    echo -e "${Info} 全部节点重装完成"
}

# 重装单个节点
reinstall_single_node() {
    local proto_array=("$@")
    local proto_count=${#proto_array[@]}
    
    echo -e ""
    echo -e "${Info} 选择要重装的单个节点:"
    
    local i=1
    for proto in "${proto_array[@]}"; do
        echo -e " ${Green}$i.${Reset} $proto"
        ((i++))
    done
    echo -e " ${Green}0.${Reset} 取消"
    
    read -p " 请选择 [1-$proto_count]: " single_choice
    
    if [[ "$single_choice" =~ ^[0-9]+$ ]] && [ "$single_choice" -ge 1 ] && [ "$single_choice" -le "$proto_count" ]; then
        local selected_proto="${proto_array[$((single_choice-1))]}"
        
        echo -e ""
        echo -e "${Info} 将重装: ${Cyan}$selected_proto${Reset}"
        echo -e "${Tip} 其他节点将保留不变"
        echo -e "${Warning} 是否继续? [y/N]"
        read -p "" confirm
        [[ ! $confirm =~ ^[Yy]$ ]] && return 0
        
        # 使用 jq 或 sed 删除指定协议的 inbound
        if command -v jq &>/dev/null; then
            # 使用 jq 删除指定类型的 inbound
            local tmp_conf="${SINGBOX_CONF}.tmp"
            jq --arg type "$selected_proto" '.inbounds = [.inbounds[] | select(.type != $type)]' "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
            echo -e "${Info} 已删除 $selected_proto 配置 (jq)"
        else
            # 没有 jq，使用备用方案：重建整个配置
            echo -e "${Warning} 未检测到 jq，将使用备用方案"
            echo -e "${Tip} 建议安装 jq: apt install jq 或 yum install jq 或 apk add jq"
            
            # 备用方案：停止服务，保存其他协议的配置，重建
            stop_singbox
            
            # 提取当前配置中的其他协议
            local other_protos=""
            for proto in "${proto_array[@]}"; do
                if [ "$proto" != "$selected_proto" ]; then
                    [ -n "$other_protos" ] && other_protos="${other_protos},"
                    other_protos="${other_protos}$proto"
                fi
            done
            
            echo -e "${Info} 将保留的协议: $other_protos"
            echo -e "${Warning} 备用方案需要重新配置所有节点，是否继续? [y/N]"
            read -p "" confirm2
            if [[ ! $confirm2 =~ ^[Yy]$ ]]; then
                start_singbox
                return 0
            fi
            
            # 删除配置并重装
            rm -f "$SINGBOX_CONF" "$SINGBOX_DIR/node_info.txt" "$SINGBOX_DIR"/*_link.txt "$SINGBOX_DIR"/combo_links.txt
            install_combo
            return 0
        fi
        
        # 重新添加该协议
        echo -e "${Info} 正在重新配置 $selected_proto..."
        case "$selected_proto" in
            hysteria2) add_protocol_hy2 ;;
            tuic) add_protocol_tuic ;;
            vless) add_protocol_vless ;;
            anytls) add_protocol_anytls ;;
        esac
        
        echo -e "${Info} $selected_proto 重装完成"
    elif [ "$single_choice" = "0" ]; then
        return 0
    else
        echo -e "${Error} 无效选择"
    fi
}

# 自定义组合重装
reinstall_custom_nodes() {
    local proto_array=("$@")
    local proto_count=${#proto_array[@]}
    
    echo -e ""
    echo -e "${Info} 选择要重装的协议 (输入编号，用逗号分隔，如: 1,3):"
    
    local i=1
    for proto in "${proto_array[@]}"; do
        echo -e " ${Green}$i.${Reset} $proto"
        ((i++))
    done
    
    read -p " 请输入: " custom_choice
    
    if [ -z "$custom_choice" ]; then
        echo -e "${Error} 未选择任何协议"
        return 1
    fi
    
    # 解析选择
    IFS=',' read -ra selections <<< "$custom_choice"
    local selected_protos=()
    
    for sel in "${selections[@]}"; do
        sel=$(echo "$sel" | tr -d ' ')
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "$proto_count" ]; then
            selected_protos+=("${proto_array[$((sel-1))]}")
        fi
    done
    
    if [ ${#selected_protos[@]} -eq 0 ]; then
        echo -e "${Error} 无有效选择"
        return 1
    fi
    
    echo -e ""
    echo -e "${Info} 将重装以下协议:"
    for proto in "${selected_protos[@]}"; do
        echo -e "  - ${Cyan}$proto${Reset}"
    done
    echo -e "${Tip} 其他节点将保留不变"
    echo -e "${Warning} 是否继续? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    # 删除选中的协议
    if command -v jq &>/dev/null; then
        for proto in "${selected_protos[@]}"; do
            local tmp_conf="${SINGBOX_CONF}.tmp"
            jq --arg type "$proto" '.inbounds = [.inbounds[] | select(.type != $type)]' "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
        done
        echo -e "${Info} 已删除选中协议的配置"
    else
        echo -e "${Warning} 未检测到 jq，无法进行部分重装"
        echo -e "${Tip} 建议安装 jq: apt install jq 或 yum install jq 或 apk add jq"
        echo -e "${Info} 将使用全量重装方案..."
        stop_singbox
        rm -f "$SINGBOX_CONF" "$SINGBOX_DIR/node_info.txt" "$SINGBOX_DIR"/*_link.txt "$SINGBOX_DIR"/combo_links.txt
        install_combo
        return 0
    fi
    
    # 重新添加选中的协议
    for proto in "${selected_protos[@]}"; do
        echo -e "${Info} 正在重新配置 $proto..."
        case "$proto" in
            hysteria2) add_protocol_hy2 ;;
            tuic) add_protocol_tuic ;;
            vless) add_protocol_vless ;;
            anytls) add_protocol_anytls ;;
        esac
    done
    
    echo -e "${Info} 自定义组合重装完成"
}

# 修改节点参数
modify_node_params() {
    echo -e ""
    echo -e "${Cyan}========== 修改节点参数 ==========${Reset}"
    
    if [ ! -f "$SINGBOX_CONF" ]; then
        echo -e "${Warning} 配置文件不存在"
        return 1
    fi
    
    echo -e " ${Green}1.${Reset} 修改端口"
    echo -e " ${Green}2.${Reset} 修改密码"
    echo -e " ${Green}3.${Reset} 修改 SNI"
    echo -e " ${Green}0.${Reset} 取消"
    
    read -p " 请选择: " modify_choice
    
    case "$modify_choice" in
        1)
            read -p "新端口: " new_port
            if [ -n "$new_port" ]; then
                # 使用 sed 替换端口 (简化版)
                sed -i "s/\"listen_port\": *[0-9]*/\"listen_port\": $new_port/" "$SINGBOX_CONF"
                echo -e "${Info} 端口已修改为 $new_port"
                restart_singbox
            fi
            ;;
        2)
            read -p "新密码: " new_password
            if [ -n "$new_password" ]; then
                sed -i "s/\"password\": *\"[^\"]*\"/\"password\": \"$new_password\"/" "$SINGBOX_CONF"
                echo -e "${Info} 密码已修改"
                restart_singbox
            fi
            ;;
        3)
            read -p "新 SNI: " new_sni
            if [ -n "$new_sni" ]; then
                sed -i "s/\"server_name\": *\"[^\"]*\"/\"server_name\": \"$new_sni\"/" "$SINGBOX_CONF"
                echo -e "${Info} SNI 已修改为 $new_sni"
                restart_singbox
            fi
            ;;
        0) return 0 ;;
    esac
    
    echo -e "${Warning} 修改后请重新生成分享链接"
}

# 复制分享链接
copy_share_links() {
    echo -e ""
    echo -e "${Cyan}========== 所有分享链接 ==========${Reset}"
    
    for link_file in "$SINGBOX_DIR"/*_link.txt "$SINGBOX_DIR"/combo_links.txt; do
        if [ -f "$link_file" ]; then
            echo -e ""
            echo -e "${Yellow}$(cat "$link_file")${Reset}"
        fi
    done
    
    echo -e ""
    echo -e "${Tip} 请手动复制以上链接"
}

view_config() {
    if [ -f "$SINGBOX_CONF" ]; then
        echo -e "${Green}==================== 配置文件 ====================${Reset}"
        cat "$SINGBOX_CONF"
        echo -e "${Green}=================================================${Reset}"
    else
        echo -e "${Warning} 配置文件不存在"
    fi
}

# ==================== 卸载 ====================
uninstall_singbox() {
    echo -e "${Warning} 确定要卸载 sing-box? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    stop_singbox
    
    # 删除 systemd 服务
    if [ -f /etc/systemd/system/sing-box.service ]; then
        systemctl disable sing-box
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload
    fi
    
    rm -rf "$SINGBOX_DIR"
    echo -e "${Info} sing-box 已卸载"
}

# ==================== 多协议组合安装 ====================
install_combo() {
    echo -e ""
    echo -e "${Cyan}========== 自定义多协议组合 ==========${Reset}"
    echo -e "${Tip} 选择要安装的协议组合，支持同时运行多个协议"
    echo -e ""
    
    # 确保 sing-box 已安装
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 协议选择
    echo -e "${Info} 请选择要启用的协议 (多选，用逗号分隔):"
    echo -e " ${Green}1.${Reset} Hysteria2"
    echo -e " ${Green}2.${Reset} TUIC v5"
    echo -e " ${Green}3.${Reset} VLESS Reality"
    echo -e " ${Green}4.${Reset} Shadowsocks"
    echo -e " ${Green}5.${Reset} Trojan"
    echo -e " ${Green}6.${Reset} AnyTLS"
    echo -e " ${Green}7.${Reset} Any-Reality"
    echo -e ""
    echo -e " ${Cyan}示例: 1,3,7 表示安装 Hysteria2 + VLESS + Any-Reality${Reset}"
    echo -e ""
    
    read -p "请选择 [1-7]: " combo_choice
    
    if [ -z "$combo_choice" ]; then
        echo -e "${Error} 未选择任何协议"
        return 1
    fi
    
    # 解析选择
    IFS=',' read -ra protocols <<< "$combo_choice"
    
    local install_hy2=false
    local install_tuic=false
    local install_vless=false
    local install_ss=false
    local install_trojan=false
    local install_anytls=false
    local install_any_reality=false
    
    for p in "${protocols[@]}"; do
        case "$(echo $p | tr -d ' ')" in
            1) install_hy2=true ;;
            2) install_tuic=true ;;
            3) install_vless=true ;;
            4) install_ss=true ;;
            5) install_trojan=true ;;
            6) install_anytls=true ;;
            7) install_any_reality=true ;;
        esac
    done
    
    # AnyTLS/Any-Reality 版本检查
    if [ "$install_anytls" = true ] || [ "$install_any_reality" = true ]; then
        if ! version_ge "$(get_version)" "1.12.0"; then
            echo -e "${Info} AnyTLS/Any-Reality 需要升级 sing-box 到 1.12.0+，正在自动升级..."
            download_singbox "1.12.0"
        fi
    fi
    
    # 配置证书 (Hysteria2, TUIC, Trojan 需要)
    if [ "$install_hy2" = true ] || [ "$install_tuic" = true ] || [ "$install_trojan" = true ]; then
        echo -e ""
        echo -e "${Info} 检测到需要 TLS 证书的协议"
        cert_menu
    fi
    
    # 生成统一的 UUID 和密码 (FreeBSD 兼容)
    init_uuid
    local password="$uuid"  # 和 argosbx 一样，使用 UUID 作为密码
    
    echo -e ""
    echo -e "${Info} 统一认证信息:"
    echo -e " UUID/密码: ${Cyan}${uuid}${Reset}"
    echo -e ""
    
    # 端口配置方式
    echo -e "${Info} 端口配置方式:"
    echo -e " ${Green}1.${Reset} 自动分配随机端口 (推荐)"
    echo -e " ${Green}2.${Reset} 手动指定端口"
    read -p "请选择 [1-2]: " port_mode
    
    local hy2_port=""
    local tuic_port=""
    local vless_port=""
    local ss_port=""
    local trojan_port=""
    local anytls_port=""
    local ar_port=""
    
    if [ "$port_mode" = "2" ]; then
        # 手动指定端口
        echo -e ""
        echo -e "${Info} 请为每个协议指定端口 (留空跳过):"
        
        if [ "$install_hy2" = true ]; then
            read -p "Hysteria2 端口: " hy2_port
            [ -z "$hy2_port" ] && hy2_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_tuic" = true ]; then
            read -p "TUIC 端口: " tuic_port
            [ -z "$tuic_port" ] && tuic_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_vless" = true ]; then
            read -p "VLESS Reality 端口: " vless_port
            [ -z "$vless_port" ] && vless_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_ss" = true ]; then
            read -p "Shadowsocks 端口: " ss_port
            [ -z "$ss_port" ] && ss_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_trojan" = true ]; then
            read -p "Trojan 端口: " trojan_port
            [ -z "$trojan_port" ] && trojan_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_anytls" = true ]; then
            read -p "AnyTLS 端口: " anytls_port
            [ -z "$anytls_port" ] && anytls_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_any_reality" = true ]; then
            read -p "Any-Reality 端口: " ar_port
            [ -z "$ar_port" ] && ar_port=$(shuf -i 10000-65535 -n 1)
        fi
    else
        # 自动分配
        local base_port=$(shuf -i 10000-50000 -n 1)
        [ "$install_hy2" = true ] && hy2_port=$((base_port))
        [ "$install_tuic" = true ] && tuic_port=$((base_port + 1))
        [ "$install_vless" = true ] && vless_port=$((base_port + 2))
        [ "$install_ss" = true ] && ss_port=$((base_port + 3))
        [ "$install_trojan" = true ] && trojan_port=$((base_port + 4))
        [ "$install_anytls" = true ] && anytls_port=$((base_port + 5))
        [ "$install_any_reality" = true ] && ar_port=$((base_port + 6))
    fi
    
    echo -e ""
    echo -e "${Info} 端口分配:"
    [ -n "$hy2_port" ] && echo -e " Hysteria2: ${Cyan}${hy2_port}${Reset}"
    [ -n "$ss_port" ] && echo -e " Shadowsocks: ${Cyan}${ss_port}${Reset}"
    [ -n "$trojan_port" ] && echo -e " Trojan: ${Cyan}${trojan_port}${Reset}"
    [ -n "$anytls_port" ] && echo -e " AnyTLS: ${Cyan}${anytls_port}${Reset}"
    [ -n "$ar_port" ] && echo -e " Any-Reality: ${Cyan}${ar_port}${Reset}"
    [ -n "$vless_port" ] && echo -e " VLESS: ${Cyan}${vless_port}${Reset}"
    [ -n "$ss_port" ] && echo -e " SS: ${Cyan}${ss_port}${Reset}"
    [ -n "$trojan_port" ] && echo -e " Trojan: ${Cyan}${trojan_port}${Reset}"
    [ -n "$anytls_port" ] && echo -e " AnyTLS: ${Cyan}${anytls_port}${Reset}"
    
    # 构建配置
    local inbounds=""
    local server_ip=$(get_ip)
    local node_info=""
    local links=""
    
    # Hysteria2 配置 (参照官方文档)
    if [ "$install_hy2" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"hysteria2\",
      \"tag\": \"hy2-in\",
      \"listen\": \"::\",
      \"listen_port\": ${hy2_port},
      \"users\": [
        {
          \"name\": \"user\",
          \"password\": \"${password}\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"alpn\": [\"h3\"],
        \"certificate_path\": \"${CERT_DIR}/cert.pem\",
        \"key_path\": \"${CERT_DIR}/private.key\"
      }
    }"
        
        node_info="${node_info}
[Hysteria2]
端口: ${hy2_port}
密码: ${password}
SNI: ${CERT_DOMAIN:-www.bing.com}"
        
        links="${links}
hysteria2://${password}@${server_ip}:${hy2_port}?sni=${CERT_DOMAIN:-www.bing.com}&insecure=1#Hy2-${server_ip}"
    fi
    
    # TUIC 配置
    if [ "$install_tuic" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"tuic\",
      \"tag\": \"tuic-in\",
      \"listen\": \"::\",
      \"listen_port\": ${tuic_port},
      \"users\": [
        {
          \"name\": \"user\",
          \"uuid\": \"${uuid}\",
          \"password\": \"${password}\"
        }
      ],
      \"congestion_control\": \"bbr\",
      \"tls\": {
        \"enabled\": true,
        \"alpn\": [\"h3\"],
        \"certificate_path\": \"${CERT_DIR}/cert.pem\",
        \"key_path\": \"${CERT_DIR}/private.key\"
      }
    }"
        
        node_info="${node_info}

[TUIC v5]
端口: ${tuic_port}
UUID: ${uuid}
密码: ${password}
SNI: ${CERT_DOMAIN:-www.bing.com}"
        
        links="${links}
tuic://${uuid}:${password}@${server_ip}:${tuic_port}?sni=${CERT_DOMAIN:-www.bing.com}&congestion_control=bbr&alpn=h3&udp_relay_mode=native&allow_insecure=1#TUIC-${server_ip}"
    fi
    
    # VLESS Reality 配置
    if [ "$install_vless" = true ]; then
        echo -e "${Info} 生成 Reality 密钥..."
        mkdir -p "$CERT_DIR/reality"
        
        # 复用已有密钥或生成新的 (参照 argosbx)
        # 检查已有密钥是否有效 (非空)
        if [ -s "$CERT_DIR/reality/private_key" ] && [ -s "$CERT_DIR/reality/public_key" ]; then
            private_key=$(cat "$CERT_DIR/reality/private_key")
            public_key=$(cat "$CERT_DIR/reality/public_key")
            short_id=$(cat "$CERT_DIR/reality/short_id" 2>/dev/null)
            echo -e "${Info} 使用已有 Reality 密钥"
        fi
        
        # 如果密钥为空，重新生成
        if [ -z "$private_key" ] || [ -z "$public_key" ]; then
            echo -e "${Info} 生成新的 Reality 密钥对..."
            local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
            private_key=$(echo "$keypair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
            public_key=$(echo "$keypair" | awk '/PublicKey/ {print $2}' | tr -d '"')
            
            # 验证密钥是否生成成功
            if [ -z "$private_key" ] || [ -z "$public_key" ]; then
                echo -e "${Error} Reality 密钥生成失败，请确保 sing-box 版本支持 reality-keypair"
                echo -e "${Info} 尝试手动执行: $SINGBOX_BIN generate reality-keypair"
                return 1
            fi
            
            # FreeBSD 兼容的 short_id 生成
            short_id=$($SINGBOX_BIN generate rand --hex 4 2>/dev/null)
            [ -z "$short_id" ] && short_id=$(od -An -tx1 -N 4 /dev/urandom 2>/dev/null | tr -d ' \n')
            [ -z "$short_id" ] && short_id=$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 8)
            [ -z "$short_id" ] && short_id="12345678"  # 最后保底
            
            # 保存密钥
            echo "$private_key" > "$CERT_DIR/reality/private_key"
            echo "$public_key" > "$CERT_DIR/reality/public_key"
            echo "$short_id" > "$CERT_DIR/reality/short_id"
            echo -e "${Info} Reality 密钥已保存"
        fi
        local dest="apple.com"
        
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"vless\",
      \"tag\": \"vless-in\",
      \"listen\": \"::\",
      \"listen_port\": ${vless_port},
      \"users\": [
        {
          \"name\": \"user\",
          \"uuid\": \"${uuid}\",
          \"flow\": \"xtls-rprx-vision\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"server_name\": \"${dest}\",
        \"reality\": {
          \"enabled\": true,
          \"handshake\": {
            \"server\": \"${dest}\",
            \"server_port\": 443
          },
          \"private_key\": \"${private_key}\",
          \"short_id\": [\"${short_id}\"]
        }
      }
    }"
        
        node_info="${node_info}

[VLESS Reality]
端口: ${vless_port}
UUID: ${uuid}
SNI: ${dest}
公钥: ${public_key}
Short ID: ${short_id}"
        
        links="${links}
vless://${uuid}@${server_ip}:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${dest}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#VLESS-Reality-${server_ip}"
    fi
    
    # Shadowsocks 配置
    if [ "$install_ss" = true ]; then
        local ss_method="2022-blake3-aes-256-gcm"
        local ss_password=$(openssl rand -base64 32 2>/dev/null || head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 | base64)
        
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"shadowsocks\",
      \"tag\": \"ss-in\",
      \"listen\": \"::\",
      \"listen_port\": ${ss_port},
      \"method\": \"${ss_method}\",
      \"password\": \"${ss_password}\"
    }"
        
        node_info="${node_info}

[Shadowsocks]
端口: ${ss_port}
加密方式: ${ss_method}
密码: ${ss_password}"
        
        local ss_userinfo=$(echo -n "${ss_method}:${ss_password}" | base64 -w0)
        links="${links}
ss://${ss_userinfo}@${server_ip}:${ss_port}#SS-${server_ip}"
    fi
    
    # Trojan 配置
    if [ "$install_trojan" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"trojan\",
      \"tag\": \"trojan-in\",
      \"listen\": \"::\",
      \"listen_port\": ${trojan_port},
      \"users\": [
        {
          \"password\": \"${password}\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"certificate_path\": \"${CERT_DIR}/cert.pem\",
        \"key_path\": \"${CERT_DIR}/private.key\"
      }
    }"
        
        node_info="${node_info}

[Trojan]
端口: ${trojan_port}
密码: ${password}
SNI: ${CERT_DOMAIN:-www.bing.com}"
        
        links="${links}
trojan://${password}@${server_ip}:${trojan_port}?sni=${CERT_DOMAIN:-www.bing.com}&allowInsecure=1#Trojan-${server_ip}"
    fi
    # AnyTLS 配置
    if [ "$install_anytls" = true ]; then
        # 生成自签证书
        local cert_domain="bing.com"
        openssl req -x509 -newkey ec:<(openssl ecparam -name prime256v1) \
            -keyout "$CERT_DIR/anytls.key" \
            -out "$CERT_DIR/anytls.crt" \
            -days 36500 -nodes \
            -subj "/CN=$cert_domain" 2>/dev/null || \
        openssl req -x509 -newkey rsa:2048 \
            -keyout "$CERT_DIR/anytls.key" \
            -out "$CERT_DIR/anytls.crt" \
            -days 36500 -nodes \
            -subj "/CN=$cert_domain" 2>/dev/null
        
        local anytls_mixed_port=$(shuf -i 20000-60000 -n 1)
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        # 参照 argosbx 的简单配置，不需要 detour
        inbounds="${inbounds}
    {
      \"type\": \"anytls\",
      \"tag\": \"anytls-in\",
      \"listen\": \"::\",
      \"listen_port\": ${anytls_port},
      \"users\": [{\"password\": \"${password}\"}],
      \"padding_scheme\": [],
      \"tls\": {
        \"enabled\": true,
        \"certificate_path\": \"$CERT_DIR/anytls.crt\",
        \"key_path\": \"$CERT_DIR/anytls.key\"
      }
    }"
    
    node_info="${node_info}
[AnyTLS]
端口: ${anytls_port}
密码: ${password}
SNI: ${server_ip}
证书: 自签证书
说明: 需 sing-box 1.12.0+ 或 Clash Meta，客户端需启用 skip-cert-verify"

    # 生成分享链接和JSON
    local anytls_link="anytls://${password}@${server_ip}:${anytls_port}?insecure=1&sni=${server_ip}&fp=chrome&alpn=h2,http/1.1&udp=1#AnyTLS-${server_ip}"
    local out_json="{\"type\":\"anytls\",\"tag\":\"anytls-out\",\"server\":\"$server_ip\",\"server_port\":$anytls_port,\"password\":\"$password\",\"tls\":{\"enabled\":true,\"server_name\":\"$server_ip\",\"insecure\":true}}"
    links="${links}
${anytls_link}"
    fi

    # Any-Reality 配置
    if [ "$install_any_reality" = true ]; then
        # 复用已有密钥或使用 VLESS 生成的密钥 (参照 argosbx)
        mkdir -p "$CERT_DIR/reality"
        
        # 检查已有密钥是否有效 (非空)
        if [ -s "$CERT_DIR/reality/private_key" ] && [ -s "$CERT_DIR/reality/public_key" ]; then
            private_key=$(cat "$CERT_DIR/reality/private_key")
            public_key=$(cat "$CERT_DIR/reality/public_key")
            short_id=$(cat "$CERT_DIR/reality/short_id" 2>/dev/null)
            echo -e "${Info} 使用已有 Reality 密钥"
        fi
        
        # 如果密钥为空，重新生成
        if [ -z "$private_key" ] || [ -z "$public_key" ]; then
            echo -e "${Info} 生成新的 Reality 密钥对..."
            local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
            private_key=$(echo "$keypair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
            public_key=$(echo "$keypair" | awk '/PublicKey/ {print $2}' | tr -d '"')
            
            # 验证密钥是否生成成功
            if [ -z "$private_key" ] || [ -z "$public_key" ]; then
                echo -e "${Error} Reality 密钥生成失败，请确保 sing-box 版本支持 reality-keypair"
                echo -e "${Info} 尝试手动执行: $SINGBOX_BIN generate reality-keypair"
                return 1
            fi
            
            # FreeBSD 兼容的 short_id 生成
            short_id=$($SINGBOX_BIN generate rand --hex 4 2>/dev/null)
            [ -z "$short_id" ] && short_id=$(od -An -tx1 -N 4 /dev/urandom 2>/dev/null | tr -d ' \n')
            [ -z "$short_id" ] && short_id=$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 8)
            [ -z "$short_id" ] && short_id="12345678"  # 最后保底
            
            echo "$private_key" > "$CERT_DIR/reality/private_key"
            echo "$public_key" > "$CERT_DIR/reality/public_key"
            echo "$short_id" > "$CERT_DIR/reality/short_id"
            echo -e "${Info} Reality 密钥已保存"
        fi
        
        local ar_dest="apple.com"
        local ar_server_name="apple.com"
        
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        # 参照 argosbx 的简单配置，不需要 detour
        inbounds="${inbounds}
    {
      \"type\": \"anytls\",
      \"tag\": \"anyreality-in\",
      \"listen\": \"::\",
      \"listen_port\": ${ar_port},
      \"users\": [{\"password\": \"${password}\"}],
      \"padding_scheme\": [],
      \"tls\": {
        \"enabled\": true,
        \"server_name\": \"${ar_server_name}\",
        \"reality\": {
          \"enabled\": true,
          \"handshake\": {
            \"server\": \"${ar_dest}\",
            \"server_port\": 443
          },
          \"private_key\": \"${private_key}\",
          \"short_id\": [\"${short_id}\"]
        }
      }
    }"

        node_info="${node_info}
[Any-Reality]
端口: ${ar_port}
密码: ${password}
SNI: ${ar_server_name}
Short ID: ${short_id}
Public Key: ${public_key}
说明: 指纹(fp)建议使用 chrome"

        local ar_link="anytls://${password}@${server_ip}:${ar_port}?security=reality&sni=${ar_server_name}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#Any-Reality-${server_ip}"
        links="${links}
${ar_link}"
    fi
    
    # 询问是否启用 WARP 出站
    ask_warp_outbound
    
    # 生成完整配置
    local exp_config=$(get_experimental_config)
    local outbounds_config=$(get_outbounds_config "$WARP_ENABLED")
    
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
${exp_config}  "inbounds": [${inbounds}
  ],
${outbounds_config}
}
EOF
    
    # 保存节点信息
    local active_protocols=""
    [ "$install_hy2" = true ] && active_protocols="${active_protocols}Hysteria2 "
    [ "$install_tuic" = true ] && active_protocols="${active_protocols}TUIC "
    [ "$install_vless" = true ] && active_protocols="${active_protocols}VLESS "
    [ "$install_ss" = true ] && active_protocols="${active_protocols}SS "
    [ "$install_trojan" = true ] && active_protocols="${active_protocols}Trojan "
    
    cat > "$SINGBOX_DIR/node_info.txt" << EOF
============= 多协议组合节点 =============
服务器: ${server_ip}
启用协议: ${active_protocols}
${node_info}
==========================================
EOF
    
    echo "$links" > "$SINGBOX_DIR/combo_links.txt"
    
    echo -e ""
    echo -e "${Green}========== 多协议组合安装完成 ==========${Reset}"
    echo -e ""
    echo -e " 服务器: ${Cyan}${server_ip}${Reset}"
    echo -e " 启用协议: ${Green}${active_protocols}${Reset}"
    echo -e ""
    
    [ "$install_hy2" = true ] && echo -e " Hysteria2 端口: ${Cyan}${hy2_port}${Reset}"
    [ "$install_tuic" = true ] && echo -e " TUIC 端口: ${Cyan}${tuic_port}${Reset}"
    [ "$install_vless" = true ] && echo -e " VLESS 端口: ${Cyan}${vless_port}${Reset}"
    [ "$install_ss" = true ] && echo -e " SS 端口: ${Cyan}${ss_port}${Reset}"
    [ "$install_trojan" = true ] && echo -e " Trojan 端口: ${Cyan}${trojan_port}${Reset}"
    
    echo -e ""
    echo -e "${Green}=========================================${Reset}"
    echo -e ""
    echo -e "${Info} 分享链接已保存到: ${Cyan}$SINGBOX_DIR/combo_links.txt${Reset}"
    echo -e ""
    
    # 显示链接
    echo -e "${Yellow}分享链接:${Reset}"
    echo -e "${links}"
    echo -e ""
    
    # 启动服务
    read -p "是否立即启动? [Y/n]: " start_now
    if [[ ! $start_now =~ ^[Nn]$ ]]; then
        start_singbox
        # 验证 WARP 连通性
        verify_warp_after_start
    fi
}

# 预设组合
install_preset_combo() {
    echo -e ""
    echo -e "${Cyan}========== 预设协议组合 ==========${Reset}"
    echo -e ""
    echo -e " ${Green}1.${Reset} 标准组合 (Hysteria2 + TUIC)"
    echo -e "    ${Cyan}适合: 日常使用，UDP 游戏${Reset}"
    echo -e ""
    echo -e " ${Green}2.${Reset} 全能组合 (Hysteria2 + TUIC + VLESS Reality)"
    echo -e "    ${Cyan}适合: 全场景覆盖${Reset}"
    echo -e ""
    echo -e " ${Green}3.${Reset} 免费端口组合 (VLESS Reality + Shadowsocks)"
    echo -e "    ${Cyan}适合: Serv00/无 UDP 环境${Reset}"
    echo -e ""
    echo -e " ${Green}4.${Reset} 完整组合 (全部 5 种协议)"
    echo -e "    ${Cyan}适合: 测试和特殊需求${Reset}"
    echo -e ""
    
    read -p "请选择预设 [1-4]: " preset_choice
    
    case "$preset_choice" in
        1)
            echo "1,2" | { read combo_choice; install_combo_internal "1,2"; }
            ;;
        2)
            install_combo_internal "1,2,3"
            ;;
        3)
            install_combo_internal "3,4"
            ;;
        4)
            install_combo_internal "1,2,3,4,5"
            ;;
        *)
            echo -e "${Error} 无效选择"
            return 1
            ;;
    esac
}

# 内部组合安装函数
install_combo_internal() {
    local combo_choice=$1
    
    # 确保 sing-box 已安装
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 解析选择
    IFS=',' read -ra protocols <<< "$combo_choice"
    
    local install_hy2=false
    local install_tuic=false
    local install_vless=false
    local install_ss=false
    local install_trojan=false
    
    for p in "${protocols[@]}"; do
        case "$(echo $p | tr -d ' ')" in
            1) install_hy2=true ;;
            2) install_tuic=true ;;
            3) install_vless=true ;;
            4) install_ss=true ;;
            5) install_trojan=true ;;
        esac
    done
    
    # 配置证书
    # 配置证书
    if [ "$install_hy2" = true ] || [ "$install_tuic" = true ] || [ "$install_trojan" = true ]; then
        if ! cert_menu; then
            return 1
        fi
    fi
    
    # 生成认证信息
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null)
    local password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    # 分配端口
    local base_port=$(shuf -i 10000-50000 -n 1)
    local hy2_port=$((base_port))
    local tuic_port=$((base_port + 1))
    local vless_port=$((base_port + 2))
    local ss_port=$((base_port + 3))
    local trojan_port=$((base_port + 4))
    
    local server_ip=$(get_ip)
    local inbounds=""
    local links=""
    
    # 构建配置 (简化版，复用上面的逻辑)
    if [ "$install_hy2" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"hysteria2\",\"tag\":\"hy2\",\"listen\":\"::\",\"listen_port\":${hy2_port},\"users\":[{\"password\":\"${password}\"}],\"tls\":{\"enabled\":true,\"alpn\":[\"h3\"],\"certificate_path\":\"${CERT_DIR}/cert.pem\",\"key_path\":\"${CERT_DIR}/private.key\"}}"
        links="${links}\nhysteria2://${password}@${server_ip}:${hy2_port}?sni=${CERT_DOMAIN:-www.bing.com}&insecure=1#Hy2"
    fi
    
    if [ "$install_tuic" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"tuic\",\"tag\":\"tuic\",\"listen\":\"::\",\"listen_port\":${tuic_port},\"users\":[{\"uuid\":\"${uuid}\",\"password\":\"${password}\"}],\"congestion_control\":\"bbr\",\"tls\":{\"enabled\":true,\"alpn\":[\"h3\"],\"certificate_path\":\"${CERT_DIR}/cert.pem\",\"key_path\":\"${CERT_DIR}/private.key\"}}"
        links="${links}\ntuic://${uuid}:${password}@${server_ip}:${tuic_port}?sni=${CERT_DOMAIN:-www.bing.com}&congestion_control=bbr&alpn=h3&allow_insecure=1#TUIC"
    fi
    
    if [ "$install_vless" = true ]; then
        local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
        local private_key=$(echo "$keypair" | grep -i "privatekey" | awk '{print $2}')
        local public_key=$(echo "$keypair" | grep -i "publickey" | awk '{print $2}')
        local short_id=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)
        
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"vless\",\"tag\":\"vless\",\"listen\":\"::\",\"listen_port\":${vless_port},\"users\":[{\"uuid\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\"}],\"tls\":{\"enabled\":true,\"server_name\":\"www.apple.com\",\"reality\":{\"enabled\":true,\"handshake\":{\"server\":\"www.apple.com\",\"server_port\":443},\"private_key\":\"${private_key}\",\"short_id\":[\"${short_id}\"]}}}"
        links="${links}\nvless://${uuid}@${server_ip}:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.apple.com&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#VLESS-Reality"
    fi
    
    if [ "$install_ss" = true ]; then
        local ss_pass=$(openssl rand -base64 32 2>/dev/null)
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"shadowsocks\",\"tag\":\"ss\",\"listen\":\"::\",\"listen_port\":${ss_port},\"method\":\"2022-blake3-aes-256-gcm\",\"password\":\"${ss_pass}\"}"
        local ss_ui=$(echo -n "2022-blake3-aes-256-gcm:${ss_pass}" | base64 -w0)
        links="${links}\nss://${ss_ui}@${server_ip}:${ss_port}#SS"
    fi
    
    if [ "$install_trojan" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"trojan\",\"tag\":\"trojan\",\"listen\":\"::\",\"listen_port\":${trojan_port},\"users\":[{\"password\":\"${password}\"}],\"tls\":{\"enabled\":true,\"certificate_path\":\"${CERT_DIR}/cert.pem\",\"key_path\":\"${CERT_DIR}/private.key\"}}"
        links="${links}\ntrojan://${password}@${server_ip}:${trojan_port}?sni=${CERT_DOMAIN:-www.bing.com}&allowInsecure=1#Trojan"
    fi
    
    # 询问是否启用 WARP 出站
    ask_warp_outbound
    
    # 生成配置
    local outbounds_json=""
    if [ "$WARP_ENABLED" = true ] && [ -n "$WARP_PRIVATE_KEY" ]; then
        local warp_endpoint=$(get_warp_endpoint)
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
        # 使用 argosbx 的正确格式：endpoint tag 为 warp-out，route.final 直接指向它
        outbounds_json="{\"type\":\"direct\",\"tag\":\"direct\"}],\"endpoints\":[{\"type\":\"wireguard\",\"tag\":\"warp-out\",\"address\":[\"172.16.0.2/32\",\"${warp_ipv6}/128\"],\"private_key\":\"${WARP_PRIVATE_KEY}\",\"peers\":[{\"address\":\"${ep_ip}\",\"port\":${ep_port},\"public_key\":\"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=\",\"allowed_ips\":[\"0.0.0.0/0\",\"::/0\"],\"reserved\":${warp_reserved}}]}],\"route\":{\"rules\":[{\"action\":\"sniff\"},{\"action\":\"resolve\",\"strategy\":\"prefer_ipv4\"}],\"final\":\"warp-out\"}"
    else
        outbounds_json="{\"type\":\"direct\",\"tag\":\"direct\"}]"
    fi
    
    echo "{\"log\":{\"level\":\"info\"},\"inbounds\":[${inbounds}],\"outbounds\":[${outbounds_json}}" | python3 -m json.tool 2>/dev/null > "$SINGBOX_CONF" || echo "{\"log\":{\"level\":\"info\"},\"inbounds\":[${inbounds}],\"outbounds\":[${outbounds_json}}" > "$SINGBOX_CONF"
    
    echo -e "$links" > "$SINGBOX_DIR/combo_links.txt"
    
    echo -e ""
    echo -e "${Green}========== 预设组合安装完成 ==========${Reset}"
    echo -e ""
    echo -e "${Info} 分享链接:"
    echo -e "${Yellow}$(echo -e "$links")${Reset}"
    echo -e ""
    
    read -p "是否立即启动? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# ==================== 辅助功能 ====================
# 查看日志
view_logs() {
    echo -e ""
    echo -e "${Cyan}========== sing-box 日志 ==========${Reset}"
    echo -e ""
    
    # 优先使用 journalctl
    if command -v journalctl &>/dev/null && systemctl is-active sing-box &>/dev/null 2>&1; then
        echo -e "${Info} 使用 journalctl 查看日志 (最近 50 行):"
        echo -e ""
        journalctl -u sing-box -n 50 --no-pager
    elif [ -f "$SINGBOX_LOG" ]; then
        echo -e "${Info} 日志文件: $SINGBOX_LOG"
        echo -e ""
        tail -n 50 "$SINGBOX_LOG"
    else
        echo -e "${Warning} 未找到日志文件"
        echo -e ""
        echo -e "${Tip} 尝试查看 journalctl:"
        journalctl -u sing-box -n 30 --no-pager 2>/dev/null || echo -e "${Error} journalctl 也没有日志"
    fi
    
    echo -e ""
    echo -e "${Green}====================================${Reset}"
}

# 查看配置文件
view_config() {
    echo -e ""
    echo -e "${Cyan}========== sing-box 配置 ==========${Reset}"
    echo -e ""
    
    if [ -f "$SINGBOX_CONF" ]; then
        echo -e "${Info} 配置文件: $SINGBOX_CONF"
        echo -e ""
        
        # 尝试用 jq 格式化，否则直接 cat
        if command -v jq &>/dev/null; then
            jq '.' "$SINGBOX_CONF" 2>/dev/null || cat "$SINGBOX_CONF"
        else
            cat "$SINGBOX_CONF"
        fi
    else
        echo -e "${Error} 配置文件不存在: $SINGBOX_CONF"
    fi
    
    echo -e ""
    echo -e "${Green}====================================${Reset}"
}

# 查看节点信息
show_node_info() {
    echo -e ""
    echo -e "${Cyan}========== 节点信息 ==========${Reset}"
    echo -e ""
    
    # 读取保存的链接
    if [ -f "$SINGBOX_DIR/combo_links.txt" ]; then
        echo -e "${Info} 分享链接:"
        echo -e ""
        cat "$SINGBOX_DIR/combo_links.txt"
    elif [ -f "$LINKS_FILE" ]; then
        echo -e "${Info} 分享链接:"
        echo -e ""
        cat "$LINKS_FILE"
    else
        echo -e "${Warning} 未找到节点链接文件"
        echo -e "${Tip} 请重新安装节点以生成链接"
    fi
    
    echo -e ""
    echo -e "${Green}===============================${Reset}"
}

# ==================== 主菜单 ====================
show_singbox_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔═╗╦╔╗╔╔═╗   ╔╗ ╔═╗═╗ ╦
    ╚═╗║║║║║ ╦───╠╩╗║ ║╔╩╦╝
    ╚═╝╩╝╚╝╚═╝   ╚═╝╚═╝╩ ╚═
    多协议代理节点
EOF
        echo -e "${Reset}"
        
        # 显示状态
        if [ -f "$SINGBOX_BIN" ]; then
            echo -e " 安装状态: ${Green}已安装${Reset}"
            if pgrep -f "sing-box" &>/dev/null; then
                echo -e " 运行状态: ${Green}运行中${Reset}"
            else
                echo -e " 运行状态: ${Red}已停止${Reset}"
            fi
        else
            echo -e " 安装状态: ${Yellow}未安装${Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== sing-box 管理 ====================${Reset}"
        echo -e " ${Yellow}单协议安装${Reset}"
        echo -e " ${Green}1.${Reset}  Hysteria2 (推荐)"
        echo -e " ${Green}2.${Reset}  TUIC v5"
        echo -e " ${Green}3.${Reset}  VLESS Reality"
        echo -e " ${Green}4.${Reset}  AnyTLS (新)"
        echo -e " ${Green}5.${Reset}  ${Cyan}Any-Reality${Reset} (AnyTLS + Reality)"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}多协议组合${Reset}"
        echo -e " ${Green}6.${Reset}  ${Cyan}自定义组合${Reset} (多选协议)"
        echo -e " ${Green}7.${Reset}  ${Cyan}预设组合${Reset} (一键安装)"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}服务管理${Reset}"
        echo -e " ${Green}8.${Reset}  启动"
        echo -e " ${Green}9.${Reset}  停止"
        echo -e " ${Green}10.${Reset} 重启"
        echo -e " ${Green}11.${Reset} 查看状态"
        echo -e " ${Green}12.${Reset} ${Yellow}查看日志${Reset}"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}13.${Reset} 查看节点信息"
        echo -e " ${Green}14.${Reset} 查看配置文件"
        echo -e " ${Green}15.${Reset} ${Cyan}配置 WARP 出站${Reset}"
        echo -e " ${Green}16.${Reset} 卸载 sing-box"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回主菜单"
        echo -e "${Green}========================================================${Reset}"
        
        read -p " 请选择 [0-16]: " choice
        
        case "$choice" in
            1) install_hysteria2 ;;
            2) install_tuic ;;
            3) install_vless_reality ;;
            4) install_anytls ;;
            5) install_any_reality ;;
            6) install_combo ;;
            7) install_preset_combo ;;
            8) start_singbox ;;
            9) stop_singbox ;;
            10) restart_singbox ;;
            11) status_singbox ;;
            12) view_logs ;;
            13) show_node_info ;;
            14) view_config ;;
            15)
                # 调用 WARP 模块的函数
                local warp_manager="$VPSPLAY_DIR/modules/warp/manager.sh"
                if [ -f "$warp_manager" ]; then
                    source "$warp_manager"
                    configure_existing_warp_outbound
                else
                    echo -e "${Error} WARP 模块未找到"
                fi
                ;;
            16) uninstall_singbox ;;
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
    detect_system
    show_singbox_menu
fi
