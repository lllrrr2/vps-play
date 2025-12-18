#!/bin/bash
# 进程管理工具 - VPS-play
# 支持 systemd、rc.d、cron、screen 等多种方式

# 加载环境检测
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env_detect.sh" 2>/dev/null || true

# ==================== 全局变量 ====================
PROCESS_DIR="$HOME/.vps-play/processes"
mkdir -p "$PROCESS_DIR"

# ==================== 进程管理方式 ====================
PROCESS_METHOD=""  # systemd/screen/nohup

# ==================== 检测进程管理方式 ====================
detect_process_method() {
    if [ "$HAS_SYSTEMD" = true ] && [ "$HAS_ROOT" = true ]; then
        PROCESS_METHOD="systemd"
        echo -e "${Info} 进程管理: ${Cyan}systemd${Reset}"
    elif command -v screen &>/dev/null; then
        PROCESS_METHOD="screen"
        echo -e "${Info} 进程管理: ${Cyan}screen${Reset}"
    else
        PROCESS_METHOD="nohup"
        echo -e "${Info} 进程管理: ${Cyan}nohup${Reset}"
    fi
}

# ==================== systemd 方式 ====================
# 创建 systemd 服务
create_systemd_service() {
    local name=$1
    local exec_path=$2
    local description=${3:-"VPS-play service: $name"}
    local user=${4:-$(whoami)}
    
    if [ "$HAS_ROOT" != true ]; then
        echo -e "${Error} 需要 root 权限创建 systemd 服务"
        return 1
    fi
    
    local service_file="/etc/systemd/system/${name}.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=$description
After=network.target

[Service]
Type=simple
User=$user
ExecStart=$exec_path
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    echo -e "${Info} systemd 服务已创建: ${name}.service"
}

# 启动 systemd 服务
start_systemd_service() {
    local name=$1
    systemctl start "${name}.service"
    systemctl enable "${name}.service"
    echo -e "${Info} 服务已启动并设置为开机自启"
}

# 停止 systemd 服务
stop_systemd_service() {
    local name=$1
    systemctl stop "${name}.service"
    systemctl disable "${name}.service"
    echo -e "${Info} 服务已停止"
}

# 查看 systemd 服务状态
status_systemd_service() {
    local name=$1
    systemctl status "${name}.service"
}

# ==================== screen 方式 ====================
# 在 screen 中启动进程
start_screen_process() {
    local name=$1
    local command=$2
    local working_dir=${3:-$HOME}
    
    # 检查是否已存在
    if screen -ls | grep -q "\\.${name}[[:space:]]"; then
        echo -e "${Warning} screen 会话 ${name} 已存在"
        return 1
    fi
    
    # 创建 screen 会话
    cd "$working_dir"
    screen -dmS "$name" bash -c "$command"
    
    if screen -ls | grep -q "\\.${name}[[:space:]]"; then
        echo -e "${Info} screen 会话已创建: ${name}"
        # 保存信息
        echo "name=$name" > "$PROCESS_DIR/${name}.info"
        echo "command=$command" >> "$PROCESS_DIR/${name}.info"
        echo "working_dir=$working_dir" >> "$PROCESS_DIR/${name}.info"
        echo "created=$(date '+%Y-%m-%d %H:%M:%S')" >> "$PROCESS_DIR/${name}.info"
        return 0
    else
        echo -e "${Error} screen 会话创建失败"
        return 1
    fi
}

# 停止 screen 进程
stop_screen_process() {
    local name=$1
    
    if screen -ls | grep -q "\\.${name}[[:space:]]"; then
        screen -S "$name" -X quit
        echo -e "${Info} screen 会话已停止: ${name}"
        rm -f "$PROCESS_DIR/${name}.info"
    else
        echo -e "${Warning} screen 会话不存在: ${name}"
    fi
}

# 进入 screen 会话
attach_screen_process() {
    local name=$1
    
    if screen -ls | grep -q "\\.${name}[[:space:]]"; then
        screen -r "$name"
    else
        echo -e "${Warning} screen 会话不存在: ${name}"
    fi
}

# 列出所有 screen 会话
list_screen_processes() {
    echo -e "${Info} screen 会话列表:"
    screen -ls
}

# ==================== nohup 方式 ====================
# 使用 nohup 启动进程
start_nohup_process() {
    local name=$1
    local command=$2
    local working_dir=${3:-$HOME}
    local log_file="${4:-$PROCESS_DIR/${name}.log}"
    
    # 检查是否已运行
    if [ -f "$PROCESS_DIR/${name}.pid" ]; then
        local old_pid=$(cat "$PROCESS_DIR/${name}.pid")
        if kill -0 "$old_pid" 2>/dev/null; then
            echo -e "${Warning} 进程 ${name} 已在运行 (PID: $old_pid)"
            return 1
        fi
    fi
    
    # 启动进程
    cd "$working_dir"
    nohup bash -c "$command" > "$log_file" 2>&1 &
    local pid=$!
    
    # 保存 PID
    echo "$pid" > "$PROCESS_DIR/${name}.pid"
    
    # 保存信息
    echo "name=$name" > "$PROCESS_DIR/${name}.info"
    echo "command=$command" >> "$PROCESS_DIR/${name}.info"
    echo "working_dir=$working_dir" >> "$PROCESS_DIR/${name}.info"
    echo "log_file=$log_file" >> "$PROCESS_DIR/${name}.info"
    echo "pid=$pid" >> "$PROCESS_DIR/${name}.info"
    echo "created=$(date '+%Y-%m-%d %H:%M:%S')" >> "$PROCESS_DIR/${name}.info"
    
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${Info} 进程已启动: ${name} (PID: $pid)"
        return 0
    else
        echo -e "${Error} 进程启动失败"
        rm -f "$PROCESS_DIR/${name}.pid"
        return 1
    fi
}

# 停止 nohup 进程
stop_nohup_process() {
    local name=$1
    
    if [ -f "$PROCESS_DIR/${name}.pid" ]; then
        local pid=$(cat "$PROCESS_DIR/${name}.pid")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            echo -e "${Info} 进程已停止: ${name} (PID: $pid)"
        else
            echo -e "${Warning} 进程不存在或已停止"
        fi
        rm -f "$PROCESS_DIR/${name}.pid"
    else
        echo -e "${Warning} PID 文件不存在: ${name}"
    fi
}

# 查看 nohup 进程状态
status_nohup_process() {
    local name=$1
    
    if [ -f "$PROCESS_DIR/${name}.pid" ]; then
        local pid=$(cat "$PROCESS_DIR/${name}.pid")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${Info} 进程状态: ${Green}运行中${Reset} (PID: $pid)"
            
            # 显示进程信息
            if [ -f "$PROCESS_DIR/${name}.info" ]; then
                echo -e "\n进程信息:"
                cat "$PROCESS_DIR/${name}.info"
            fi
            
            # 显示最新日志
            if [ -f "$PROCESS_DIR/${name}.log" ]; then
                echo -e "\n最新日志 (最后10行):"
                tail -10 "$PROCESS_DIR/${name}.log"
            fi
            return 0
        else
            echo -e "${Warning} 进程已停止"
            return 1
        fi
    else
        echo -e "${Warning} 进程未运行"
        return 1
    fi
}

# ==================== 统一接口 ====================
# 启动进程
start_process() {
    local name=$1
    local command=$2
    local working_dir=${3:-$HOME}
    local options=${4:-}
    
    detect_process_method
    
    case "$PROCESS_METHOD" in
        systemd)
            # 创建临时启动脚本
            local script_file="/tmp/vps-play-${name}.sh"
            echo "#!/bin/bash" > "$script_file"
            echo "cd $working_dir" >> "$script_file"
            echo "$command" >> "$script_file"
            chmod +x "$script_file"
            
            create_systemd_service "$name" "$script_file" "VPS-play: $name"
            start_systemd_service "$name"
            ;;
        screen)
            start_screen_process "$name" "$command" "$working_dir"
            ;;
        nohup)
            start_nohup_process "$name" "$command" "$working_dir"
            ;;
    esac
}

# 停止进程
stop_process() {
    local name=$1
    
    detect_process_method
    
    case "$PROCESS_METHOD" in
        systemd)
            stop_systemd_service "$name"
            ;;
        screen)
            stop_screen_process "$name"
            ;;
        nohup)
            stop_nohup_process "$name"
            ;;
    esac
}

# 重启进程
restart_process() {
    local name=$1
    
    echo -e "${Info} 重启进程: ${name}"
    stop_process "$name"
    sleep 2
    
    # 从保存的信息中恢复命令
    if [ -f "$PROCESS_DIR/${name}.info" ]; then
        source "$PROCESS_DIR/${name}.info"
        start_process "$name" "$command" "$working_dir"
    else
        echo -e "${Error} 无法找到进程信息"
        return 1
    fi
}

# 查看进程状态
status_process() {
    local name=$1
    
    detect_process_method
    
    case "$PROCESS_METHOD" in
        systemd)
            status_systemd_service "$name"
            ;;
        screen)
            if screen -ls | grep -q "\\.${name}[[:space:]]"; then
                echo -e "${Info} screen 会话: ${Green}运行中${Reset}"
                screen -ls | grep "\\.${name}[[:space:]]"
            else
                echo -e "${Warning} screen 会话未运行"
            fi
            ;;
        nohup)
            status_nohup_process "$name"
            ;;
    esac
}

# 列出所有进程
list_processes() {
    echo -e "${Info} 已管理的进程:"
    
    detect_process_method
    
    case "$PROCESS_METHOD" in
        systemd)
            systemctl list-units --type=service | grep vps-play
            ;;
        screen)
            list_screen_processes
            ;;
        nohup)
            if [ -d "$PROCESS_DIR" ]; then
                for info_file in "$PROCESS_DIR"/*.info; do
                    if [ -f "$info_file" ]; then
                        local name=$(basename "$info_file" .info)
                        echo -n "  [$name] - "
                        if status_nohup_process "$name" &>/dev/null; then
                            echo -e "${Green}运行中${Reset}"
                        else
                            echo -e "${Red}已停止${Reset}"
                        fi
                    fi
                done
            fi
            ;;
    esac
}

# 查看进程日志
view_log() {
    local name=$1
    local lines=${2:-50}
    
    if [ -f "$PROCESS_DIR/${name}.log" ]; then
        echo -e "${Info} 进程日志 (最后 $lines 行):"
        tail -n "$lines" "$PROCESS_DIR/${name}.log"
    else
        echo -e "${Warning} 日志文件不存在"
    fi
}

# 如果直接运行此脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    detect_process_method
    
    case "${1:-help}" in
        start)
            start_process "$2" "$3" "$4"
            ;;
        stop)
            stop_process "$2"
            ;;
        restart)
            restart_process "$2"
            ;;
        status)
            status_process "$2"
            ;;
        list)
            list_processes
            ;;
        log)
            view_log "$2" "$3"
            ;;
        *)
            echo "用法: $0 {start|stop|restart|status|list|log} [参数...]"
            echo ""
            echo "命令:"
            echo "  start <name> <command> [working_dir]  启动进程"
            echo "  stop <name>                            停止进程"
            echo "  restart <name>                         重启进程"
            echo "  status <name>                          查看进程状态"
            echo "  list                                   列出所有进程"
            echo "  log <name> [lines]                     查看进程日志"
            ;;
    esac
fi
