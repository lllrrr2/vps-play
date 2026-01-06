#!/bin/bash
# VPS-play 安全操作函数库
# 用途: 提供安全的文件操作、下载执行、进程管理函数
#
# Copyright (C) 2025 VPS-play Contributors

# 严格模式
set -Eeuo pipefail

# ==================== 配置 ====================
# 白名单路径前缀（只允许删除以下路径）
declare -a SAFE_RM_ALLOWED_PREFIXES=(
    "$HOME/.vps-play"
    "$HOME/vps-play"
    "/tmp/vps-play"
)

# PID 文件目录
PID_DIR="${HOME}/.vps-play/run"
LOCK_DIR="${HOME}/.vps-play/locks"

# 确保目录存在
mkdir -p "$PID_DIR" "$LOCK_DIR" 2>/dev/null || true

# ==================== 颜色定义 ====================
_Red="\033[31m"
_Green="\033[32m"
_Yellow="\033[33m"
_Cyan="\033[36m"
_Reset="\033[0m"
_Info="${_Green}[信息]${_Reset}"
_Error="${_Red}[错误]${_Reset}"
_Warning="${_Yellow}[警告]${_Reset}"

# ==================== 日志函数 ====================
log_info()    { echo -e "${_Info} $*"; }
log_error()   { echo -e "${_Error} $*" >&2; }
log_warning() { echo -e "${_Warning} $*"; }
log_debug()   { [[ "${DEBUG:-}" == "1" ]] && echo -e "[DEBUG] $*"; }

# ==================== Bug 1: 安全删除函数 ====================
# 用法: safe_rm "/path/to/delete"
# 只允许删除白名单内的路径
safe_rm() {
    local target="${1:-}"
    
    # 参数检查
    if [[ -z "$target" ]]; then
        log_error "safe_rm: 缺少目标路径参数"
        return 1
    fi
    
    # 规范化路径（去除末尾斜杠）
    target="${target%/}"
    
    # 防止删除根目录或 HOME
    if [[ "$target" == "/" || "$target" == "$HOME" || "$target" == "/root" ]]; then
        log_error "safe_rm: 拒绝删除危险路径: $target"
        return 1
    fi
    
    # 检查是否在白名单内
    local allowed=false
    for prefix in "${SAFE_RM_ALLOWED_PREFIXES[@]}"; do
        if [[ "$target" == "$prefix" || "$target" == "$prefix"/* ]]; then
            allowed=true
            break
        fi
    done
    
    if [[ "$allowed" != true ]]; then
        log_error "safe_rm: 路径不在白名单内: $target"
        log_error "允许的路径前缀: ${SAFE_RM_ALLOWED_PREFIXES[*]}"
        return 1
    fi
    
    # 检查路径是否存在
    if [[ ! -e "$target" ]]; then
        log_warning "safe_rm: 路径不存在，跳过: $target"
        return 0
    fi
    
    # 执行删除
    log_info "safe_rm: 删除 $target"
    rm -rf "$target"
}

# 安全删除文件（仅删除文件，不删除目录）
safe_rm_file() {
    local target="${1:-}"
    
    if [[ -z "$target" ]]; then
        log_error "safe_rm_file: 缺少目标路径参数"
        return 1
    fi
    
    if [[ -d "$target" ]]; then
        log_error "safe_rm_file: 目标是目录，请使用 safe_rm: $target"
        return 1
    fi
    
    if [[ -f "$target" ]]; then
        rm -f "$target"
    fi
}

# ==================== Bug 2: 安全下载执行函数 ====================
# 用法: safe_download_exec "https://example.com/script.sh" [expected_size]
# 先下载到临时文件，校验后再执行
# 注意: 使用子 shell 隔离 trap，避免覆盖全局 trap
safe_download_exec() {
    local url="${1:-}"
    local expected_size="${2:-0}"
    
    if [[ -z "$url" ]]; then
        log_error "safe_download_exec: 缺少 URL 参数"
        return 1
    fi
    
    # 使用子 shell 隔离 trap，避免覆盖调用方的 trap
    (
        local tmp_file
        tmp_file=$(mktemp "${TMPDIR:-/tmp}/vps-play-download.XXXXXX") || exit 1
        
        # 在子 shell 内设置 trap，不会影响父 shell
        trap 'rm -f "$tmp_file"' EXIT
        
        log_info "下载脚本: $url"
        
        # 下载
        if command -v curl &>/dev/null; then
            if ! curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$tmp_file"; then
                log_error "下载失败: $url"
                exit 1
            fi
        elif command -v wget &>/dev/null; then
            if ! wget -q --timeout=60 "$url" -O "$tmp_file"; then
                log_error "下载失败: $url"
                exit 1
            fi
        else
            log_error "未找到 curl 或 wget"
            exit 1
        fi
        
        # 检查文件是否为空
        if [[ ! -s "$tmp_file" ]]; then
            log_error "下载的文件为空"
            exit 1
        fi
        
        # 大小校验（可选）
        if [[ "$expected_size" -gt 0 ]]; then
            local actual_size
            if [[ "$(uname)" == "Darwin" ]]; then
                actual_size=$(stat -f%z "$tmp_file" 2>/dev/null)
            else
                actual_size=$(stat -c%s "$tmp_file" 2>/dev/null)
            fi
            
            if [[ "${actual_size:-0}" -lt "$expected_size" ]]; then
                log_error "文件大小异常: 期望 >= $expected_size, 实际 $actual_size"
                exit 1
            fi
        fi
        
        # 简单的脚本安全检查
        if grep -q 'rm -rf /\s*$\|rm -rf /$' "$tmp_file" 2>/dev/null; then
            log_error "检测到危险命令，拒绝执行"
            exit 1
        fi
        
        log_info "执行下载的脚本..."
        bash "$tmp_file"
    )
}

# 安全下载文件（不执行）
safe_download() {
    local url="${1:-}"
    local dest="${2:-}"
    local expected_size="${3:-0}"
    
    if [[ -z "$url" || -z "$dest" ]]; then
        log_error "safe_download: 缺少参数 (url, dest)"
        return 1
    fi
    
    log_info "下载: $url -> $dest"
    
    if command -v curl &>/dev/null; then
        if ! curl -fsSL --connect-timeout 10 --max-time 300 "$url" -o "$dest"; then
            log_error "下载失败: $url"
            return 1
        fi
    elif command -v wget &>/dev/null; then
        if ! wget -q --timeout=300 "$url" -O "$dest"; then
            log_error "下载失败: $url"
            return 1
        fi
    else
        log_error "未找到 curl 或 wget"
        return 1
    fi
    
    # 大小校验
    if [[ "$expected_size" -gt 0 ]]; then
        local actual_size
        if [[ "$(uname)" == "Darwin" ]]; then
            actual_size=$(stat -f%z "$dest" 2>/dev/null)
        else
            actual_size=$(stat -c%s "$dest" 2>/dev/null)
        fi
        
        if [[ "${actual_size:-0}" -lt "$expected_size" ]]; then
            log_error "文件大小异常: 期望 >= $expected_size, 实际 $actual_size"
            rm -f "$dest"
            return 1
        fi
    fi
    
    return 0
}

# ==================== Bug 3: 端口分配锁机制 ====================
# 用法: with_port_lock "command"
# 使用 flock 确保端口分配原子性
with_port_lock() {
    local lock_file="${LOCK_DIR}/port.lock"
    
    # 确保锁目录存在
    mkdir -p "$LOCK_DIR" 2>/dev/null || true
    
    (
        flock -x -w 10 200 || {
            log_error "无法获取端口分配锁"
            return 1
        }
        
        # 在锁内执行命令
        "$@"
    ) 200>"$lock_file"
}

# 获取随机可用端口（带锁）
get_random_port_safe() {
    local min_port="${1:-10000}"
    local max_port="${2:-65535}"
    local lock_file="${LOCK_DIR}/port.lock"
    
    mkdir -p "$LOCK_DIR" 2>/dev/null || true
    
    (
        flock -x -w 10 200 || {
            echo ""
            return 1
        }
        
        local port
        local attempts=0
        local max_attempts=100
        
        while [[ $attempts -lt $max_attempts ]]; do
            port=$((RANDOM % (max_port - min_port + 1) + min_port))
            
            # 检查端口是否被占用
            if ! ss -tuln 2>/dev/null | grep -q ":${port}\s"; then
                echo "$port"
                return 0
            fi
            
            ((attempts++))
        done
        
        log_error "无法找到可用端口"
        echo ""
        return 1
    ) 200>"$lock_file"
}

# ==================== Bug 4: PID 文件管理 ====================
# 用法: save_pid "service_name" "$!"
save_pid() {
    local name="${1:-}"
    local pid="${2:-}"
    
    if [[ -z "$name" || -z "$pid" ]]; then
        log_error "save_pid: 缺少参数 (name, pid)"
        return 1
    fi
    
    mkdir -p "$PID_DIR" 2>/dev/null || true
    echo "$pid" > "${PID_DIR}/${name}.pid"
    log_debug "保存 PID: $name -> $pid"
}

# 获取 PID
get_pid() {
    local name="${1:-}"
    local pid_file="${PID_DIR}/${name}.pid"
    
    if [[ -f "$pid_file" ]]; then
        cat "$pid_file"
    else
        echo ""
    fi
}

# 检查进程是否存活
is_process_alive() {
    local pid="${1:-}"
    
    if [[ -z "$pid" ]]; then
        return 1
    fi
    
    kill -0 "$pid" 2>/dev/null
}

# 安全停止进程（使用 PID 文件）
# 用法: safe_kill "service_name"
safe_kill() {
    local name="${1:-}"
    local signal="${2:-TERM}"
    
    if [[ -z "$name" ]]; then
        log_error "safe_kill: 缺少服务名参数"
        return 1
    fi
    
    local pid
    pid=$(get_pid "$name")
    
    if [[ -n "$pid" ]] && is_process_alive "$pid"; then
        log_info "停止进程: $name (PID: $pid)"
        kill -"$signal" "$pid" 2>/dev/null
        
        # 等待进程退出
        local wait_count=0
        while is_process_alive "$pid" && [[ $wait_count -lt 10 ]]; do
            sleep 0.5
            ((wait_count++))
        done
        
        # 如果还没退出，强制杀死
        if is_process_alive "$pid"; then
            log_warning "进程未响应，强制终止..."
            kill -9 "$pid" 2>/dev/null
        fi
        
        rm -f "${PID_DIR}/${name}.pid"
        return 0
    else
        log_warning "未找到运行中的进程: $name"
        rm -f "${PID_DIR}/${name}.pid"
        return 0
    fi
}

# 限定路径的 pkill（用于回退场景）
# 用法: safe_pkill "pattern"
safe_pkill() {
    local pattern="${1:-}"
    
    if [[ -z "$pattern" ]]; then
        log_error "safe_pkill: 缺少匹配模式"
        return 1
    fi
    
    # 限定到 vps-play 相关路径
    local safe_pattern="$HOME/.vps-play.*${pattern}|$HOME/vps-play.*${pattern}"
    
    log_info "安全终止匹配进程: $safe_pattern"
    pkill -f "$safe_pattern" 2>/dev/null || true
}

# ==================== Bug 5: Swap 管理辅助函数 ====================
# 检查是否为容器环境
is_container_env() {
    # Docker
    if [[ -f /.dockerenv ]]; then
        return 0
    fi
    
    # LXC/OpenVZ
    if grep -qa 'docker\|lxc\|kubepods\|openvz' /proc/1/cgroup 2>/dev/null; then
        return 0
    fi
    
    # systemd-detect-virt
    if command -v systemd-detect-virt &>/dev/null; then
        local virt
        virt=$(systemd-detect-virt 2>/dev/null)
        if [[ "$virt" == "lxc" || "$virt" == "openvz" || "$virt" == "docker" ]]; then
            return 0
        fi
    fi
    
    return 1
}

# 验证 Swap 是否真正生效
# 用法: verify_swap "/swapfile"
verify_swap() {
    local swapfile="${1:-/swapfile}"
    
    # 容器环境告警
    if is_container_env; then
        log_warning "检测到容器环境，Swap 可能不会生效"
    fi
    
    # 等待 swap 生效
    sleep 1
    
    # 检查 swap 是否在使用中
    if swapon --show 2>/dev/null | grep -q "$swapfile"; then
        log_info "Swap 已生效: $swapfile"
        return 0
    fi
    
    # 备用检查方式
    if grep -q "$swapfile" /proc/swaps 2>/dev/null; then
        log_info "Swap 已生效: $swapfile"
        return 0
    fi
    
    # 检查总 swap 是否增加
    local swap_total
    swap_total=$(free | awk '/^Swap:/{print $2}')
    
    if [[ "${swap_total:-0}" -gt 0 ]]; then
        log_info "Swap 总量: ${swap_total}KB"
        return 0
    fi
    
    log_error "Swap 未生效！"
    if is_container_env; then
        log_error "您在容器环境中，Swap 通常不被支持。"
    fi
    return 1
}

# 创建 Swap 并验证
create_swap_safe() {
    local swapfile="${1:-/swapfile}"
    local size_mb="${2:-1024}"
    
    # 容器环境警告
    if is_container_env; then
        log_warning "警告: 容器环境中 Swap 可能不生效"
        read -rp "是否继续? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "取消创建 Swap"
            return 1
        fi
    fi
    
    # 检查是否已存在
    if [[ -f "$swapfile" ]]; then
        log_warning "Swap 文件已存在: $swapfile"
        return 0
    fi
    
    log_info "创建 ${size_mb}MB Swap: $swapfile"
    
    # 创建 swap 文件
    dd if=/dev/zero of="$swapfile" bs=1M count="$size_mb" status=progress 2>/dev/null || {
        log_error "创建 Swap 文件失败"
        return 1
    }
    
    chmod 600 "$swapfile"
    mkswap "$swapfile" >/dev/null || {
        log_error "mkswap 失败"
        rm -f "$swapfile"
        return 1
    }
    
    swapon "$swapfile" || {
        log_error "swapon 失败"
        rm -f "$swapfile"
        return 1
    }
    
    # 验证是否生效
    if ! verify_swap "$swapfile"; then
        log_error "Swap 创建后未生效，正在回滚..."
        swapoff "$swapfile" 2>/dev/null
        rm -f "$swapfile"
        return 1
    fi
    
    # 添加到 fstab
    if ! grep -q "$swapfile" /etc/fstab; then
        echo "$swapfile none swap sw 0 0" >> /etc/fstab
    fi
    
    log_info "Swap 创建成功！"
    return 0
}

# ==================== 导出函数 ====================
export -f log_info log_error log_warning log_debug
export -f safe_rm safe_rm_file
export -f safe_download safe_download_exec
export -f with_port_lock get_random_port_safe
export -f save_pid get_pid is_process_alive safe_kill safe_pkill
export -f is_container_env verify_swap create_swap_safe
