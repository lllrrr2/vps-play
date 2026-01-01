#!/bin/bash
# VPS-play 主脚本
# 支持: 普通VPS、NAT VPS、FreeBSD、Serv00/Hostuno
# 功能: 节点管理、保活、域名、SSL、监控等
#
# 使用方法:
#   一键运行: bash <(curl -Ls https://raw.githubusercontent.com/hxzlplp7/vps-play/main/start.sh)
#             (总是重新安装最新版本并运行)
#   仅运行:   bash <(curl -Ls ...) --run  或  vps-play
#   仅安装:   bash <(curl -Ls ...) --install
#   卸载:     bash <(curl -Ls ...) --uninstall
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

version="1.2.1"

# ==================== 参数解析 ====================
ACTION=""
for arg in "$@"; do
    case "$arg" in
        --install|-i)
            ACTION="install"
            ;;
        --run|-r)
            ACTION="run"
            ;;
        --uninstall|-u)
            ACTION="uninstall"
            ;;
        --help|-h)
            echo "VPS-play v${version} - 通用 VPS 管理工具"
            echo ""
            echo "使用方法:"
            echo "  bash <(curl -Ls URL)            # 自动安装并运行"
            echo "  bash <(curl -Ls URL) --install  # 仅安装"
            echo "  bash <(curl -Ls URL) --run      # 仅运行（需已安装）"
            echo "  bash <(curl -Ls URL) --uninstall # 卸载"
            echo ""
            echo "选项:"
            echo "  -i, --install    仅安装，不运行"
            echo "  -r, --run        仅运行，不安装"
            echo "  -u, --uninstall  卸载脚本"
            echo "  -h, --help       显示帮助"
            exit 0
            ;;
    esac
done

# ==================== 在线安装功能 ====================
PROJECT_NAME="vps-play"
INSTALL_DIR="$HOME/$PROJECT_NAME"
REPO_RAW="https://raw.githubusercontent.com/hxzlplp7/vps-play/main"

# 检查是否已安装
is_installed() {
    [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/start.sh" ] && [ -d "$INSTALL_DIR/modules" ]
}

# 在线安装函数
online_install() {
    local _Green="\033[32m"
    local _Red="\033[31m"
    local _Yellow="\033[33m"
    local _Cyan="\033[36m"
    local _Reset="\033[0m"
    
    echo -e "${_Cyan}"
    cat << "EOF"
    ╦  ╦╔═╗╔═╗   ╔═╗╦  ╔═╗╦ ╦
    ╚╗╔╝╠═╝╚═╗───╠═╝║  ╠═╣╚╦╝
     ╚╝ ╩  ╚═╝   ╩  ╩═╝╩ ╩ ╩ 
    通用 VPS 管理工具 - 安装程序
EOF
    echo -e "${_Reset}"
    
    echo -e "${_Green}==================== 开始安装 ====================${_Reset}"
    
    # 检查 curl 或 wget
    if command -v curl &>/dev/null; then
        DOWNLOAD_CMD="curl -sL"
    elif command -v wget &>/dev/null; then
        DOWNLOAD_CMD="wget -qO-"
    else
        echo -e "${_Red}[错误]${_Reset} 需要 curl 或 wget"
        exit 1
    fi
    
    # 清理旧安装（避免目录结构错误）
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${_Yellow}[信息]${_Reset} 清理旧安装..."
        # 只删除脚本文件，保留配置
        rm -rf "$INSTALL_DIR/start.sh" 2>/dev/null
        rm -rf "$INSTALL_DIR/install.sh" 2>/dev/null
        rm -rf "$INSTALL_DIR/uninstall.sh" 2>/dev/null
        rm -rf "$INSTALL_DIR/utils" 2>/dev/null
        rm -rf "$INSTALL_DIR/modules" 2>/dev/null
        rm -rf "$INSTALL_DIR/keepalive" 2>/dev/null
    fi
    
    # 创建目录结构
    mkdir -p "$INSTALL_DIR"/{utils,modules/{gost,xui,singbox,hysteria,tuic,frpc,frps,cloudflared,nezha,warp,docker,benchmark,argo,argosbx,jumper,stats},keepalive,config}
    
    # 下载文件函数
    download_file() {
        local path=$1
        local url="${REPO_RAW}/${path}"
        local dest="${INSTALL_DIR}/${path}"
        
        mkdir -p "$(dirname "$dest")"
        
        if [ "$DOWNLOAD_CMD" = "curl -sL" ]; then
            curl -sL "$url" -o "$dest"
        else
            wget -q "$url" -O "$dest"
        fi
        
        if [ $? -eq 0 ] && [ -s "$dest" ]; then
            chmod +x "$dest" 2>/dev/null || true
            echo -e "  ✓ $path"
        else
            echo -e "  ✗ $path (下载失败)"
        fi
    }
    
    echo -e "${_Green}[信息]${_Reset} 下载核心文件..."
    download_file "start.sh"
    
    echo -e "${_Green}[信息]${_Reset} 下载工具库..."
    download_file "utils/env_detect.sh"
    download_file "utils/port_manager.sh"
    download_file "utils/process_manager.sh"
    download_file "utils/network.sh"
    download_file "utils/system_clean.sh"
    
    echo -e "${_Green}[信息]${_Reset} 下载功能模块..."
    download_file "modules/singbox/manager.sh"
    download_file "modules/hysteria/manager.sh"
    download_file "modules/tuic/manager.sh"
    download_file "modules/nodes/manager.sh"
    download_file "modules/argo/manager.sh"
    download_file "modules/gost/manager.sh"
    download_file "modules/xui/manager.sh"
    download_file "modules/frpc/manager.sh"
    download_file "modules/frps/manager.sh"
    download_file "modules/cloudflared/manager.sh"
    download_file "modules/jumper/manager.sh"
    download_file "modules/nezha/manager.sh"
    download_file "modules/warp/manager.sh"
    download_file "modules/docker/manager.sh"
    download_file "modules/benchmark/manager.sh"
    download_file "modules/stats/manager.sh"
    
    echo -e "${_Green}[信息]${_Reset} 下载保活模块..."
    download_file "keepalive/manager.sh"
    
    # 创建快捷命令
    echo -e "${_Green}[信息]${_Reset} 创建快捷命令..."
    mkdir -p "$HOME/bin"
    
    cat > "$HOME/bin/vps-play" << SHORTCUT_EOF
#!/bin/bash
exec bash "$INSTALL_DIR/start.sh" "\$@"
SHORTCUT_EOF
    
    chmod +x "$HOME/bin/vps-play"
    
    # 添加到 PATH
    for profile_file in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$profile_file" ]; then
            if ! grep -q 'HOME/bin' "$profile_file" 2>/dev/null; then
                echo 'export PATH="$HOME/bin:$PATH"' >> "$profile_file"
            fi
        fi
    done
    
    export PATH="$HOME/bin:$PATH"
    
    echo -e ""
    echo -e "${_Green}==================== 安装完成 ====================${_Reset}"
    echo -e ""
}

# 在线卸载函数
online_uninstall() {
    local _Green="\033[32m"
    local _Red="\033[31m"
    local _Yellow="\033[33m"
    local _Reset="\033[0m"
    
    echo -e "${_Yellow}[警告]${_Reset} 确定要卸载 VPS-play 吗? [y/N]"
    read -p "" confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${_Green}[信息]${_Reset} 已取消"
        exit 0
    fi
    
    # 下载并执行卸载脚本
    if command -v curl &>/dev/null; then
        curl -sL "${REPO_RAW}/uninstall.sh" | bash
    elif command -v wget &>/dev/null; then
        wget -qO- "${REPO_RAW}/uninstall.sh" | bash
    fi
    exit 0
}

# ==================== 根据参数执行 ====================
# 如果是卸载
if [ "$ACTION" = "uninstall" ]; then
    online_uninstall
fi

# 如果指定 --run，只运行不安装
if [ "$ACTION" = "run" ]; then
    if ! is_installed; then
        echo -e "\033[31m[错误]\033[0m VPS-play 未安装"
        echo -e "\033[36m[提示]\033[0m 请先运行: bash <(curl -Ls ${REPO_RAW}/start.sh)"
        exit 1
    fi
    # 跳过安装，直接运行
else
    # 默认行为：总是重新安装（覆盖旧版本）
    online_install
    
    # 如果只是安装模式，不继续运行
    if [ "$ACTION" = "install" ]; then
        echo -e "\033[33m快捷命令:\033[0m vps-play"
        echo -e "\033[33m或运行:\033[0m bash ~/vps-play/start.sh"
        exit 0
    fi
fi

# ==================== 初始化 ====================
# 获取脚本目录 - 兼容 Linux 和 FreeBSD
SCRIPT_DIR=""

# 方法1：直接从 BASH_SOURCE 获取（最可靠）
if [ -n "${BASH_SOURCE[0]}" ] && [ "${BASH_SOURCE[0]}" != "bash" ]; then
    _dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
    if [ -d "$_dir/modules" ] && [ -d "$_dir/utils" ]; then
        SCRIPT_DIR="$_dir"
    fi
fi

# 方法2：从 $0 获取
if [ -z "$SCRIPT_DIR" ] && [ -n "$0" ] && [ "$0" != "bash" ] && [ "$0" != "-bash" ]; then
    _dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
    if [ -d "$_dir/modules" ] && [ -d "$_dir/utils" ]; then
        SCRIPT_DIR="$_dir"
    fi
fi

# 方法3：常见安装路径
if [ -z "$SCRIPT_DIR" ]; then
    for _path in "$HOME/vps-play" "/root/vps-play" "/usr/local/vps-play"; do
        if [ -d "$_path/modules" ] && [ -d "$_path/utils" ]; then
            SCRIPT_DIR="$_path"
            break
        fi
    done
fi

# 方法4：最终回退
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR="$HOME/vps-play"

# 健全性检查: 防止路径误判为子目录
if [[ "$SCRIPT_DIR" == */utils ]] || [[ "$SCRIPT_DIR" == */modules ]]; then
    SCRIPT_DIR=$(dirname "$SCRIPT_DIR")
fi

# 进入工作目录，确保相对路径正确
cd "$SCRIPT_DIR" 2>/dev/null

WORK_DIR="$HOME/.vps-play"

# 加载工具库（静默失败）
[ -f "$SCRIPT_DIR/utils/env_detect.sh" ] && source "$SCRIPT_DIR/utils/env_detect.sh"
[ -f "$SCRIPT_DIR/utils/port_manager.sh" ] && source "$SCRIPT_DIR/utils/port_manager.sh"
[ -f "$SCRIPT_DIR/utils/process_manager.sh" ] && source "$SCRIPT_DIR/utils/process_manager.sh"
[ -f "$SCRIPT_DIR/utils/network.sh" ] && source "$SCRIPT_DIR/utils/network.sh"
[ -f "$SCRIPT_DIR/utils/system_clean.sh" ] && source "$SCRIPT_DIR/utils/system_clean.sh"

# 自动检测环境
if type detect_environment &>/dev/null; then
    ENV_CONF="$HOME/.vps-play/env.conf"
    if [ -f "$ENV_CONF" ]; then
        source "$ENV_CONF"
    else
        # 首次检测，不静默以便调试（或者重定向到日志）
        detect_environment >/dev/null 2>&1
        if type save_env_info &>/dev/null; then
            save_env_info "$ENV_CONF" 2>/dev/null
        fi
    fi
    
    # 如果仍然未设置（例如配置文件为空或检测失败），尝试再次检测
    if [ -z "$ENV_TYPE" ]; then
        detect_environment >/dev/null 2>&1
    fi
fi

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

# ==================== 初始化环境 ====================
init_environment() {
    mkdir -p "$WORK_DIR"/{modules,config,logs,keepalive,processes}
    
    # 检测或加载环境信息
    if [ -f "$WORK_DIR/env.conf" ]; then
        source "$WORK_DIR/env.conf"
    fi
    
    # 如果环境变量为空，重新检测
    if [ -z "$ENV_TYPE" ] || [ -z "$OS_DISTRO" ]; then
        # 静默检测
        detect_os_silent
        detect_arch_silent
        detect_virt_silent
        detect_permissions_silent
        detect_services_silent
        detect_network_silent
        determine_env_type_silent
        
        # 保存配置
        save_env_info "$WORK_DIR/env.conf" 2>/dev/null
    fi
}

# 静默版本的检测函数
detect_os_silent() {
    local os=$(uname -s)
    case "$os" in
        Linux)
            OS_TYPE="linux"
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                OS_DISTRO=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
            elif [ -f /etc/redhat-release ]; then
                OS_DISTRO="centos"
            elif [ -f /etc/debian_version ]; then
                OS_DISTRO="debian"
            else
                OS_DISTRO="linux"
            fi
            ;;
        FreeBSD)
            OS_TYPE="freebsd"
            OS_DISTRO="freebsd"
            ;;
        *)
            OS_TYPE="unknown"
            OS_DISTRO="unknown"
            ;;
    esac
}

detect_arch_silent() {
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        i386|i686) ARCH="386" ;;
        *) ARCH="unknown" ;;
    esac
}

detect_permissions_silent() {
    if [ "$(id -u)" = "0" ]; then
        HAS_ROOT=true
    else
        HAS_ROOT=false
    fi
}

detect_services_silent() {
    if command -v systemctl &>/dev/null && systemctl &>/dev/null 2>&1; then
        HAS_SYSTEMD=true
    else
        HAS_SYSTEMD=false
    fi
    
    if command -v devil &>/dev/null; then
        HAS_DEVIL=true
    else
        HAS_DEVIL=false
    fi
}

detect_network_silent() {
    PUBLIC_IP=$(curl -s4m5 ip.sb 2>/dev/null || curl -s4m5 ifconfig.me 2>/dev/null || echo "unknown")
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
    
    if [ "$PUBLIC_IP" != "$LOCAL_IP" ] && [ "$PUBLIC_IP" != "unknown" ] && [ "$LOCAL_IP" != "unknown" ]; then
        IS_NAT=true
    else
        IS_NAT=false
    fi
}

determine_env_type_silent() {
    if [ "$HAS_DEVIL" = true ]; then
        ENV_TYPE="serv00"
    elif [ "$OS_TYPE" = "freebsd" ]; then
        ENV_TYPE="freebsd"
    elif [ "$IS_NAT" = true ]; then
        ENV_TYPE="natvps"
    elif [ "$HAS_ROOT" = true ]; then
        ENV_TYPE="vps"
    else
        ENV_TYPE="limited"
    fi
}

detect_virt_silent() {
    IS_CONTAINER=false
    VIRT_TYPE="none"
    
    if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        VIRT_TYPE="docker"
        IS_CONTAINER=true
    elif [ -f /run/.containerenv ]; then
        VIRT_TYPE="podman"
        IS_CONTAINER=true
    elif command -v systemd-detect-virt &>/dev/null; then
        VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
    fi
}

# ==================== 显示 Logo ====================
show_logo() {
    clear
    echo -e "${Cyan}"
    cat << "EOF"
    ╦  ╦╔═╗╔═╗   ╔═╗╦  ╔═╗╦ ╦
    ╚╗╔╝╠═╝╚═╗───╠═╝║  ╠═╣╚╦╝
     ╚╝ ╩  ╚═╝   ╩  ╩═╝╩ ╩ ╩ 
    通用 VPS 管理工具
EOF
    echo -e "${Reset}"
    echo -e "  版本: ${Green}v${version}${Reset}"
    echo -e "  环境: ${Yellow}${ENV_TYPE}${Reset} | ${Cyan}${OS_DISTRO}${Reset} | ${Blue}${ARCH}${Reset}"
    echo -e ""
}

# ==================== 模块管理 ====================
list_modules() {
    echo -e "${Green}==================== 可用模块 ====================${Reset}"
    echo -e " ${Green}1.${Reset}  sing-box    - 通用代理节点"
    echo -e " ${Green}2.${Reset}  GOST        - 流量中转工具"
    echo -e " ${Green}3.${Reset}  X-UI        - 可视化面板"
    echo -e " ${Green}4.${Reset}  FRPC        - 内网穿透客户端"
    echo -e " ${Green}5.${Reset}  Cloudflared - Cloudflare隧道"
    echo -e " ${Green}6.${Reset}  哪吒监控    - 服务器监控"
    echo -e "${Green}=================================================${Reset}"
}

# ==================== 系统工具菜单 ====================
show_tools_menu() {
    echo -e ""
    echo -e "${Green}==================== 系统工具 ====================${Reset}"
    echo -e " ${Green}1.${Reset}  端口管理"
    echo -e " ${Green}2.${Reset}  环境检测"
    echo -e " ${Green}3.${Reset}  保活设置"
    echo -e " ${Green}4.${Reset}  更新脚本"
    echo -e " ${Green}0.${Reset}  返回"
    echo -e "${Green}=================================================${Reset}"
}

# ==================== 端口管理菜单 ====================
port_manage_menu() {
    while true; do
        echo -e ""
        echo -e "${Green}==================== 端口管理 ====================${Reset}"
        echo -e " 当前方式: ${Cyan}${PORT_METHOD}${Reset}"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}1.${Reset}  添加端口"
        echo -e " ${Green}2.${Reset}  删除端口"
        echo -e " ${Green}3.${Reset}  列出所有端口"
        echo -e " ${Green}4.${Reset}  检查端口可用性"
        echo -e " ${Green}5.${Reset}  获取随机端口"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}=================================================${Reset}"
        
        read -p " 请选择 [0-5]: " choice
        
        case "$choice" in
            1)
                echo -e ""
                read -p "请输入端口号: " port
                read -p "协议类型 [tcp/udp/both] (默认tcp): " proto
                proto=${proto:-tcp}
                
                if [ "$PORT_METHOD" = "socat" ]; then
                    read -p "目标主机: " target_host
                    read -p "目标端口: " target_port
                    add_port "$port" "$proto" "$target_host" "$target_port"
                elif [ "$PORT_METHOD" = "iptables" ]; then
                    read -p "目标端口: " target_port
                    add_port "$port" "$proto" "" "$target_port"
                else
                    add_port "$port" "$proto"
                fi
                ;;
            2)
                echo -e ""
                read -p "请输入要删除的端口: " port
                read -p "协议类型 [tcp/udp/both] (默认tcp): " proto
                proto=${proto:-tcp}
                del_port "$port" "$proto"
                ;;
            3)
                echo -e ""
                list_ports
                ;;
            4)
                echo -e ""
                read -p "请输入要检查的端口: " port
                if check_port_available "$port"; then
                    echo -e "${Info} 端口 $port 可用"
                else
                    echo -e "${Warning} 端口 $port 已被占用"
                fi
                ;;
            5)
                port=$(get_random_port 10000 65535)
                echo -e "${Info} 随机可用端口: ${Green}$port${Reset}"
                ;;
            0)
                break
                ;;
            *)
                echo -e "${Error} 无效选择"
                ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# ==================== 主菜单 ====================
show_main_menu() {
    show_logo
    
    echo -e "${Green}==================== 主菜单 ====================${Reset}"
    echo -e " ${Green}代理节点${Reset}"
    echo -e " ${Green}1.${Reset}  ${Cyan}节点管理 (混合搭建)${Reset} ${Yellow}(Hy2/Tuic/Reality)${Reset}"
    echo -e " ${Green}2.${Reset}  GOST 中转"
    echo -e " ${Green}3.${Reset}  X-UI 面板"
    echo -e "${Green}---------------------------------------------------${Reset}"
    echo -e " ${Green}内网穿透${Reset}"
    echo -e " ${Green}4.${Reset}  FRPC 客户端"
    echo -e " ${Green}5.${Reset}  FRPS 服务端"
    echo -e " ${Green}6.${Reset}  Cloudflared 隧道"
    echo -e "${Green}---------------------------------------------------${Reset}"
    echo -e " ${Green}服务器管理${Reset}"
    echo -e " ${Green}7.${Reset}  跳板服务器 ${Cyan}(SSH 管理)${Reset}"
    echo -e " ${Green}8.${Reset}  哪吒监控"
    echo -e " ${Green}9.${Reset}  WARP 代理"
    echo -e " ${Green}10.${Reset} Docker 管理"
    echo -e " ${Green}11.${Reset} VPS 测评"
    echo -e " ${Green}12.${Reset} 流量统计 ${Cyan}(API)${Reset}"
    echo -e "${Green}---------------------------------------------------${Reset}"
    echo -e " ${Yellow}系统工具${Reset}"
    echo -e " ${Green}13.${Reset} 端口管理"
    echo -e " ${Green}14.${Reset} 进程管理"
    echo -e " ${Green}15.${Reset} 网络工具"
    echo -e " ${Green}16.${Reset} 环境检测"
    echo -e " ${Green}17.${Reset} 保活设置"
    echo -e " ${Green}18.${Reset} ${Cyan}Swap 管理${Reset} (小内存必备)"
    echo -e " ${Green}19.${Reset} 更新脚本"
    echo -e " ${Green}20.${Reset} 系统清理"
    echo -e " ${Green}21.${Reset} ${Red}卸载脚本${Reset}"
    echo -e "${Green}---------------------------------------------------${Reset}"
    echo -e " ${Red}0.${Reset}  退出"
    echo -e "${Green}=================================================${Reset}"
}

# ==================== 运行模块 ====================
run_module() {
    local module_name=$1
    local module_path=$2
    
    # 尝试多个可能的路径
    local paths=(
        "$SCRIPT_DIR/$module_path"
        "$HOME/vps-play/$module_path"
        "/root/vps-play/$module_path"
    )
    
    for path in "${paths[@]}"; do
        if [ -f "$path" ]; then
            bash "$path"
            return 0
        fi
    done
    
    echo -e "${Error} $module_name 模块未找到"
    echo -e "${Tip} 请检查安装目录: $SCRIPT_DIR"
    echo -e "${Tip} 尝试重新安装: curl -sL https://raw.githubusercontent.com/hxzlplp7/vps-play/main/install.sh | bash"
    return 1
}

# ==================== 主循环 ====================
main_loop() {
    while true; do
        show_main_menu
        
        read -p " 请选择 [0-21]: " choice
        
        case "$choice" in
            1)
                run_module "节点管理" "modules/nodes/manager.sh"
                ;;
            2)
                run_module "GOST" "modules/gost/manager.sh"
                ;;
            3)
                run_module "X-UI" "modules/xui/manager.sh"
                ;;
            4)
                run_module "FRPC" "modules/frpc/manager.sh"
                ;;
            5)
                run_module "FRPS" "modules/frps/manager.sh"
                ;;
            6)
                run_module "Cloudflared" "modules/cloudflared/manager.sh"
                ;;
            7)
                run_module "跳板服务器" "modules/jumper/manager.sh"
                ;;
            8)
                run_module "哪吒监控" "modules/nezha/manager.sh"
                ;;
            9)
                run_module "WARP" "modules/warp/manager.sh"
                ;;
            10)
                run_module "Docker" "modules/docker/manager.sh"
                ;;
            11)
                run_module "VPS测评" "modules/benchmark/manager.sh"
                ;;
            12)
                run_module "流量统计" "modules/stats/manager.sh"
                ;;
            13)
                if type port_manage_menu &>/dev/null; then
                    port_manage_menu
                else
                    echo -e "${Warning} 端口管理工具未加载"
                    echo -e "${Tip} 请尝试重新安装: curl -sL https://raw.githubusercontent.com/hxzlplp7/vps-play/main/install.sh | bash"
                fi
                ;;
            14)
                # 进程管理
                clear
                echo -e "${Cyan}==================== 进程管理 ====================${Reset}"
                echo -e ""
                echo -e "${Info} VPS-play 相关进程:"
                echo -e ""
                
                # 检查常见进程
                local found_process=false
                
                for proc in "sing-box" "gost" "cloudflared" "xray" "nezha-agent" "frpc" "frps" "hysteria" "tuic"; do
                    local pids=$(pgrep -f "$proc" 2>/dev/null)
                    if [ -n "$pids" ]; then
                        found_process=true
                        echo -e " ${Green}●${Reset} ${proc}"
                        for pid in $pids; do
                            local cmd=$(ps -p $pid -o args= 2>/dev/null | head -c 60)
                            echo -e "   └─ PID: ${Cyan}${pid}${Reset} | ${cmd}..."
                        done
                    fi
                done
                
                if [ "$found_process" = false ]; then
                    echo -e " ${Yellow}暂无运行中的 VPS-play 进程${Reset}"
                fi
                
                echo -e ""
                echo -e "${Green}---------------------------------------------------${Reset}"
                echo -e " ${Green}1.${Reset} 停止指定进程"
                echo -e " ${Green}2.${Reset} 停止所有 VPS-play 进程"
                echo -e " ${Green}3.${Reset} 查看所有进程 (ps aux)"
                echo -e " ${Green}0.${Reset} 返回"
                echo -e "${Green}===================================================${Reset}"
                
                read -p " 请选择 [0-3]: " proc_choice
                
                case "$proc_choice" in
                    1)
                        read -p "输入要停止的进程 PID: " kill_pid
                        if [ -n "$kill_pid" ]; then
                            kill "$kill_pid" 2>/dev/null && echo -e "${Info} 进程 $kill_pid 已停止" || echo -e "${Error} 停止失败"
                        fi
                        ;;
                    2)
                        echo -e "${Warning} 即将停止所有 VPS-play 相关进程"
                        read -p "确定? [y/N]: " confirm
                        if [[ $confirm =~ ^[Yy]$ ]]; then
                            pkill -f "sing-box" 2>/dev/null
                            pkill -f "gost" 2>/dev/null
                            pkill -f "cloudflared" 2>/dev/null
                            pkill -f "xray" 2>/dev/null
                            pkill -f "nezha-agent" 2>/dev/null
                            pkill -f "frpc" 2>/dev/null
                            pkill -f "frps" 2>/dev/null
                            pkill -f "hysteria" 2>/dev/null
                            pkill -f "tuic" 2>/dev/null
                            echo -e "${Info} 已停止所有进程"
                        fi
                        ;;
                    3)
                        echo -e ""
                        ps aux | head -1
                        ps aux | grep -E "sing-box|gost|cloudflared|xray|nezha|frp|hysteria|tuic" | grep -v grep
                        ;;
                esac
                ;;
            15)
                # 网络工具
                if type network_info &>/dev/null; then
                    network_info
                else
                    echo -e "${Warning} 网络工具未加载"
                    echo -e "${Tip} 查看 IP: curl -s ip.sb"
                fi
                ;;
            16)
                if type detect_environment &>/dev/null; then
                    detect_environment
                    show_env_info 2>/dev/null || echo -e "${Info} 环境检测完成"
                else
                    echo -e "${Warning} 环境检测工具未加载"
                fi
                ;;
            17)
                # 保活系统
                if [ -f "$SCRIPT_DIR/keepalive/manager.sh" ]; then
                    bash "$SCRIPT_DIR/keepalive/manager.sh"
                else
                    echo -e "${Error} 保活模块未找到"
                fi
                ;;
            18)
                # Swap 管理 - 调用 WARP 模块中的 Swap 管理函数
                # 直接内嵌 Swap 管理功能
                swap_menu() {
                    while true; do
                        clear
                        echo -e "${Cyan}"
                        cat << "SWAP_EOF"
    ╔═╗╦ ╦╔═╗╔═╗
    ╚═╗║║║╠═╣╠═╝
    ╚═╝╚╩╝╩ ╩╩  
    Swap 管理
SWAP_EOF
                        echo -e "${Reset}"
                        
                        # 显示当前状态
                        echo -e "${Info} 当前内存/Swap 状态:"
                        echo -e ""
                        local total_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
                        local used_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $3}')
                        local total_swap=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')
                        local used_swap=$(free -m 2>/dev/null | awk '/^Swap:/{print $3}')
                        
                        if [ -n "$total_mem" ]; then
                            echo -e " 物理内存: ${Cyan}${total_mem}MB${Reset} (已用: ${used_mem}MB)"
                        fi
                        if [ -n "$total_swap" ] && [ "$total_swap" -gt 0 ]; then
                            echo -e " 交换分区: ${Green}${total_swap}MB${Reset} (已用: ${used_swap}MB)"
                        else
                            echo -e " 交换分区: ${Red}未启用${Reset}"
                        fi
                        
                        # 检测容器环境
                        local is_container=false
                        local container_type=""
                        if [ -f /.dockerenv ]; then
                            is_container=true
                            container_type="Docker"
                        elif [ -f /run/.containerenv ]; then
                            is_container=true
                            container_type="Podman"
                        elif grep -qa "lxc" /proc/1/cgroup 2>/dev/null; then
                            is_container=true
                            container_type="LXC"
                        elif grep -qa "container=lxc" /proc/1/environ 2>/dev/null; then
                            is_container=true
                            container_type="LXC"
                        elif [ -d /proc/vz ] && [ ! -d /proc/bc ]; then
                            is_container=true
                            container_type="OpenVZ"
                        fi
                        
                        if [ "$is_container" = true ]; then
                            echo -e ""
                            echo -e " ${Yellow}⚠ 检测到容器环境: ${container_type}${Reset}"
                            echo -e " ${Yellow}  容器通常无法创建/管理 Swap${Reset}"
                        fi
                        echo -e ""
                        
                        echo -e "${Green}==================== Swap 管理 ====================${Reset}"
                        echo -e " ${Green}1.${Reset}  创建 Swap"
                        echo -e " ${Green}2.${Reset}  删除 Swap"
                        echo -e " ${Green}3.${Reset}  启用 Swap"
                        echo -e " ${Green}4.${Reset}  停止 Swap"
                        echo -e " ${Green}5.${Reset}  查看详细状态"
                        echo -e "${Green}---------------------------------------------------${Reset}"
                        echo -e " ${Green}0.${Reset}  返回"
                        echo -e "${Green}====================================================${Reset}"
                        
                        read -p " 请选择 [0-5]: " swap_choice
                        
                        case "$swap_choice" in
                            1)
                                # 创建 Swap
                                if [ "$(id -u)" -ne 0 ]; then
                                    echo -e "${Error} 创建 Swap 需要 root 权限"
                                else
                                    local cur_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
                                    cur_mem=${cur_mem:-0}
                                    local recommend=$((256 - cur_mem))
                                    [ $recommend -lt 256 ] && recommend=256
                                    
                                    echo -e ""
                                    echo -e "${Info} 创建 Swap 交换分区"
                                    echo -e " 当前内存: ${Cyan}${cur_mem}MB${Reset}"
                                    echo -e "${Tip} 建议: Swap + 内存至少达到 ${Yellow}256MB${Reset}"
                                    echo -e "${Tip} 推荐 Swap 大小: ${Green}${recommend}MB${Reset} 或更大"
                                    echo -e ""
                                    
                                    read -p "输入 Swap 大小 (MB) [默认${recommend}]: " swap_size
                                    swap_size=${swap_size:-$recommend}
                                    
                                    if [[ "$swap_size" =~ ^[0-9]+$ ]] && [ "$swap_size" -gt 0 ]; then
                                        echo -e "${Info} 正在创建 ${swap_size}MB Swap..."
                                        
                                        # 删除旧的
                                        swapoff /swapfile 2>/dev/null
                                        rm -f /swapfile 2>/dev/null
                                        
                                        # 创建新的
                                        if command -v fallocate &>/dev/null; then
                                            fallocate -l ${swap_size}M /swapfile 2>/dev/null || \
                                            dd if=/dev/zero of=/swapfile bs=1M count=$swap_size status=progress 2>/dev/null
                                        else
                                            dd if=/dev/zero of=/swapfile bs=1M count=$swap_size status=progress 2>/dev/null
                                        fi
                                        
                                        chmod 600 /swapfile
                                        mkswap /swapfile >/dev/null 2>&1
                                        swapon /swapfile 2>/dev/null
                                        
                                        # 添加到 fstab
                                        if ! grep -q "/swapfile" /etc/fstab 2>/dev/null; then
                                            echo "/swapfile none swap sw 0 0" >> /etc/fstab
                                        fi
                                        
                                        echo -e "${Info} Swap 创建成功!"
                                    else
                                        echo -e "${Error} 无效的大小"
                                    fi
                                fi
                                ;;
                            2)
                                # 删除 Swap
                                if [ "$(id -u)" -ne 0 ]; then
                                    echo -e "${Error} 删除 Swap 需要 root 权限"
                                else
                                    echo -e "${Warning} 确定删除 Swap? [y/N]"
                                    read -p "" confirm
                                    if [[ $confirm =~ ^[Yy]$ ]]; then
                                        swapoff -a 2>/dev/null
                                        rm -f /swapfile 2>/dev/null
                                        sed -i '/swapfile/d' /etc/fstab 2>/dev/null
                                        echo -e "${Info} Swap 已删除"
                                    fi
                                fi
                                ;;
                            3)
                                # 启用 Swap
                                if [ "$(id -u)" -ne 0 ]; then
                                    echo -e "${Error} 启用 Swap 需要 root 权限"
                                else
                                    echo -e ""
                                    # 检查 swapfile 是否存在
                                    if [ ! -f /swapfile ]; then
                                        echo -e "${Warning} /swapfile 不存在，请先创建 Swap"
                                    else
                                        # 检查是否已经启用
                                        local swap_before=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')
                                        if [ -n "$swap_before" ] && [ "$swap_before" -gt 0 ]; then
                                            echo -e "${Warning} Swap 已经是启用状态 (${swap_before}MB)"
                                        else
                                            # 尝试启用
                                            echo -e "${Info} 正在启用 /swapfile ..."
                                            local swap_result=$(swapon /swapfile 2>&1)
                                            local swap_exit=$?
                                            
                                            # 验证是否真正启用成功
                                            sleep 1
                                            local swap_after=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')
                                            
                                            if [ -n "$swap_after" ] && [ "$swap_after" -gt 0 ]; then
                                                echo -e "${Info} Swap 启用成功! (${swap_after}MB)"
                                                free -h 2>/dev/null | head -3
                                            else
                                                echo -e "${Error} 启用失败 - Swap 未生效"
                                                if [ -n "$swap_result" ]; then
                                                    echo -e "${Warning} 错误信息: ${swap_result}"
                                                fi
                                                echo -e ""
                                                echo -e "${Tip} 可能的原因:"
                                                echo -e "  1. ${Yellow}容器环境 (LXC/Docker/Podman) 不支持 Swap${Reset}"
                                                echo -e "  2. swapfile 未正确格式化，尝试: mkswap /swapfile"
                                                echo -e "  3. 权限问题，确保权限为 600: chmod 600 /swapfile"
                                                echo -e "  4. 内核或 cgroup 限制了 swap"
                                            fi
                                        fi
                                    fi
                                fi
                                ;;
                            4)
                                # 停止 Swap
                                if [ "$(id -u)" -ne 0 ]; then
                                    echo -e "${Error} 停止 Swap 需要 root 权限"
                                else
                                    echo -e ""
                                    # 检查是否有活动的 swap
                                    local active_swap=$(swapon --show 2>/dev/null)
                                    if [ -z "$active_swap" ]; then
                                        echo -e "${Warning} 当前没有启用的 Swap"
                                    else
                                        echo -e "${Info} 当前活动的 Swap:"
                                        echo "$active_swap"
                                        echo -e ""
                                        echo -e "${Info} 正在停止所有 Swap ..."
                                        local swapoff_result=$(swapoff -a 2>&1)
                                        if [ $? -eq 0 ]; then
                                            echo -e "${Info} Swap 已停止"
                                        else
                                            echo -e "${Error} 停止失败"
                                            echo -e "${Warning} 错误信息: ${swapoff_result}"
                                            echo -e "${Tip} 可能有进程正在使用 Swap，请检查内存使用情况"
                                        fi
                                    fi
                                fi
                                ;;
                            5)
                                echo -e ""
                                echo -e "${Info} 详细状态:"
                                free -h 2>/dev/null || free -m
                                echo -e ""
                                swapon --show 2>/dev/null
                                ;;
                            0)
                                return 0
                                ;;
                        esac
                        
                        echo -e ""
                        read -p "按回车继续..."
                    done
                }
                swap_menu
                ;;
            19)
                echo -e "${Info} 更新脚本..."
                echo -e ""
                
                local REPO_RAW="https://raw.githubusercontent.com/hxzlplp7/vps-play/main"
                local UPDATE_DIR="$SCRIPT_DIR"
                local update_count=0
                local fail_count=0
                
                # 更新文件函数
                update_file() {
                    local path=$1
                    local url="${REPO_RAW}/${path}"
                    local dest="${UPDATE_DIR}/${path}"
                    
                    mkdir -p "$(dirname "$dest")" 2>/dev/null
                    
                    # 下载到临时文件
                    local tmp_file="${dest}.tmp"
                    if curl -sL "$url" -o "$tmp_file" 2>/dev/null; then
                        if [ -s "$tmp_file" ]; then
                            mv "$tmp_file" "$dest"
                            chmod +x "$dest" 2>/dev/null
                            echo -e "  ${Green}✓${Reset} $path"
                            update_count=$((update_count + 1))
                            return 0
                        fi
                    fi
                    rm -f "$tmp_file" 2>/dev/null
                    echo -e "  ${Red}✗${Reset} $path"
                    fail_count=$((fail_count + 1))
                    return 1
                }
                
                echo -e "${Info} 更新核心文件..."
                update_file "start.sh"
                update_file "install.sh"
                update_file "uninstall.sh"
                
                echo -e "${Info} 更新工具库..."
                update_file "utils/env_detect.sh"
                update_file "utils/port_manager.sh"
                update_file "utils/process_manager.sh"
                update_file "utils/network.sh"
                update_file "utils/system_clean.sh"
                
                echo -e "${Info} 更新功能模块..."
                update_file "modules/nodes/manager.sh"
                update_file "modules/singbox/manager.sh"
                update_file "modules/hysteria/manager.sh"
                update_file "modules/tuic/manager.sh"
                update_file "modules/argo/manager.sh"
                update_file "modules/gost/manager.sh"
                update_file "modules/gost/gost.sh"
                update_file "modules/xui/manager.sh"
                update_file "modules/frpc/manager.sh"
                update_file "modules/frps/manager.sh"
                update_file "modules/cloudflared/manager.sh"
                update_file "modules/jumper/manager.sh"
                update_file "modules/nezha/manager.sh"
                update_file "modules/warp/manager.sh"
                update_file "modules/docker/manager.sh"
                update_file "modules/benchmark/manager.sh"
                update_file "modules/stats/manager.sh"
                
                echo -e "${Info} 更新保活模块..."
                update_file "keepalive/manager.sh"
                
                echo -e ""
                echo -e "${Info} 更新完成: ${Green}${update_count}${Reset} 成功, ${Red}${fail_count}${Reset} 失败"
                
                if [ $update_count -gt 0 ]; then
                    echo -e "${Tip} 请重新运行脚本以使用新版本"
                    echo -e ""
                    read -p "立即重启脚本? [Y/n]: " restart_choice
                    restart_choice=${restart_choice:-Y}
                    if [[ $restart_choice =~ ^[Yy]$ ]]; then
                        exec bash "$SCRIPT_DIR/start.sh"
                    fi
                fi
                ;;
            20)
                # 系统清理 - 尝试多个可能的路径
                local clean_script=""
                for _p in "$SCRIPT_DIR/utils/system_clean.sh" "$HOME/vps-play/utils/system_clean.sh" "/root/vps-play/utils/system_clean.sh"; do
                    if [ -f "$_p" ]; then
                        clean_script="$_p"
                        break
                    fi
                done
                
                if [ -n "$clean_script" ]; then
                    bash "$clean_script"
                else
                    echo -e "${Warning} 系统清理工具未找到"
                    echo -e "${Tip} 手动清理命令:"
                    echo -e "  apt-get clean && apt-get autoremove -y"
                    echo -e "  rm -rf /tmp/* /var/log/*.gz"
                fi
                ;;
            21)
                # 卸载脚本
                local uninstall_script=""
                for _p in "$SCRIPT_DIR/uninstall.sh" "$HOME/vps-play/uninstall.sh" "/root/vps-play/uninstall.sh"; do
                    if [ -f "$_p" ]; then
                        uninstall_script="$_p"
                        break
                    fi
                done
                
                if [ -n "$uninstall_script" ]; then
                    bash "$uninstall_script"
                else
                    # 从网络下载卸载脚本
                    echo -e "${Info} 下载卸载脚本..."
                    curl -sL https://raw.githubusercontent.com/hxzlplp7/vps-play/main/uninstall.sh | bash
                fi
                ;;
            0)
                echo -e "${Info} 感谢使用 VPS-play!"
                exit 0
                ;;
            *)
                echo -e "${Error} 无效选择"
                ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# ==================== 入口 ====================
main() {
    init_environment
    main_loop
}

main
