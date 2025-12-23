#!/bin/bash
# 跳板服务器模块 - VPS-play
# 远程SSH管理，让VPS作为跳板连接其他VPS

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/jumper"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"
[ -z "$VPSPLAY_DIR" ] && VPSPLAY_DIR="$HOME/vps-play"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/process_manager.sh" ] && source "$VPSPLAY_DIR/utils/process_manager.sh"

# ==================== 颜色定义 ====================
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Cyan="\033[36m"
Blue="\033[34m"
Reset="\033[0m"
Info="${Green}[信息]${Reset}"
Error="${Red}[错误]${Reset}"
Warning="${Yellow}[警告]${Reset}"
Tip="${Cyan}[提示]${Reset}"

# ==================== 配置 ====================
JUMPER_DIR="$HOME/.vps-play/jumper"
SERVERS_FILE="$JUMPER_DIR/servers.conf"
KEYS_DIR="$JUMPER_DIR/keys"
LOG_FILE="$JUMPER_DIR/jumper.log"
TUNNEL_PIDS_FILE="$JUMPER_DIR/tunnels.pid"

mkdir -p "$JUMPER_DIR" "$KEYS_DIR"

# ==================== 服务器管理 ====================
# 添加服务器
add_server() {
    echo -e ""
    echo -e "${Cyan}========== 添加跳板服务器 ==========${Reset}"
    echo -e ""
    
    read -p "服务器名称 (唯一标识): " server_name
    [ -z "$server_name" ] && { echo -e "${Error} 名称不能为空"; return 1; }
    
    # 检查是否已存在
    if grep -q "^${server_name}|" "$SERVERS_FILE" 2>/dev/null; then
        echo -e "${Warning} 服务器 '$server_name' 已存在"
        read -p "是否覆盖? [y/N]: " overwrite
        [[ ! $overwrite =~ ^[Yy]$ ]] && return 1
        # 删除旧记录
        sed -i "/^${server_name}|/d" "$SERVERS_FILE" 2>/dev/null
    fi
    
    read -p "服务器地址 (IP/域名): " server_host
    [ -z "$server_host" ] && { echo -e "${Error} 地址不能为空"; return 1; }
    
    read -p "SSH 端口 [22]: " server_port
    server_port=${server_port:-22}
    
    read -p "SSH 用户名 [root]: " server_user
    server_user=${server_user:-root}
    
    echo -e ""
    echo -e "${Info} 认证方式:"
    echo -e " ${Green}1.${Reset} 密码认证"
    echo -e " ${Green}2.${Reset} 密钥认证 (推荐)"
    echo -e " ${Green}3.${Reset} 生成并分发新密钥"
    read -p "请选择 [1-3]: " auth_type
    
    local auth_method=""
    local auth_data=""
    
    case "$auth_type" in
        1)
            read -sp "SSH 密码: " server_pass
            echo ""
            auth_method="password"
            auth_data="$server_pass"
            ;;
        2)
            read -p "私钥路径 [$HOME/.ssh/id_rsa]: " key_path
            key_path=${key_path:-$HOME/.ssh/id_rsa}
            if [ ! -f "$key_path" ]; then
                echo -e "${Error} 密钥文件不存在: $key_path"
                return 1
            fi
            # 复制密钥到管理目录
            cp "$key_path" "$KEYS_DIR/${server_name}.key"
            chmod 600 "$KEYS_DIR/${server_name}.key"
            auth_method="key"
            auth_data="$KEYS_DIR/${server_name}.key"
            ;;
        3)
            generate_and_distribute_key "$server_name" "$server_host" "$server_port" "$server_user"
            auth_method="key"
            auth_data="$KEYS_DIR/${server_name}.key"
            ;;
        *)
            echo -e "${Error} 无效选择"
            return 1
            ;;
    esac
    
    # 保存配置 格式: name|host|port|user|auth_method|auth_data|description
    read -p "备注说明 (可留空): " description
    echo "${server_name}|${server_host}|${server_port}|${server_user}|${auth_method}|${auth_data}|${description}" >> "$SERVERS_FILE"
    
    echo -e ""
    echo -e "${Info} 服务器已添加: ${Green}${server_name}${Reset}"
    
    # 测试连接
    read -p "是否测试连接? [Y/n]: " test_conn
    [[ ! $test_conn =~ ^[Nn]$ ]] && test_connection "$server_name"
}

# 生成并分发密钥
generate_and_distribute_key() {
    local name=$1
    local host=$2
    local port=$3
    local user=$4
    
    local key_file="$KEYS_DIR/${name}.key"
    
    echo -e "${Info} 生成 SSH 密钥对..."
    ssh-keygen -t ed25519 -f "$key_file" -N "" -q
    chmod 600 "$key_file"
    
    echo -e "${Info} 分发公钥到目标服务器..."
    echo -e "${Tip} 需要输入目标服务器密码"
    
    # 使用 ssh-copy-id 分发
    if command -v ssh-copy-id &>/dev/null; then
        ssh-copy-id -i "${key_file}.pub" -p "$port" "${user}@${host}"
    else
        # 手动分发
        read -sp "目标服务器密码: " temp_pass
        echo ""
        local pub_key=$(cat "${key_file}.pub")
        
        if command -v sshpass &>/dev/null; then
            sshpass -p "$temp_pass" ssh -p "$port" "${user}@${host}" \
                "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub_key' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        else
            echo -e "${Tip} 请手动将以下公钥添加到目标服务器的 ~/.ssh/authorized_keys:"
            echo -e "${Yellow}${pub_key}${Reset}"
        fi
    fi
    
    echo -e "${Info} 密钥已生成并分发"
}

# 列出服务器
list_servers() {
    if [ ! -f "$SERVERS_FILE" ] || [ ! -s "$SERVERS_FILE" ]; then
        echo -e "${Warning} 暂无已配置的服务器"
        return 1
    fi
    
    echo -e ""
    echo -e "${Green}==================== 已配置的服务器 ====================${Reset}"
    echo -e ""
    printf " %-4s %-15s %-25s %-10s %-10s %s\n" "序号" "名称" "地址" "端口" "用户" "备注"
    echo -e "${Green}-----------------------------------------------------------${Reset}"
    
    local i=1
    while IFS='|' read -r name host port user auth_method auth_data desc; do
        printf " %-4s %-15s %-25s %-10s %-10s %s\n" "$i" "$name" "$host" "$port" "$user" "$desc"
        ((i++))
    done < "$SERVERS_FILE"
    
    echo -e "${Green}=========================================================${Reset}"
}

# 删除服务器
delete_server() {
    list_servers || return 1
    echo -e ""
    read -p "输入要删除的服务器名称: " server_name
    
    if grep -q "^${server_name}|" "$SERVERS_FILE"; then
        sed -i "/^${server_name}|/d" "$SERVERS_FILE"
        rm -f "$KEYS_DIR/${server_name}.key" "$KEYS_DIR/${server_name}.key.pub"
        echo -e "${Info} 服务器 '$server_name' 已删除"
    else
        echo -e "${Error} 服务器 '$server_name' 不存在"
    fi
}

# 获取服务器信息
get_server_info() {
    local name=$1
    local info=$(grep "^${name}|" "$SERVERS_FILE" 2>/dev/null)
    echo "$info"
}

# ==================== SSH 连接 ====================
# 连接到服务器
connect_server() {
    list_servers || return 1
    echo -e ""
    read -p "输入要连接的服务器名称: " server_name
    
    local info=$(get_server_info "$server_name")
    if [ -z "$info" ]; then
        echo -e "${Error} 服务器 '$server_name' 不存在"
        return 1
    fi
    
    local host=$(echo "$info" | cut -d'|' -f2)
    local port=$(echo "$info" | cut -d'|' -f3)
    local user=$(echo "$info" | cut -d'|' -f4)
    local auth_method=$(echo "$info" | cut -d'|' -f5)
    local auth_data=$(echo "$info" | cut -d'|' -f6)
    
    echo -e "${Info} 连接到 ${Green}${user}@${host}:${port}${Reset}..."
    
    case "$auth_method" in
        password)
            if command -v sshpass &>/dev/null; then
                sshpass -p "$auth_data" ssh -o StrictHostKeyChecking=no -p "$port" "${user}@${host}"
            else
                echo -e "${Warning} sshpass 未安装，请手动输入密码"
                ssh -o StrictHostKeyChecking=no -p "$port" "${user}@${host}"
            fi
            ;;
        key)
            ssh -o StrictHostKeyChecking=no -i "$auth_data" -p "$port" "${user}@${host}"
            ;;
    esac
}

# 测试连接
test_connection() {
    local server_name=$1
    
    local info=$(get_server_info "$server_name")
    if [ -z "$info" ]; then
        echo -e "${Error} 服务器 '$server_name' 不存在"
        return 1
    fi
    
    local host=$(echo "$info" | cut -d'|' -f2)
    local port=$(echo "$info" | cut -d'|' -f3)
    local user=$(echo "$info" | cut -d'|' -f4)
    local auth_method=$(echo "$info" | cut -d'|' -f5)
    local auth_data=$(echo "$info" | cut -d'|' -f6)
    
    echo -e "${Info} 测试连接 ${server_name} (${user}@${host}:${port})..."
    
    case "$auth_method" in
        password)
            if command -v sshpass &>/dev/null; then
                local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
                local result=$(sshpass -p "$auth_data" ssh $ssh_opts -p "$port" "${user}@${host}" "echo ok" 2>&1)
                if [ "$result" = "ok" ]; then
                    echo -e "${Info} ${Green}连接成功${Reset}"
                    return 0
                else
                    echo -e "${Error} ${Red}连接失败${Reset}: $result"
                    return 1
                fi
            else
                echo -e "${Warning} sshpass 未安装，将使用交互式测试"
                echo -e "${Tip} 请在提示时输入密码..."
                ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$port" "${user}@${host}" "echo '连接成功!' && exit"
                return $?
            fi
            ;;
        key)
            local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
            local result=$(ssh $ssh_opts -i "$auth_data" -p "$port" "${user}@${host}" "echo ok" 2>&1)
            if [ "$result" = "ok" ]; then
                echo -e "${Info} ${Green}连接成功${Reset}"
                return 0
            else
                echo -e "${Error} ${Red}连接失败${Reset}: $result"
                return 1
            fi
            ;;
    esac
}

# ==================== SSH 隧道 ====================
# 创建本地端口转发 (访问远程服务)
create_local_forward() {
    echo -e ""
    echo -e "${Cyan}========== 本地端口转发 ==========${Reset}"
    echo -e "${Tip} 将远程服务映射到本地端口"
    echo -e ""
    
    list_servers || return 1
    echo -e ""
    read -p "通过哪台服务器转发: " server_name
    
    local info=$(get_server_info "$server_name")
    if [ -z "$info" ]; then
        echo -e "${Error} 服务器 '$server_name' 不存在"
        return 1
    fi
    
    read -p "本地监听端口: " local_port
    read -p "远程目标地址 (默认 localhost): " remote_host
    remote_host=${remote_host:-localhost}
    read -p "远程目标端口: " remote_port
    
    local host=$(echo "$info" | cut -d'|' -f2)
    local port=$(echo "$info" | cut -d'|' -f3)
    local user=$(echo "$info" | cut -d'|' -f4)
    local auth_method=$(echo "$info" | cut -d'|' -f5)
    local auth_data=$(echo "$info" | cut -d'|' -f6)
    
    local ssh_opts="-o StrictHostKeyChecking=no -N -f"
    local tunnel_cmd=""
    
    case "$auth_method" in
        password)
            if command -v sshpass &>/dev/null; then
                tunnel_cmd="sshpass -p '$auth_data' ssh $ssh_opts -L ${local_port}:${remote_host}:${remote_port} -p $port ${user}@${host}"
            else
                echo -e "${Error} 密码认证需要安装 sshpass"
                return 1
            fi
            ;;
        key)
            tunnel_cmd="ssh $ssh_opts -i '$auth_data' -L ${local_port}:${remote_host}:${remote_port} -p $port ${user}@${host}"
            ;;
    esac
    
    echo -e "${Info} 创建隧道..."
    eval $tunnel_cmd
    
    if [ $? -eq 0 ]; then
        echo -e "${Info} ${Green}本地端口转发已建立${Reset}"
        echo -e " 本地访问: ${Cyan}localhost:${local_port}${Reset}"
        echo -e " 实际访问: ${Cyan}${remote_host}:${remote_port}${Reset} (通过 ${server_name})"
        
        # 记录隧道
        echo "local|${server_name}|${local_port}|${remote_host}|${remote_port}" >> "$TUNNEL_PIDS_FILE"
    else
        echo -e "${Error} 隧道创建失败"
    fi
}

# 创建远程端口转发 (反向隧道)
create_remote_forward() {
    echo -e ""
    echo -e "${Cyan}========== 远程端口转发 (反向隧道) ==========${Reset}"
    echo -e "${Tip} 将本地服务暴露到远程服务器"
    echo -e ""
    
    list_servers || return 1
    echo -e ""
    read -p "转发到哪台服务器: " server_name
    
    local info=$(get_server_info "$server_name")
    if [ -z "$info" ]; then
        echo -e "${Error} 服务器 '$server_name' 不存在"
        return 1
    fi
    
    read -p "远程监听端口: " remote_listen_port
    read -p "本地目标地址 (默认 localhost): " local_host
    local_host=${local_host:-localhost}
    read -p "本地目标端口: " local_target_port
    
    local host=$(echo "$info" | cut -d'|' -f2)
    local port=$(echo "$info" | cut -d'|' -f3)
    local user=$(echo "$info" | cut -d'|' -f4)
    local auth_method=$(echo "$info" | cut -d'|' -f5)
    local auth_data=$(echo "$info" | cut -d'|' -f6)
    
    local ssh_opts="-o StrictHostKeyChecking=no -o ServerAliveInterval=60 -N -f"
    local tunnel_cmd=""
    
    case "$auth_method" in
        password)
            if command -v sshpass &>/dev/null; then
                tunnel_cmd="sshpass -p '$auth_data' ssh $ssh_opts -R ${remote_listen_port}:${local_host}:${local_target_port} -p $port ${user}@${host}"
            else
                echo -e "${Error} 密码认证需要安装 sshpass"
                return 1
            fi
            ;;
        key)
            tunnel_cmd="ssh $ssh_opts -i '$auth_data' -R ${remote_listen_port}:${local_host}:${local_target_port} -p $port ${user}@${host}"
            ;;
    esac
    
    echo -e "${Info} 创建反向隧道..."
    eval $tunnel_cmd
    
    if [ $? -eq 0 ]; then
        echo -e "${Info} ${Green}远程端口转发已建立${Reset}"
        echo -e " 远程访问: ${Cyan}${host}:${remote_listen_port}${Reset}"
        echo -e " 实际访问: ${Cyan}${local_host}:${local_target_port}${Reset} (本地)"
        
        # 记录隧道
        echo "remote|${server_name}|${remote_listen_port}|${local_host}|${local_target_port}" >> "$TUNNEL_PIDS_FILE"
    else
        echo -e "${Error} 反向隧道创建失败"
    fi
}

# 动态端口转发 (SOCKS 代理)
create_socks_proxy() {
    echo -e ""
    echo -e "${Cyan}========== SOCKS5 代理 ==========${Reset}"
    echo -e "${Tip} 创建一个 SOCKS5 代理，流量通过跳板服务器"
    echo -e ""
    
    list_servers || return 1
    echo -e ""
    read -p "通过哪台服务器代理: " server_name
    
    local info=$(get_server_info "$server_name")
    if [ -z "$info" ]; then
        echo -e "${Error} 服务器 '$server_name' 不存在"
        return 1
    fi
    
    read -p "本地 SOCKS 端口 [1080]: " socks_port
    socks_port=${socks_port:-1080}
    
    local host=$(echo "$info" | cut -d'|' -f2)
    local port=$(echo "$info" | cut -d'|' -f3)
    local user=$(echo "$info" | cut -d'|' -f4)
    local auth_method=$(echo "$info" | cut -d'|' -f5)
    local auth_data=$(echo "$info" | cut -d'|' -f6)
    
    local ssh_opts="-o StrictHostKeyChecking=no -o ServerAliveInterval=60 -N -f"
    local tunnel_cmd=""
    
    case "$auth_method" in
        password)
            if command -v sshpass &>/dev/null; then
                tunnel_cmd="sshpass -p '$auth_data' ssh $ssh_opts -D ${socks_port} -p $port ${user}@${host}"
            else
                echo -e "${Error} 密码认证需要安装 sshpass"
                return 1
            fi
            ;;
        key)
            tunnel_cmd="ssh $ssh_opts -i '$auth_data' -D ${socks_port} -p $port ${user}@${host}"
            ;;
    esac
    
    echo -e "${Info} 创建 SOCKS5 代理..."
    eval $tunnel_cmd
    
    if [ $? -eq 0 ]; then
        echo -e "${Info} ${Green}SOCKS5 代理已建立${Reset}"
        echo -e " 代理地址: ${Cyan}socks5://127.0.0.1:${socks_port}${Reset}"
        echo -e " 流量经由: ${Cyan}${server_name}${Reset}"
        
        # 记录隧道
        echo "socks|${server_name}|${socks_port}||" >> "$TUNNEL_PIDS_FILE"
    else
        echo -e "${Error} 代理创建失败"
    fi
}

# 列出活动隧道
list_tunnels() {
    echo -e ""
    echo -e "${Green}==================== 活动的 SSH 隧道 ====================${Reset}"
    
    # 查找 SSH 隧道进程
    local tunnels=$(ps aux 2>/dev/null | grep -E "ssh.*-[LD]" | grep -v grep)
    
    if [ -z "$tunnels" ]; then
        echo -e "${Warning} 暂无活动的隧道"
        return 1
    fi
    
    echo -e ""
    echo "$tunnels" | while read line; do
        local pid=$(echo "$line" | awk '{print $2}')
        local cmd=$(echo "$line" | awk '{$1=$2=$3=$4=$5=$6=$7=$8=$9=$10=""; print $0}' | sed 's/^ *//')
        echo -e " PID: ${Green}${pid}${Reset}"
        echo -e " 命令: ${Cyan}${cmd}${Reset}"
        echo -e ""
    done
    echo -e "${Green}=========================================================${Reset}"
}

# 关闭隧道
close_tunnel() {
    list_tunnels || return 1
    echo -e ""
    read -p "输入要关闭的隧道 PID: " pid
    
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${Info} 隧道已关闭"
        else
            echo -e "${Error} 关闭失败，可能需要 root 权限"
        fi
    fi
}

# ==================== 批量执行 ====================
# 在所有服务器上执行命令
batch_execute() {
    echo -e ""
    echo -e "${Cyan}========== 批量执行命令 ==========${Reset}"
    echo -e "${Tip} 在所有已配置的服务器上执行相同命令"
    echo -e ""
    
    if [ ! -f "$SERVERS_FILE" ] || [ ! -s "$SERVERS_FILE" ]; then
        echo -e "${Warning} 暂无已配置的服务器"
        return 1
    fi
    
    read -p "输入要执行的命令: " cmd
    [ -z "$cmd" ] && { echo -e "${Error} 命令不能为空"; return 1; }
    
    echo -e ""
    echo -e "${Info} 开始批量执行..."
    echo -e ""
    
    while IFS='|' read -r name host port user auth_method auth_data desc; do
        echo -e "${Cyan}>>> ${name} (${host})${Reset}"
        
        local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
        local result=""
        
        case "$auth_method" in
            password)
                if command -v sshpass &>/dev/null; then
                    result=$(sshpass -p "$auth_data" ssh $ssh_opts -p "$port" "${user}@${host}" "$cmd" 2>&1)
                else
                    result="[跳过: 需要 sshpass]"
                fi
                ;;
            key)
                result=$(ssh $ssh_opts -i "$auth_data" -p "$port" "${user}@${host}" "$cmd" 2>&1)
                ;;
        esac
        
        echo "$result"
        echo -e ""
    done < "$SERVERS_FILE"
    
    echo -e "${Info} 批量执行完成"
}

# 批量上传文件
batch_upload() {
    echo -e ""
    echo -e "${Cyan}========== 批量上传文件 ==========${Reset}"
    echo -e ""
    
    if [ ! -f "$SERVERS_FILE" ] || [ ! -s "$SERVERS_FILE" ]; then
        echo -e "${Warning} 暂无已配置的服务器"
        return 1
    fi
    
    read -p "本地文件路径: " local_file
    [ ! -f "$local_file" ] && { echo -e "${Error} 文件不存在"; return 1; }
    
    read -p "远程目标路径 [/tmp/]: " remote_path
    remote_path=${remote_path:-/tmp/}
    
    echo -e ""
    echo -e "${Info} 开始批量上传..."
    echo -e ""
    
    while IFS='|' read -r name host port user auth_method auth_data desc; do
        echo -e "${Cyan}>>> ${name} (${host})${Reset}"
        
        local scp_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
        
        case "$auth_method" in
            password)
                if command -v sshpass &>/dev/null; then
                    sshpass -p "$auth_data" scp $scp_opts -P "$port" "$local_file" "${user}@${host}:${remote_path}"
                else
                    echo -e "[跳过: 需要 sshpass]"
                    continue
                fi
                ;;
            key)
                scp $scp_opts -i "$auth_data" -P "$port" "$local_file" "${user}@${host}:${remote_path}"
                ;;
        esac
        
        if [ $? -eq 0 ]; then
            echo -e "${Green}上传成功${Reset}"
        else
            echo -e "${Red}上传失败${Reset}"
        fi
    done < "$SERVERS_FILE"
    
    echo -e ""
    echo -e "${Info} 批量上传完成"
}

# ==================== 跳板链 ====================
# 多跳 SSH (A -> B -> C)
chain_connect() {
    echo -e ""
    echo -e "${Cyan}========== SSH 跳板链 ==========${Reset}"
    echo -e "${Tip} 通过多台服务器链式连接"
    echo -e ""
    
    list_servers || return 1
    
    echo -e ""
    echo -e "请输入跳板链 (用逗号分隔，如: server1,server2,target)"
    read -p "跳板链: " chain
    
    [ -z "$chain" ] && { echo -e "${Error} 跳板链不能为空"; return 1; }
    
    IFS=',' read -ra servers <<< "$chain"
    local proxy_cmd=""
    
    for ((i=0; i<${#servers[@]}-1; i++)); do
        local server_name=$(echo "${servers[$i]}" | tr -d ' ')
        local info=$(get_server_info "$server_name")
        
        if [ -z "$info" ]; then
            echo -e "${Error} 服务器 '$server_name' 不存在"
            return 1
        fi
        
        local host=$(echo "$info" | cut -d'|' -f2)
        local port=$(echo "$info" | cut -d'|' -f3)
        local user=$(echo "$info" | cut -d'|' -f4)
        local auth_method=$(echo "$info" | cut -d'|' -f5)
        local auth_data=$(echo "$info" | cut -d'|' -f6)
        
        if [ -n "$proxy_cmd" ]; then
            proxy_cmd="${proxy_cmd} -> "
        fi
        
        case "$auth_method" in
            key)
                proxy_cmd="${proxy_cmd}${user}@${host}:${port} (key)"
                ;;
            password)
                proxy_cmd="${proxy_cmd}${user}@${host}:${port} (password)"
                ;;
        esac
    done
    
    # 最终目标
    local target_name=$(echo "${servers[-1]}" | tr -d ' ')
    local target_info=$(get_server_info "$target_name")
    
    if [ -z "$target_info" ]; then
        echo -e "${Error} 目标服务器 '$target_name' 不存在"
        return 1
    fi
    
    local target_host=$(echo "$target_info" | cut -d'|' -f2)
    local target_port=$(echo "$target_info" | cut -d'|' -f3)
    local target_user=$(echo "$target_info" | cut -d'|' -f4)
    
    echo -e ""
    echo -e "${Info} 连接路径: ${Cyan}${proxy_cmd} -> ${target_user}@${target_host}:${target_port}${Reset}"
    echo -e ""
    
    # 构建 ProxyJump 命令
    local proxy_jump=""
    for ((i=0; i<${#servers[@]}-1; i++)); do
        local server_name=$(echo "${servers[$i]}" | tr -d ' ')
        local info=$(get_server_info "$server_name")
        local host=$(echo "$info" | cut -d'|' -f2)
        local port=$(echo "$info" | cut -d'|' -f3)
        local user=$(echo "$info" | cut -d'|' -f4)
        
        if [ -n "$proxy_jump" ]; then
            proxy_jump="${proxy_jump},${user}@${host}:${port}"
        else
            proxy_jump="${user}@${host}:${port}"
        fi
    done
    
    echo -e "${Info} 正在建立连接..."
    ssh -o StrictHostKeyChecking=no -J "$proxy_jump" -p "$target_port" "${target_user}@${target_host}"
}

# ==================== 主菜单 ====================
show_jumper_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
      ╦╦ ╦╔╦╗╔═╗╔═╗╦═╗
      ║║ ║║║║╠═╝║╣ ╠╦╝
    ╚╝╚═╝╩ ╩╩  ╚═╝╩╚═
    SSH 跳板服务器
EOF
        echo -e "${Reset}"
        
        echo -e "${Green}==================== 跳板服务器管理 ====================${Reset}"
        echo -e " ${Yellow}服务器管理${Reset}"
        echo -e " ${Green}1.${Reset}  添加服务器"
        echo -e " ${Green}2.${Reset}  列出服务器"
        echo -e " ${Green}3.${Reset}  删除服务器"
        echo -e " ${Green}4.${Reset}  测试连接"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}SSH 连接${Reset}"
        echo -e " ${Green}5.${Reset}  连接到服务器"
        echo -e " ${Green}6.${Reset}  SSH 跳板链 (多跳)"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}SSH 隧道${Reset}"
        echo -e " ${Green}7.${Reset}  本地端口转发"
        echo -e " ${Green}8.${Reset}  远程端口转发 (反向隧道)"
        echo -e " ${Green}9.${Reset}  SOCKS5 代理"
        echo -e " ${Green}10.${Reset} 查看活动隧道"
        echo -e " ${Green}11.${Reset} 关闭隧道"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}批量操作${Reset}"
        echo -e " ${Green}12.${Reset} 批量执行命令"
        echo -e " ${Green}13.${Reset} 批量上传文件"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回主菜单"
        echo -e "${Green}========================================================${Reset}"
        
        read -p " 请选择 [0-13]: " choice
        
        case "$choice" in
            1) add_server ;;
            2) list_servers ;;
            3) delete_server ;;
            4)
                list_servers && {
                    echo ""
                    read -p "输入要测试的服务器名称: " sn
                    test_connection "$sn"
                }
                ;;
            5) connect_server ;;
            6) chain_connect ;;
            7) create_local_forward ;;
            8) create_remote_forward ;;
            9) create_socks_proxy ;;
            10) list_tunnels ;;
            11) close_tunnel ;;
            12) batch_execute ;;
            13) batch_upload ;;
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
    show_jumper_menu
fi
