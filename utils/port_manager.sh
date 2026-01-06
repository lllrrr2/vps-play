#!/bin/bash
# 端口管理工具 - VPS-play
# 支持 devil (Serv00)、iptables、socat 等多种端口管理方式

# 加载环境检测
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env_detect.sh" 2>/dev/null || true

# ==================== 端口管理方式 ====================
PORT_METHOD=""  # devil/iptables/socat/direct

# ==================== 检测端口管理方式 ====================
detect_port_method() {
    # 实时检测权限
    local has_root=false
    [ "$(id -u)" = "0" ] && has_root=true
    
    if command -v devil &>/dev/null; then
        PORT_METHOD="devil"
        echo -e "${Info} 端口管理: ${Cyan}devil${Reset}"
    elif [ "$has_root" = true ] && command -v iptables &>/dev/null; then
        PORT_METHOD="iptables"
        echo -e "${Info} 端口管理: ${Cyan}iptables${Reset}"
    elif command -v socat &>/dev/null; then
        PORT_METHOD="socat"
        echo -e "${Info} 端口管理: ${Cyan}socat${Reset}"
    else
        PORT_METHOD="direct"
        echo -e "${Info} 端口管理: ${Yellow}direct (直接绑定)${Reset}"
    fi
}

# ==================== 添加端口 (devil) ====================
add_port_devil() {
    local port=$1
    local proto=${2:-tcp}  # tcp/udp
    
    echo -e "${Info} 使用 devil 添加端口 $port ($proto)..."
    
    case "$proto" in
        tcp)
            devil port add tcp "$port"
            ;;
        udp)
            devil port add udp "$port"
            ;;
        both)
            devil port add tcp "$port"
            devil port add udp "$port"
            ;;
        *)
            echo -e "${Error} 无效的协议类型: $proto"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${Info} 端口 $port ($proto) 添加成功"
        return 0
    else
        echo -e "${Error} 端口添加失败"
        return 1
    fi
}

# ==================== 删除端口 (devil) ====================
del_port_devil() {
    local port=$1
    local proto=${2:-tcp}
    
    echo -e "${Info} 使用 devil 删除端口 $port ($proto)..."
    
    case "$proto" in
        tcp)
            devil port del tcp "$port"
            ;;
        udp)
            devil port del udp "$port"
            ;;
        both)
            devil port del tcp "$port"
            devil port del udp "$port"
            ;;
    esac
}

# ==================== 列出端口 (devil) ====================
list_ports_devil() {
    echo -e "${Info} 已添加的端口:"
    devil port list
}

# ==================== 添加端口映射 (iptables) ====================
add_port_iptables() {
    local port=$1
    local target_port=$2
    local proto=${3:-tcp}
    
    if [ -z "$target_port" ]; then
        echo -e "${Error} 需要指定目标端口"
        return 1
    fi
    
    echo -e "${Info} 使用 iptables 添加端口映射 $port -> $target_port ($proto)..."
    
    # NAT 端口转发
    iptables -t nat -A PREROUTING -p "$proto" --dport "$port" -j REDIRECT --to-port "$target_port"
    
    if [ $? -eq 0 ]; then
        echo -e "${Info} 端口映射添加成功"
        # 保存规则
        if command -v iptables-save &>/dev/null; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        return 0
    else
        echo -e "${Error} 端口映射添加失败"
        return 1
    fi
}

# ==================== 删除端口映射 (iptables) ====================
del_port_iptables() {
    local port=$1
    local target_port=$2
    local proto=${3:-tcp}
    
    echo -e "${Info} 使用 iptables 删除端口映射 $port -> $target_port ($proto)..."
    
    iptables -t nat -D PREROUTING -p "$proto" --dport "$port" -j REDIRECT --to-port "$target_port"
    
    # 保存规则
    if command -v iptables-save &>/dev/null; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
}

# ==================== 列出端口映射 (iptables) ====================
list_ports_iptables() {
    echo -e "${Info} 端口映射规则:"
    if [ "$(id -u)" != "0" ]; then
        echo -e "${Error} iptables 需要 root 权限"
        echo -e "${Tip} NAT VPS 可使用 socat 进行端口转发"
        echo -e "${Tip} 或使用 ss -tlnp 查看监听端口"
        return 1
    fi
    iptables -t nat -L PREROUTING -n -v --line-numbers | grep REDIRECT
}

# ==================== 启动 socat 端口转发 ====================
start_socat_forward() {
    local listen_port=$1
    local target_host=$2
    local target_port=$3
    local proto=${4:-tcp}
    
    echo -e "${Info} 使用 socat 启动端口转发 $listen_port -> $target_host:$target_port ($proto)..."
    
    local socat_cmd=""
    case "$proto" in
        tcp)
            socat_cmd="socat TCP4-LISTEN:$listen_port,reuseaddr,fork TCP4:$target_host:$target_port"
            ;;
        udp)
            socat_cmd="socat UDP4-LISTEN:$listen_port,reuseaddr,fork UDP4:$target_host:$target_port"
            ;;
        *)
            echo -e "${Error} 无效的协议类型"
            return 1
            ;;
    esac
    
    # 后台运行
    nohup $socat_cmd > /dev/null 2>&1 &
    local pid=$!
    
    echo -e "${Info} socat 进程已启动 (PID: $pid)"
    
    # 保存 PID
    mkdir -p "$HOME/.vps-play/socat"
    echo "$pid" > "$HOME/.vps-play/socat/${listen_port}_${proto}.pid"
}

# ==================== 停止 socat 端口转发 ====================
stop_socat_forward() {
    local listen_port=$1
    local proto=${2:-tcp}
    
    local pid_file="$HOME/.vps-play/socat/${listen_port}_${proto}.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            echo -e "${Info} socat 进程已停止 (PID: $pid)"
        fi
        rm -f "$pid_file"
    else
        # 尝试查找并杀死进程
        pkill -f "socat.*:$listen_port"
        echo -e "${Info} socat 进程已停止"
    fi
}

# ==================== 列出 socat 转发 ====================
list_socat_forwards() {
    echo -e "${Info} socat 端口转发:"
    ps aux | grep socat | grep -v grep
}

# ==================== 统一接口：添加端口 ====================
add_port() {
    local port=$1
    local proto=${2:-tcp}
    local target_host=${3:-}
    local target_port=${4:-}
    
    detect_port_method
    
    case "$PORT_METHOD" in
        devil)
            add_port_devil "$port" "$proto"
            ;;
        iptables)
            if [ -n "$target_port" ]; then
                add_port_iptables "$port" "$target_port" "$proto"
            else
                echo -e "${Warning} iptables 模式需要指定目标端口"
                return 1
            fi
            ;;
        socat)
            if [ -n "$target_host" ] && [ -n "$target_port" ]; then
                start_socat_forward "$port" "$target_host" "$target_port" "$proto"
            else
                echo -e "${Warning} socat 模式需要指定目标主机和端口"
                return 1
            fi
            ;;
        direct)
            echo -e "${Info} 直接绑定模式，端口 $port 可直接使用"
            ;;
    esac
}

# ==================== 统一接口：删除端口 ====================
del_port() {
    local port=$1
    local proto=${2:-tcp}
    local target_port=${3:-}
    
    detect_port_method
    
    case "$PORT_METHOD" in
        devil)
            del_port_devil "$port" "$proto"
            ;;
        iptables)
            if [ -n "$target_port" ]; then
                del_port_iptables "$port" "$target_port" "$proto"
            fi
            ;;
        socat)
            stop_socat_forward "$port" "$proto"
            ;;
        direct)
            echo -e "${Info} 直接绑定模式，无需删除端口"
            ;;
    esac
}

# ==================== 统一接口：列出端口 ====================
list_ports() {
    detect_port_method
    
    case "$PORT_METHOD" in
        devil)
            list_ports_devil
            ;;
        iptables)
            list_ports_iptables
            ;;
        socat)
            list_socat_forwards
            ;;
        direct)
            echo -e "${Info} 直接绑定模式，使用 netstat 查看:"
            netstat -tlnp 2>/dev/null || ss -tlnp 2>/dev/null || sockstat -4l 2>/dev/null
            ;;
    esac
}

# ==================== 检查端口是否可用 ====================
check_port_available() {
    local port=$1
    
    if command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | grep -q ":$port " && return 1
    elif command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep -q ":$port " && return 1
    elif command -v sockstat &>/dev/null; then
        sockstat -4 -l 2>/dev/null | grep -q ":$port " && return 1
    fi
    
    return 0
}

# ==================== 获取随机可用端口（带锁防竞态） ====================
get_random_port() {
    local min=${1:-10000}
    local max=${2:-65535}
    local port
    local lock_file="${HOME}/.vps-play/locks/port.lock"
    
    # 确保锁目录存在
    mkdir -p "$(dirname "$lock_file")" 2>/dev/null || true
    
    # 使用 flock 获取排他锁
    (
        # 尝试获取锁，超时 5 秒
        if command -v flock &>/dev/null; then
            flock -x -w 5 200 || {
                echo -e "${Warning} 无法获取端口锁，使用无锁模式" >&2
            }
        fi
        
        for i in {1..50}; do
            port=$((RANDOM % (max - min + 1) + min))
            if check_port_available "$port"; then
                echo "$port"
                exit 0
            fi
        done
        
        echo -e "${Error} 无法找到可用端口" >&2
        exit 1
    ) 200>"$lock_file"
}

# 如果直接运行此脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    detect_port_method
    
    case "${1:-help}" in
        add)
            add_port "$2" "$3" "$4" "$5"
            ;;
        del)
            del_port "$2" "$3" "$4"
            ;;
        list)
            list_ports
            ;;
        check)
            if check_port_available "$2"; then
                echo -e "${Info} 端口 $2 可用"
            else
                echo -e "${Warning} 端口 $2 已被占用"
            fi
            ;;
        random)
            port=$(get_random_port "$2" "$3")
            echo -e "${Info} 随机端口: $port"
            ;;
        *)
            echo "用法: $0 {add|del|list|check|random} [参数...]"
            echo ""
            echo "命令:"
            echo "  add <port> [proto] [target_host] [target_port]  添加端口/映射"
            echo "  del <port> [proto] [target_port]                删除端口/映射"
            echo "  list                                            列出所有端口"
            echo "  check <port>                                     检查端口是否可用"
            echo "  random [min] [max]                              获取随机可用端口"
            ;;
    esac
fi
