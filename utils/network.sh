#!/bin/bash
# 网络工具 - VPS-play
# IP获取、端口测试、连通性检查等

# 加载环境检测
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env_detect.sh" 2>/dev/null || true

# ==================== IP 获取 ====================
# 获取公网 IPv4
get_public_ipv4() {
    local ip=""
    
    # 尝试多个 API
    ip=$(curl -s4m5 ip.sb 2>/dev/null) || \
    ip=$(curl -s4m5 ifconfig.me 2>/dev/null) || \
    ip=$(curl -s4m5 icanhazip.com 2>/dev/null) || \
    ip=$(curl -s4m5 ipinfo.io/ip 2>/dev/null) || \
    ip=$(wget -qO- -4 ip.sb 2>/dev/null)
    
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    else
        echo "unknown"
        return 1
    fi
}

# 获取公网 IPv6
get_public_ipv6() {
    local ip=""
    
    ip=$(curl -s6m5 ip.sb 2>/dev/null) || \
    ip=$(curl -s6m5 ifconfig.me 2>/dev/null) || \
    ip=$(curl -s6m5 icanhazip.com 2>/dev/null)
    
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    else
        echo "unknown"
        return 1
    fi
}

# 获取本地 IP
get_local_ip() {
    local ip=""
    
    if command -v hostname &>/dev/null; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    if [ -z "$ip" ] && command -v ip &>/dev/null; then
        ip=$(ip addr show 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d'/' -f1)
    fi
    
    if [ -z "$ip" ] && command -v ifconfig &>/dev/null; then
        ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')
    fi
    
    echo "${ip:-unknown}"
}

# 获取所有网络接口和IP
get_all_interfaces() {
    echo -e "${Info} 网络接口信息:"
    
    if command -v ip &>/dev/null; then
        ip -o addr show | grep -v '127.0.0.1' | awk '{print $2, $4}'
    elif command -v ifconfig &>/dev/null; then
        ifconfig | grep -E '^[a-z]|inet ' | grep -v '127.0.0.1'
    else
        echo -e "${Warning} 无法获取网络接口信息"
    fi
}

# ==================== 端口测试 ====================
# 测试 TCP 端口连通性
test_tcp_port() {
    local host=$1
    local port=$2
    local timeout=${3:-3}
    
    if command -v nc &>/dev/null; then
        if timeout "$timeout" nc -z -w 2 "$host" "$port" &>/dev/null; then
            echo -e "${Info} TCP $host:$port ${Green}可达${Reset}"
            return 0
        else
            echo -e "${Warning} TCP $host:$port ${Red}不可达${Reset}"
            return 1
        fi
    elif command -v telnet &>/dev/null; then
        if timeout "$timeout" bash -c "echo '' | telnet $host $port" &>/dev/null; then
            echo -e "${Info} TCP $host:$port ${Green}可达${Reset}"
            return 0
        else
            echo -e "${Warning} TCP $host:$port ${Red}不可达${Reset}"
            return 1
        fi
    else
        echo -e "${Error} 需要 nc 或 telnet 工具"
        return 2
    fi
}

# 测试 UDP 端口连通性
test_udp_port() {
    local host=$1
    local port=$2
    local timeout=${3:-3}
    
    if command -v nc &>/dev/null; then
        if timeout "$timeout" nc -z -u -w 2 "$host" "$port" &>/dev/null; then
            echo -e "${Info} UDP $host:$port ${Green}可能可达${Reset}"
            return 0
        else
            echo -e "${Warning} UDP $host:$port ${Yellow}无法确定${Reset}"
            return 1
        fi
    else
        echo -e "${Warning} UDP 端口测试需要 nc 工具"
        return 2
    fi
}

# 批量测试端口
test_ports() {
    local host=$1
    shift
    local ports=("$@")
    
    echo -e "${Info} 测试 $host 的端口连通性:"
    
    for port in "${ports[@]}"; do
        test_tcp_port "$host" "$port" 2
    done
}

# ==================== 连通性检查 ====================
# Ping 测试
ping_test() {
    local host=$1
    local count=${2:-4}
    
    echo -e "${Info} Ping $host ($count 次):"
    
    if command -v ping &>/dev/null; then
        ping -c "$count" "$host"
    else
        echo -e "${Error} ping 命令不可用"
        return 1
    fi
}

# HTTP 测试
http_test() {
    local url=$1
    local method=${2:-GET}
    
    echo -e "${Info} HTTP 测试: $url"
    
    if command -v curl &>/dev/null; then
        local start_time=$(date +%s%N)
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X "$method" "$url")
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 ))
        
        echo -e "  HTTP 状态码: ${Cyan}$http_code${Reset}"
        echo -e "  响应时间: ${Cyan}${duration}ms${Reset}"
        
        if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
            echo -e "  状态: ${Green}正常${Reset}"
            return 0
        else
            echo -e "  状态: ${Red}异常${Reset}"
            return 1
        fi
    else
        echo -e "${Error} curl 命令不可用"
        return 2
    fi
}

# ==================== DNS 解析 ====================
# DNS 解析
dns_resolve() {
    local domain=$1
    
    echo -e "${Info} DNS 解析: $domain"
    
    if command -v dig &>/dev/null; then
        dig +short "$domain"
    elif command -v nslookup &>/dev/null; then
        nslookup "$domain" | grep -A 2 "Name:" | tail -2
    elif command -v host &>/dev/null; then
        host "$domain"
    else
        echo -e "${Error} 需要 dig/nslookup/host 工具"
        return 1
    fi
}

# 反向 DNS 解析
reverse_dns() {
    local ip=$1
    
    echo -e "${Info} 反向 DNS 解析: $ip"
    
    if command -v dig &>/dev/null; then
        dig +short -x "$ip"
    elif command -v host &>/dev/null; then
        host "$ip"
    else
        echo -e "${Error} 需要 dig/host 工具"
        return 1
    fi
}

# ==================== 网络诊断 ====================
# 路由追踪
traceroute_test() {
    local host=$1
    local max_hops=${2:-30}
    
    echo -e "${Info} 路由追踪: $host"
    
    if command -v traceroute &>/dev/null; then
        traceroute -m "$max_hops" "$host"
    elif command -v tracepath &>/dev/null; then
        tracepath "$host"
    elif command -v mtr &>/dev/null; then
        mtr -r -c 10 "$host"
    else
        echo -e "${Error} 需要 traceroute/tracepath/mtr 工具"
        return 1
    fi
}

# 网络速度测试
speedtest() {
    echo -e "${Info} 网络速度测试..."
    
    if command -v speedtest-cli &>/dev/null; then
        speedtest-cli
    elif command -v speedtest &>/dev/null; then
        speedtest
    else
        echo -e "${Warning} speedtest-cli 未安装，使用简单下载测试"
        
        # 从 cachefly 下载测试文件
        local test_url="http://cachefly.cachefly.net/10mb.test"
        echo -e "${Info} 下载测试文件 (10MB)..."
        
        local start_time=$(date +%s)
        curl -o /dev/null -s "$test_url"
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        if [ "$duration" -gt 0 ]; then
            local speed=$((10 / duration))
            echo -e "  下载速度: 约 ${Cyan}${speed}MB/s${Reset}"
        else
            echo -e "  下载速度: 非常快 (>10MB/s)"
        fi
    fi
}

# ==================== 网络信息汇总 ====================
network_info() {
    echo -e ""
    echo -e "${Green}==================== 网络信息 ====================${Reset}"
    
    # 公网 IP
    echo -e "${Cyan}公网 IPv4:${Reset}"
    local ipv4=$(get_public_ipv4)
    echo -e "  $ipv4"
    
    echo -e "\n${Cyan}公网 IPv6:${Reset}"
    local ipv6=$(get_public_ipv6)
    echo -e "  $ipv6"
    
    # 本地 IP
    echo -e "\n${Cyan}本地 IP:${Reset}"
    local local_ip=$(get_local_ip)
    echo -e "  $local_ip"
    
    # 判断 NAT
    if [ "$ipv4" != "unknown" ] && [ "$local_ip" != "unknown" ] && [ "$ipv4" != "$local_ip" ]; then
        echo -e "\n${Yellow}网络类型: NAT环境${Reset}"
    else
        echo -e "\n${Green}网络类型: 公网直连${Reset}"
    fi
    
    # 网络接口
    echo -e "\n${Cyan}网络接口:${Reset}"
    get_all_interfaces
    
    echo -e "\n${Green}=================================================${Reset}"
}

# 如果直接运行此脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        ip)
            case "${2:-all}" in
                public|pub|4)
                    get_public_ipv4
                    ;;
                6|ipv6)
                    get_public_ipv6
                    ;;
                local|loc)
                    get_local_ip
                    ;;
                all|*)
                    network_info
                    ;;
            esac
            ;;
        test)
            case "${2:-tcp}" in
                tcp)
                    test_tcp_port "$3" "$4" "$5"
                    ;;
                udp)
                    test_udp_port "$3" "$4" "$5"
                    ;;
                http|https)
                    http_test "$3"
                    ;;
                *)
                    echo -e "${Error} 无效的测试类型"
                    ;;
            esac
            ;;
        dns)
            dns_resolve "$2"
            ;;
        rdns)
            reverse_dns "$2"
            ;;
        ping)
            ping_test "$2" "$3"
            ;;
        trace)
            traceroute_test "$2" "$3"
            ;;
        speed)
            speedtest
            ;;
        info)
            network_info
            ;;
        *)
            echo "用法: $0 <命令> [参数...]"
            echo ""
            echo "命令:"
            echo "  ip [public|6|local|all]         获取IP地址"
            echo "  test tcp <host> <port>           测试TCP端口"
            echo "  test udp <host> <port>           测试UDP端口"
            echo "  test http <url>                  测试HTTP连接"
            echo "  dns <domain>                     DNS解析"
            echo "  rdns <ip>                        反向DNS解析"
            echo "  ping <host> [count]              Ping测试"
            echo "  trace <host> [max_hops]          路由追踪"
            echo "  speed                            网速测试"
            echo "  info                             网络信息汇总"
            echo ""
            echo "示例:"
            echo "  $0 ip                            # 显示所有IP信息"
            echo "  $0 test tcp google.com 443       # 测试TCP端口"
            echo "  $0 dns google.com                # DNS解析"
            echo "  $0 info                          # 显示网络信息汇总"
            ;;
    esac
fi
