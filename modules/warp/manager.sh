#!/bin/bash
# WARP 模块 - VPS-play
# Cloudflare WARP 代理管理
# 参考: ygkkk/CFwarp, fscarmen/warp

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
WGCF_BIN="$WARP_DIR/wgcf"
WGCF_ACCOUNT="$WARP_DIR/wgcf-account.toml"
WGCF_PROFILE="$WARP_DIR/wgcf-profile.conf"
WARP_CONF="/etc/wireguard/wgcf.conf"

mkdir -p "$WARP_DIR"

# wgcf 版本
WGCF_VERSION="2.2.22"

# ==================== 系统检测 ====================
check_system() {
    if [ -z "$OS_TYPE" ]; then
        case "$(uname -s)" in
            Linux) OS_TYPE="linux" ;;
            FreeBSD) OS_TYPE="freebsd" ;;
        esac
    fi
    
    if [ -z "$ARCH" ]; then
        case "$(uname -m)" in
            x86_64|amd64) ARCH="amd64" ;;
            aarch64|arm64) ARCH="arm64" ;;
            armv7l) ARCH="armv7" ;;
        esac
    fi
    
    # 检测发行版
    if [ -z "$OS_DISTRO" ] && [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_DISTRO=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
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

# ==================== Swap 管理 ====================
# 检查当前 Swap 状态
check_swap_status() {
    echo -e "${Info} 当前 Swap 状态:"
    echo -e ""
    
    # 获取内存信息
    local total_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    local used_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $3}')
    local free_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $4}')
    
    if [ -n "$total_mem" ]; then
        echo -e " 物理内存: ${Cyan}${total_mem}MB${Reset} (已用: ${used_mem}MB, 空闲: ${free_mem}MB)"
    fi
    
    # 获取 Swap 信息
    local total_swap=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')
    local used_swap=$(free -m 2>/dev/null | awk '/^Swap:/{print $3}')
    local free_swap=$(free -m 2>/dev/null | awk '/^Swap:/{print $4}')
    
    if [ -n "$total_swap" ] && [ "$total_swap" -gt 0 ]; then
        echo -e " 交换分区: ${Green}${total_swap}MB${Reset} (已用: ${used_swap}MB, 空闲: ${free_swap}MB)"
        
        # 显示 swap 文件位置
        echo -e ""
        echo -e " Swap 详情:"
        swapon --show 2>/dev/null | while read line; do
            echo -e "   $line"
        done
    else
        echo -e " 交换分区: ${Red}未启用${Reset}"
    fi
    echo -e ""
}

# 创建 Swap
create_swap() {
    # 检查 root 权限
    if [ "$EUID" -ne 0 ] && [ "$(id -u)" -ne 0 ]; then
        echo -e "${Error} 创建 Swap 需要 root 权限"
        return 1
    fi
    
    # 检查是否已存在 swap
    local current_swap=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')
    if [ -n "$current_swap" ] && [ "$current_swap" -gt 0 ]; then
        echo -e "${Warning} 当前已有 ${current_swap}MB Swap"
        read -p "是否删除现有 Swap 并创建新的? [y/N]: " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            delete_swap
        else
            return 0
        fi
    fi
    
    # 获取当前内存
    local current_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    current_mem=${current_mem:-0}
    
    # 计算推荐的 swap 大小 (使 swap + 内存至少达到 256MB)
    local min_total=256
    local recommended_swap=0
    if [ "$current_mem" -lt "$min_total" ]; then
        recommended_swap=$((min_total - current_mem))
        # 至少 128MB，最好 256MB 以上更安全
        [ "$recommended_swap" -lt 128 ] && recommended_swap=256
    else
        # 内存够用，但还是建议 256-512MB swap 作为缓冲
        recommended_swap=256
    fi
    
    echo -e ""
    echo -e "${Info} 创建 Swap 交换分区"
    echo -e ""
    echo -e " 当前内存: ${Cyan}${current_mem}MB${Reset}"
    echo -e ""
    echo -e "${Tip} 建议: Swap + 内存 至少达到 ${Yellow}256MB${Reset}"
    if [ "$current_mem" -lt "$min_total" ]; then
        echo -e "${Warning} 当前内存不足 256MB，强烈建议创建 Swap!"
        echo -e "${Tip} 推荐 Swap 大小: ${Green}${recommended_swap}MB${Reset} 或更大"
    else
        echo -e "${Tip} 推荐 Swap 大小: ${Green}256MB - 1GB${Reset}"
    fi
    echo -e ""
    
    # 选择单位
    echo -e " ${Green}1.${Reset} MB (兆字节)"
    echo -e " ${Green}2.${Reset} GB (吉字节)"
    echo -e ""
    read -p "选择单位 [1/2, 默认1]: " unit_choice
    unit_choice=${unit_choice:-1}
    
    local unit="GB"
    local multiplier=1024
    if [ "$unit_choice" = "1" ]; then
        unit="MB"
        multiplier=1
    fi
    
    # 计算默认大小
    local default_size=$recommended_swap
    if [ "$unit" = "GB" ]; then
        default_size=1
    fi
    
    read -p "输入 Swap 大小 (${unit}) [默认${default_size}]: " swap_size
    swap_size=${swap_size:-$default_size}
    
    # 验证输入
    if ! [[ "$swap_size" =~ ^[0-9]+$ ]] || [ "$swap_size" -le 0 ]; then
        echo -e "${Error} 无效的大小，请输入正整数"
        return 1
    fi
    
    # 计算实际大小 (MB)
    local swap_mb=$((swap_size * multiplier))
    
    # 检查磁盘空间
    local free_disk=$(df -m / | awk 'NR==2{print $4}')
    if [ "$swap_mb" -gt "$free_disk" ]; then
        echo -e "${Error} 磁盘空间不足，需要 ${swap_mb}MB，可用 ${free_disk}MB"
        return 1
    fi
    
    echo -e ""
    echo -e "${Info} 正在创建 ${swap_size}${unit} Swap 文件..."
    
    # 创建 swap 文件
    local swap_file="/swapfile"
    
    # 检查并删除可能存在的旧文件
    [ -f "$swap_file" ] && rm -f "$swap_file"
    
    # 使用 fallocate 或 dd 创建文件
    if command -v fallocate &>/dev/null; then
        if ! fallocate -l ${swap_mb}M "$swap_file" 2>/dev/null; then
            echo -e "${Warning} fallocate 失败，尝试使用 dd..."
            dd if=/dev/zero of="$swap_file" bs=1M count=$swap_mb status=progress 2>/dev/null
        fi
    else
        dd if=/dev/zero of="$swap_file" bs=1M count=$swap_mb status=progress 2>/dev/null
    fi
    
    if [ ! -f "$swap_file" ]; then
        echo -e "${Error} 创建 Swap 文件失败"
        return 1
    fi
    
    # 设置权限
    chmod 600 "$swap_file"
    
    # 格式化为 swap
    echo -e "${Info} 格式化 Swap 文件..."
    if ! mkswap "$swap_file" >/dev/null 2>&1; then
        echo -e "${Error} 格式化 Swap 失败"
        rm -f "$swap_file"
        return 1
    fi
    
    # 启用 swap
    echo -e "${Info} 启用 Swap..."
    if ! swapon "$swap_file" 2>/dev/null; then
        echo -e "${Error} 启用 Swap 失败"
        rm -f "$swap_file"
        return 1
    fi
    
    # 添加到 fstab 实现开机自动挂载
    if ! grep -q "$swap_file" /etc/fstab 2>/dev/null; then
        echo "$swap_file none swap sw 0 0" >> /etc/fstab
        echo -e "${Info} 已添加到 /etc/fstab (开机自动挂载)"
    fi
    
    echo -e ""
    echo -e "${Info} Swap 创建成功!"
    check_swap_status
}

# 删除 Swap
delete_swap() {
    # 检查 root 权限
    if [ "$EUID" -ne 0 ] && [ "$(id -u)" -ne 0 ]; then
        echo -e "${Error} 删除 Swap 需要 root 权限"
        return 1
    fi
    
    local current_swap=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')
    if [ -z "$current_swap" ] || [ "$current_swap" -le 0 ]; then
        echo -e "${Warning} 当前没有启用 Swap"
        return 0
    fi
    
    echo -e "${Info} 正在删除 Swap..."
    
    # 获取所有 swap 设备/文件
    local swap_files=$(swapon --show=NAME --noheadings 2>/dev/null)
    
    for swap_file in $swap_files; do
        echo -e " 禁用: $swap_file"
        swapoff "$swap_file" 2>/dev/null
        
        # 如果是文件则删除
        if [ -f "$swap_file" ]; then
            rm -f "$swap_file"
            echo -e " 删除: $swap_file"
        fi
        
        # 从 fstab 中移除
        if grep -q "$swap_file" /etc/fstab 2>/dev/null; then
            sed -i "\|$swap_file|d" /etc/fstab
            echo -e " 已从 /etc/fstab 中移除"
        fi
    done
    
    echo -e "${Info} Swap 已删除"
}

# Swap 管理菜单
manage_swap_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔═╗╦ ╦╔═╗╔═╗
    ╚═╗║║║╠═╣╠═╝
    ╚═╝╚╩╝╩ ╩╩  
    Swap 管理
EOF
        echo -e "${Reset}"
        
        check_swap_status
        
        echo -e "${Green}==================== Swap 管理 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  创建 Swap"
        echo -e " ${Green}2.${Reset}  删除 Swap"
        echo -e " ${Green}3.${Reset}  查看状态"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}====================================================${Reset}"
        
        read -p " 请选择 [0-3]: " choice
        
        case "$choice" in
            1) create_swap ;;
            2) 
                read -p "确定删除 Swap? [y/N]: " confirm
                [[ $confirm =~ ^[Yy]$ ]] && delete_swap
                ;;
            3) check_swap_status ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# ==================== 安装依赖 ====================
install_deps() {
    echo -e "${Info} 检查依赖..."
    
    # 在 Debian/Ubuntu 上先修复可能的 dpkg 问题 (在所有模式下执行)
    if [ -f /etc/debian_version ]; then
        # 检测 dpkg 中断
        if dpkg --audit 2>/dev/null | grep -q . || \
           [ -f /var/lib/dpkg/lock-frontend ] || \
           [ -f /var/lib/dpkg/lock ]; then
            echo -e "${Warning} 检测到 dpkg 问题，正在修复..."
            rm -f /var/lib/dpkg/lock-frontend 2>/dev/null
            rm -f /var/lib/dpkg/lock 2>/dev/null
            rm -f /var/cache/apt/archives/lock 2>/dev/null
            dpkg --configure -a 2>/dev/null
            echo -e "${Info} dpkg 修复完成"
        fi
    fi
    
    # 检测内存
    local total_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    local total_swap=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')
    total_mem=${total_mem:-512}
    total_swap=${total_swap:-0}
    local total_available=$((total_mem + total_swap))
    
    # 小内存模式 (< 256MB)
    if [ "$total_available" -lt 256 ]; then
        echo -e ""
        echo -e "${Warning} ===== 小内存模式 ====="
        echo -e "${Warning} 内存 + Swap 仅 ${Cyan}${total_available}MB${Reset}"
        echo -e "${Warning} apt/yum 安装大型包可能会因内存不足被 Killed"
        echo -e ""
        
        # 检查是否已有必要命令
        local has_wg=false
        local has_curl=true
        
        command -v wg &>/dev/null && has_wg=true
        command -v curl &>/dev/null || has_curl=false
        
        if [ "$has_curl" = false ]; then
            echo -e "${Error} curl 未安装，这是必需的"
            return 1
        fi
        
        if [ "$has_wg" = true ]; then
            echo -e "${Info} wireguard-tools 已安装 ✓"
            echo -e "${Info} 依赖检查完成"
            return 0
        fi
        
        echo -e "${Error} wireguard-tools 未安装"
        echo -e ""
        echo -e "${Tip} 请选择安装方式:"
        echo -e ""
        echo -e " ${Green}1.${Reset} 创建 Swap 后自动安装 (推荐)"
        echo -e " ${Green}2.${Reset} 手动下载 deb 包上传安装"
        echo -e " ${Green}3.${Reset} 使用 Cloudflare WARP 官方客户端"
        echo -e " ${Green}4.${Reset} 强制 apt 安装 (可能失败)"
        echo -e " ${Green}0.${Reset} 取消"
        echo -e ""
        
        read -p "请选择 [0-4]: " install_choice
        
        case "$install_choice" in
            1)
                # 创建 Swap 后安装
                echo -e "${Info} 请先创建 Swap..."
                echo -e "${Tip} 选择菜单 ${Cyan}13. Swap 管理${Reset} 创建至少 256MB Swap"
                echo -e "${Tip} 然后重新运行安装"
                return 1
                ;;
            2)
                # 手动下载 deb 包安装
                local deb_dir="/tmp/wg-debs"
                mkdir -p "$deb_dir"
                
                # 获取系统架构
                local arch=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
                local codename=$(lsb_release -cs 2>/dev/null || echo "bookworm")
                
                echo -e ""
                echo -e "${Info} ===== 手动安装模式 ====="
                echo -e ""
                echo -e "${Tip} 请在本地电脑下载以下 deb 包并上传到服务器:"
                echo -e ""
                echo -e " ${Green}下载地址 (Debian ${codename} ${arch}):${Reset}"
                echo -e "   wireguard-tools: ${Cyan}https://packages.debian.org/${codename}/${arch}/wireguard-tools/download${Reset}"
                echo -e ""
                echo -e " ${Green}上传位置:${Reset}"
                echo -e "   ${Cyan}${deb_dir}/${Reset}"
                echo -e ""
                echo -e " ${Green}上传命令示例:${Reset}"
                echo -e "   ${Yellow}scp wireguard-tools_*.deb root@你的IP:${deb_dir}/${Reset}"
                echo -e ""
                echo -e "${Tip} 如果下载页面显示依赖包，也需要一起下载上传"
                echo -e ""
                
                while true; do
                    read -p "文件已上传完成? [y/n/q(退出)]: " upload_confirm
                    
                    if [[ $upload_confirm =~ ^[Qq]$ ]]; then
                        echo -e "${Warning} 已取消"
                        return 1
                    fi
                    
                    if [[ ! $upload_confirm =~ ^[Yy]$ ]]; then
                        continue
                    fi
                    
                    # 检查是否有 deb 文件
                    local deb_files=$(ls ${deb_dir}/*.deb 2>/dev/null)
                    if [ -z "$deb_files" ]; then
                        echo -e "${Error} 未找到 deb 文件: ${deb_dir}/*.deb"
                        echo -e "${Tip} 请确保已上传 .deb 文件到 ${deb_dir}/ 目录"
                        continue
                    fi
                    
                    echo -e "${Info} 找到以下 deb 文件:"
                    ls -lh ${deb_dir}/*.deb
                    echo -e ""
                    
                    # 尝试安装
                    echo -e "${Info} 正在安装..."
                    if dpkg -i ${deb_dir}/*.deb 2>&1; then
                        # 修复可能的依赖问题
                        apt-get install -f -y --no-install-recommends 2>/dev/null
                        
                        # 验证安装
                        if command -v wg &>/dev/null; then
                            echo -e "${Info} wireguard-tools 安装成功!"
                            rm -rf "$deb_dir"
                            return 0
                        fi
                    fi
                    
                    echo -e "${Error} 安装失败，请检查 deb 包是否正确"
                    echo -e "${Tip} 可能需要下载更多依赖包"
                    echo -e ""
                done
                ;;
            3)
                # Cloudflare 官方客户端
                echo -e "${Info} 安装 Cloudflare WARP 官方客户端..."
                curl https://pkg.cloudflareclient.com/install.sh | bash
                if command -v warp-cli &>/dev/null; then
                    echo -e "${Info} WARP 客户端安装成功"
                    echo -e "${Tip} 使用方法: warp-cli register && warp-cli connect"
                    return 0
                else
                    echo -e "${Error} 安装失败"
                    return 1
                fi
                ;;
            4)
                # 强制 apt 安装
                echo -e "${Warning} 强制安装，可能因内存不足失败..."
                ;;
            *)
                return 1
                ;;
        esac
    fi
    
    # 正常安装模式
    echo -e "${Info} 安装依赖..."
    
    case "$OS_DISTRO" in
        debian|ubuntu)
            # 设置非交互模式，避免 debconf 问题
            export DEBIAN_FRONTEND=noninteractive
            
            apt-get update
            
            # 只安装新包，不升级现有包 (避免升级 linux-image 等大型包)
            # --no-upgrade: 不升级已安装的包
            apt-get install -y --no-install-recommends --no-upgrade wireguard-tools
            
            # 如果失败，可能是依赖问题，尝试修复
            if [ $? -ne 0 ]; then
                echo -e "${Warning} 安装失败，尝试修复依赖..."
                apt-get install -f -y --no-install-recommends
                apt-get install -y --no-install-recommends --no-upgrade wireguard-tools
            fi
            ;;
        centos|rhel|rocky|alma)
            yum install -y epel-release
            yum install -y curl wget wireguard-tools
            ;;
        fedora)
            dnf install -y curl wget wireguard-tools
            ;;
        alpine)
            apk add curl wget wireguard-tools
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm curl wget wireguard-tools
            ;;
        freebsd)
            pkg install -y curl wget wireguard
            ;;
        *)
            echo -e "${Warning} 未知系统，请手动安装 wireguard-tools"
            ;;
    esac
}

# ==================== 下载 wgcf ====================
download_wgcf() {
    local os_type="linux"
    [ "$OS_TYPE" = "freebsd" ] && os_type="freebsd"
    
    local arch_type="amd64"
    case "$ARCH" in
        arm64) arch_type="arm64" ;;
        armv7) arch_type="armv7" ;;
    esac
    
    local filename="wgcf_${WGCF_VERSION}_${os_type}_${arch_type}"
    local url="https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VERSION}/${filename}"
    
    # 检测内存大小
    local total_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    total_mem=${total_mem:-512}
    
    # 如果内存小于 256MB，提示手动上传
    if [ "$total_mem" -lt 256 ]; then
        echo -e ""
        echo -e "${Warning} 检测到内存较小: ${Cyan}${total_mem}MB${Reset}"
        echo -e "${Warning} 小内存服务器下载/解压可能会失败"
        echo -e ""
        echo -e "${Tip} 请在本地下载 wgcf 并手动上传到服务器:"
        echo -e ""
        echo -e " ${Green}下载地址:${Reset}"
        echo -e "   ${Cyan}${url}${Reset}"
        echo -e ""
        echo -e " ${Green}上传位置:${Reset}"
        echo -e "   ${Cyan}${WGCF_BIN}${Reset}"
        echo -e ""
        echo -e " ${Green}上传方法:${Reset}"
        echo -e "   1. 在本地电脑下载上述文件"
        echo -e "   2. 使用 SCP/SFTP 上传到服务器:"
        echo -e "      ${Yellow}scp ${filename} root@你的IP:${WGCF_BIN}${Reset}"
        echo -e "   3. 或使用 rz 命令 (如果已安装 lrzsz):"
        echo -e "      ${Yellow}rz -be > ${WGCF_BIN}${Reset}"
        echo -e ""
        
        read -p "文件已上传完成? 按回车确认，或输入 n 取消: " upload_confirm
        
        if [[ $upload_confirm =~ ^[Nn]$ ]]; then
            echo -e "${Warning} 已取消"
            return 1
        fi
        
        # 检查文件是否存在
        if [ ! -f "$WGCF_BIN" ]; then
            echo -e "${Error} 未找到文件: $WGCF_BIN"
            echo -e "${Tip} 请确保已正确上传文件"
            return 1
        fi
        
        # 检查文件大小
        local file_size=$(stat -c%s "$WGCF_BIN" 2>/dev/null || stat -f%z "$WGCF_BIN" 2>/dev/null)
        if [ -z "$file_size" ] || [ "$file_size" -lt 1000000 ]; then
            echo -e "${Warning} 文件大小异常 (${file_size:-0} bytes)，可能上传不完整"
            read -p "继续? [y/N]: " continue_choice
            [[ ! $continue_choice =~ ^[Yy]$ ]] && return 1
        fi
        
        # 设置执行权限
        chmod +x "$WGCF_BIN"
        echo -e "${Info} 已设置执行权限"
        
        # 验证文件
        if "$WGCF_BIN" --version &>/dev/null; then
            echo -e "${Info} wgcf 验证成功"
            return 0
        else
            echo -e "${Error} wgcf 文件无法执行，请检查是否下载了正确的版本"
            echo -e "${Tip} 确保下载的是 ${os_type} ${arch_type} 版本"
            return 1
        fi
    fi
    
    # 内存足够，正常下载
    echo -e "${Info} 下载 wgcf v${WGCF_VERSION}..."
    
    if curl -sL "$url" -o "$WGCF_BIN"; then
        chmod +x "$WGCF_BIN"
        echo -e "${Info} wgcf 下载完成"
        return 0
    else
        echo -e "${Error} wgcf 下载失败"
        echo -e "${Tip} 如果下载失败，请尝试手动下载:"
        echo -e "   ${Cyan}${url}${Reset}"
        return 1
    fi
}

# ==================== 注册 WARP ====================
register_warp() {
    if [ ! -f "$WGCF_BIN" ]; then
        echo -e "${Error} 请先下载 wgcf"
        return 1
    fi
    
    cd "$WARP_DIR"
    
    if [ -f "$WGCF_ACCOUNT" ]; then
        echo -e "${Warning} 已存在 WARP 账户"
        read -p "重新注册? [y/N]: " re_reg
        [[ ! $re_reg =~ ^[Yy]$ ]] && return 0
        rm -f "$WGCF_ACCOUNT"
    fi
    
    echo -e "${Info} 注册 WARP 账户..."
    
    # 注册 (最多重试5次)
    local retry=0
    while [ $retry -lt 5 ]; do
        if $WGCF_BIN register --accept-tos 2>/dev/null; then
            echo -e "${Info} 注册成功"
            return 0
        fi
        retry=$((retry + 1))
        echo -e "${Warning} 注册失败，重试 $retry/5..."
        sleep 2
    done
    
    echo -e "${Error} 注册失败，请检查网络"
    return 1
}

# ==================== 生成配置 ====================
generate_config() {
    if [ ! -f "$WGCF_ACCOUNT" ]; then
        echo -e "${Error} 请先注册 WARP 账户"
        return 1
    fi
    
    cd "$WARP_DIR"
    
    echo -e "${Info} 生成 WireGuard 配置..."
    
    if $WGCF_BIN generate 2>/dev/null; then
        echo -e "${Info} 配置生成成功"
        
        # 优化配置
        optimize_config
        
        return 0
    else
        echo -e "${Error} 配置生成失败"
        return 1
    fi
}

# ==================== 优化配置 ====================
optimize_config() {
    if [ ! -f "$WGCF_PROFILE" ]; then
        echo -e "${Error} 配置文件不存在"
        return 1
    fi
    
    echo -e ""
    echo -e "${Info} 选择 WARP 模式:"
    echo -e " ${Green}1.${Reset} 仅 IPv4 (推荐大多数用户)"
    echo -e " ${Green}2.${Reset} 仅 IPv6"
    echo -e " ${Green}3.${Reset} 双栈 IPv4 + IPv6"
    echo -e " ${Green}4.${Reset} 非全局 (仅特定IP走WARP)"
    
    read -p "请选择 [1-4, 默认1]: " mode
    mode=${mode:-1}
    
    case "$mode" in
        1)
            # 仅IPv4
            sed -i 's/AllowedIPs = .*/AllowedIPs = 0.0.0.0\/0/' "$WGCF_PROFILE"
            echo -e "${Info} 已设置为 IPv4 模式"
            ;;
        2)
            # 仅IPv6
            sed -i 's/AllowedIPs = .*/AllowedIPs = ::\/0/' "$WGCF_PROFILE"
            echo -e "${Info} 已设置为 IPv6 模式"
            ;;
        3)
            # 双栈
            sed -i 's/AllowedIPs = .*/AllowedIPs = 0.0.0.0\/0, ::\/0/' "$WGCF_PROFILE"
            echo -e "${Info} 已设置为双栈模式"
            ;;
        4)
            # 非全局 - 仅 Cloudflare IP 走 WARP
            sed -i 's/AllowedIPs = .*/AllowedIPs = 1.1.1.1\/32, 1.0.0.1\/32, 2606:4700:4700::1111\/128, 2606:4700:4700::1001\/128/' "$WGCF_PROFILE"
            echo -e "${Info} 已设置为非全局模式"
            ;;
    esac
    
    # 添加 MTU 优化
    if ! grep -q "MTU" "$WGCF_PROFILE"; then
        sed -i '/\[Peer\]/i MTU = 1280' "$WGCF_PROFILE"
    fi
    
    # 添加 DNS
    if ! grep -q "DNS" "$WGCF_PROFILE"; then
        sed -i '/\[Interface\]/a DNS = 1.1.1.1, 2606:4700:4700::1111' "$WGCF_PROFILE"
    fi
    
    echo -e "${Info} 配置优化完成"
}

# ==================== 启动 WARP ====================
start_warp() {
    if [ ! -f "$WGCF_PROFILE" ]; then
        echo -e "${Error} 请先生成配置"
        return 1
    fi
    
    # 检查 WireGuard
    if ! command -v wg &>/dev/null; then
        echo -e "${Warning} WireGuard 未安装"
        install_deps
    fi
    
    echo -e "${Info} 启动 WARP..."
    
    # 复制配置到 WireGuard 目录
    if [ "$OS_TYPE" = "freebsd" ]; then
        mkdir -p /usr/local/etc/wireguard
        cp "$WGCF_PROFILE" /usr/local/etc/wireguard/wgcf.conf
        wg-quick up wgcf
    else
        mkdir -p /etc/wireguard
        cp "$WGCF_PROFILE" /etc/wireguard/wgcf.conf
        
        # 设置权限
        chmod 600 /etc/wireguard/wgcf.conf
        
        # 启动
        wg-quick up wgcf
        
        # 设置开机自启
        if command -v systemctl &>/dev/null; then
            systemctl enable wg-quick@wgcf 2>/dev/null
        fi
    fi
    
    sleep 2
    
    # 检查状态
    if wg show wgcf &>/dev/null; then
        echo -e "${Info} WARP 启动成功"
        show_ip
    else
        echo -e "${Error} WARP 启动失败"
    fi
}

# ==================== 停止 WARP ====================
stop_warp() {
    echo -e "${Info} 停止 WARP..."
    
    wg-quick down wgcf 2>/dev/null
    
    if command -v systemctl &>/dev/null; then
        systemctl disable wg-quick@wgcf 2>/dev/null
    fi
    
    echo -e "${Info} WARP 已停止"
}

# ==================== 重启 WARP ====================
restart_warp() {
    stop_warp
    sleep 1
    start_warp
}

# ==================== WARP 状态 ====================
status_warp() {
    echo -e "${Info} WARP 状态:"
    echo -e ""
    
    if wg show wgcf &>/dev/null 2>&1; then
        echo -e " 运行状态: ${Green}运行中${Reset}"
        echo -e ""
        wg show wgcf
    else
        echo -e " 运行状态: ${Red}未运行${Reset}"
    fi
    
    echo -e ""
    show_ip
}

# ==================== 卸载 WARP ====================
uninstall_warp() {
    echo -e "${Warning} 确定卸载 WARP? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    stop_warp
    
    rm -f /etc/wireguard/wgcf.conf
    rm -f /usr/local/etc/wireguard/wgcf.conf
    rm -rf "$WARP_DIR"
    
    echo -e "${Info} WARP 已卸载"
}

# ==================== 一键安装 ====================
quick_install() {
    echo -e "${Info} 开始一键安装 WARP..."
    
    check_system
    
    # 检查内存，如果太小且没有 swap，建议先创建
    local total_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    local total_swap=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')
    
    if [ -n "$total_mem" ] && [ "$total_mem" -lt 512 ]; then
        echo -e ""
        echo -e "${Warning} 检测到内存较小: ${Cyan}${total_mem}MB${Reset}"
        
        if [ -z "$total_swap" ] || [ "$total_swap" -le 0 ]; then
            echo -e "${Warning} 且没有 Swap 交换分区"
            echo -e "${Tip} 小内存机器安装 WARP 可能会因内存不足被 killed"
            echo -e ""
            read -p "是否先创建 Swap? [Y/n]: " create_swap_choice
            create_swap_choice=${create_swap_choice:-Y}
            
            if [[ $create_swap_choice =~ ^[Yy]$ ]]; then
                create_swap
                if [ $? -ne 0 ]; then
                    echo -e "${Warning} Swap 创建失败，继续安装可能会失败"
                    read -p "是否继续安装? [y/N]: " continue_choice
                    [[ ! $continue_choice =~ ^[Yy]$ ]] && return 1
                fi
            else
                echo -e "${Warning} 跳过 Swap 创建，继续安装..."
            fi
        else
            echo -e "${Info} 已有 Swap: ${total_swap}MB"
        fi
        echo -e ""
    fi
    
    install_deps || return 1
    download_wgcf || return 1
    register_warp || return 1
    generate_config || return 1
    start_warp
    
    echo -e ""
    echo -e "${Info} WARP 安装完成!"
}

# ==================== WireProxy 安装 (容器模式) ====================
# 适合容器环境和小内存服务器，不需要内核模块
WIREPROXY_VERSION="1.0.9"
WIREPROXY_BIN="/usr/local/bin/wireproxy"
WIREPROXY_CONFIG="/etc/wireproxy/config.toml"
WIREPROXY_SERVICE="/etc/systemd/system/wireproxy.service"

# 手动输入配置
manual_config_input() {
    local wgcf_dir="/tmp/wgcf_config"
    mkdir -p "$wgcf_dir"
    
    echo -e ""
    echo -e "${Info} ===== 手动配置模式 ====="
    echo -e "${Tip} 请粘贴 WireGuard 配置内容 (粘贴完成后输入 EOF 并回车):"
    echo -e "${Tip} 格式示例:"
    echo -e " [Interface]"
    echo -e " PrivateKey = ..."
    echo -e " Address = ..."
    echo -e " [Peer]"
    echo -e " PublicKey = ..."
    echo -e " Endpoint = ..."
    echo -e ""
    
    local config_content=""
    while IFS= read -r line; do
        [[ "$line" == "EOF" ]] && break
        config_content+="$line"$'\n'
    done
    
    if [ -z "$config_content" ]; then
        echo -e "${Error} 配置内容为空"
        return 1
    fi
    
    echo "$config_content" > "$wgcf_dir/wgcf-profile.conf"
    echo -e "${Info} 配置已保存"
    return 0
}

# 尝试导入本地配置
try_import_local_config() {
    local wgcf_dir="/tmp/wgcf_config"
    mkdir -p "$wgcf_dir"
    
    local found_configs=()
    local search_paths=(
        "/etc/wireguard/wgcf-profile.conf"
        "/usr/local/bin/warp.conf"
        "/root/warp-go/warp.conf"
        "$HOME/sing-box-yg-main/ygkkkkeys.txt"
        "/etc/s-box/ygkkkkeys.txt"
        "ygkkkkeys.txt"
    )
    
    for path in "${search_paths[@]}"; do
        if [ -f "$path" ]; then
            found_configs+=("$path")
        fi
    done
    
    if [ ${#found_configs[@]} -gt 0 ]; then
        echo -e ""
        echo -e "${Green}检测到本地已有配置文件:${Reset}"
        for i in "${!found_configs[@]}"; do
            echo -e " ${Green}$((i+1)).${Reset} ${found_configs[$i]}"
        done
        echo -e " ${Green}0.${Reset} 不使用，切换到手动输入"
        echo -e ""
        
        read -p "请选择 [0-${#found_configs[@]}]: " choice
        
        if [[ "$choice" =~ ^[1-9][0-9]*$ && "$choice" -le "${#found_configs[@]}" ]]; then
            local selected="${found_configs[$((choice-1))]}"
            echo -e "${Info} 正在导入: $selected"
            cat "$selected" > "$wgcf_dir/wgcf-profile.conf"
            
            # 简单检查
            if grep -q "PrivateKey" "$wgcf_dir/wgcf-profile.conf"; then
                echo -e "${Info} 导入成功"
                return 0
            else
                echo -e "${Error} 文件似乎不是有效的 WireGuard 配置"
            fi
        fi
    fi
    return 1
}

install_wireproxy() {
    echo -e "${Info} ===== WireProxy 安装模式 ====="
    echo -e "${Tip} 此模式适合容器环境和小内存服务器"
    echo -e "${Tip} 不需要 WireGuard 内核模块，创建本地 SOCKS5 代理"
    echo -e ""
    
    # 检测架构
    local arch_type="amd64"
    local wgcf_arch="amd64"
    case "$(uname -m)" in
        x86_64|amd64) arch_type="amd64"; wgcf_arch="amd64" ;;
        aarch64|arm64) arch_type="arm64"; wgcf_arch="arm64" ;;
        armv7l) arch_type="arm"; wgcf_arch="armv7" ;;
    esac
    
    # ========== 步骤1: 下载 wgcf ==========
    echo -e "${Green}步骤 1/4: 下载 wgcf${Reset}"
    
    local wgcf_tmp="/tmp/wgcf"
    local wgcf_url="https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VERSION}/wgcf_${WGCF_VERSION}_linux_${wgcf_arch}"
    
    echo -e "${Info} 下载 wgcf v${WGCF_VERSION}..."
    if curl -sL "$wgcf_url" -o "$wgcf_tmp" && [ -s "$wgcf_tmp" ]; then
        chmod +x "$wgcf_tmp"
        echo -e "${Info} wgcf 下载成功"
    else
        echo -e "${Error} wgcf 下载失败"
        return 1
    fi
    
    # ========== 步骤2: 注册 WARP 账户 ==========
    echo -e ""
    echo -e "${Green}步骤 2/4: 注册 WARP 账户${Reset}"
    
    local wgcf_dir="/tmp/wgcf_config"
    rm -rf "$wgcf_dir"  # 清理旧数据，防止残留干扰
    mkdir -p "$wgcf_dir"
    cd "$wgcf_dir"
    
    echo -e "${Info} 注册 WARP 账户..."
    
    # 注册账户 (重试5次)
    local max_retries=5
    local retry=0
    local log_file="/tmp/wgcf_register.log"
    
    while [ $retry -lt $max_retries ]; do
        # 使用临时文件记录日志，避免管道导致的问题
        yes | "$wgcf_tmp" register --accept-tos > "$log_file" 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "${Info} WARP 账户注册成功"
            break
        fi
        
        retry=$((retry + 1))
        echo -e "${Warning} 注册失败，重试 $retry/$max_retries..."
        
        # 显示关键错误信息
        if grep -q "429" "$log_file"; then
            echo -e "${Yellow} 原因: 请求过多 (HTTP 429)，等待 5 秒...${Reset}"
            sleep 5
        elif grep -q "network" "$log_file"; then
            echo -e "${Yellow} 原因: 网络连接失败${Reset}"
            sleep 2
        else
            local err_msg=$(tail -n 1 "$log_file")
            echo -e "${Yellow} 错误详情: ${err_msg}${Reset}"
            sleep 2
        fi
    done
    
    if [ ! -f "$wgcf_dir/wgcf-account.toml" ]; then
        echo -e "${Error} 账户注册失败"
        echo -e ""
        echo -e "${Tip} 自动注册遇到问题..."
        
        # 优先尝试导入本地配置
        if try_import_local_config; then
             echo -e "${Info} 已使用本地配置，跳过注册"
             # 跳过后续 generate 步骤，直接去解析配置
             # 但是我们怎么跳过 generate？
             # 我们可以创建一个标记文件，或者重构逻辑。
             # 简单办法：创建一个假的 wgcf-account.toml 和 wgcf-profile.conf (后者已经有了)
             touch "$wgcf_dir/wgcf-account.toml"
        else
            echo -e "${Tip} 您可以选择切换到手动输入配置模式"
            echo -e "${Tip} 需要您在其他机器上生成 WireGuard 配置 (PrivateKey, Address 等)"
            echo -e ""
            read -p "切换到手动模式? [y/N]: " manual_mode
            
            if [[ $manual_mode =~ ^[Yy]$ ]]; then
                manual_config_input
                # 如果手动输入成功，我们需要确保后续逻辑能跑通
                # 手动输入已经创建了 wgcf-profile.conf
                if [ $? -eq 0 ]; then
                    touch "$wgcf_dir/wgcf-account.toml" # 标记为成功
                else
                    return 1
                fi
            else
                rm -rf "$wgcf_dir" "$wgcf_tmp"
                return 1
            fi
        fi
    fi
    
    # 生成配置 (仅当 wgcf-profile.conf 不存在时)
    if [ ! -f "$wgcf_dir/wgcf-profile.conf" ]; then
        echo -e "${Info} 生成 WireGuard 配置..."
        if ! "$wgcf_tmp" generate >/dev/null 2>&1; then
            echo -e "${Error} 配置生成失败"
            
            # 如果生成失败，也提供手动模式
            echo -e ""
            read -p "切换到手动模式? [y/N]: " manual_mode
            if [[ $manual_mode =~ ^[Yy]$ ]]; then
                manual_config_input
                if [ $? -ne 0 ]; then
                    rm -rf "$wgcf_dir" "$wgcf_tmp"
                    return 1
                fi
            else
                rm -rf "$wgcf_dir" "$wgcf_tmp"
                return 1
            fi
        fi
    fi
    
    if [ ! -f "$wgcf_dir/wgcf-profile.conf" ]; then
        echo -e "${Error} 配置文件未生成"
        rm -rf "$wgcf_dir" "$wgcf_tmp"
        return 1
    fi
    
    echo -e "${Info} WireGuard 配置生成成功"
    
    # ========== 步骤3: 下载 WireProxy ==========
    echo -e ""
    echo -e "${Green}步骤 3/4: 下载 WireProxy${Reset}"
    
    local wireproxy_url="https://github.com/whyvl/wireproxy/releases/download/v${WIREPROXY_VERSION}/wireproxy_linux_${arch_type}.tar.gz"
    local tmp_file="/tmp/wireproxy.tar.gz"
    
    echo -e "${Info} 下载 WireProxy v${WIREPROXY_VERSION} (${arch_type})..."
    
    if curl -sL "$wireproxy_url" -o "$tmp_file"; then
        cd /tmp
        tar -xzf "$tmp_file" 2>/dev/null
        
        if [ -f /tmp/wireproxy ]; then
            mv /tmp/wireproxy "$WIREPROXY_BIN"
            chmod +x "$WIREPROXY_BIN"
            rm -f "$tmp_file"
            echo -e "${Info} WireProxy 安装成功"
        else
            echo -e "${Error} 解压失败"
            rm -rf "$wgcf_dir" "$wgcf_tmp"
            return 1
        fi
    else
        echo -e "${Error} 下载失败"
        rm -rf "$wgcf_dir" "$wgcf_tmp"
        return 1
    fi
    
    # ========== 步骤4: 创建配置和服务 ==========
    echo -e ""
    echo -e "${Green}步骤 4/4: 创建配置和服务${Reset}"
    
    mkdir -p /etc/wireproxy
    
    # 读取 wgcf 生成的配置并转换为 WireProxy 格式
    # 读取 wgcf 生成的配置并转换为 WireProxy 格式
    local private_key=$(grep "PrivateKey" "$wgcf_dir/wgcf-profile.conf" | awk '{print $3}')
    local address_v4=$(grep "Address" "$wgcf_dir/wgcf-profile.conf" | head -1 | awk '{print $3}')
    local address_v6=$(grep "Address" "$wgcf_dir/wgcf-profile.conf" | tail -1 | awk '{print $3}')
    local public_key=$(grep "PublicKey" "$wgcf_dir/wgcf-profile.conf" | awk '{print $3}')
    
    # 优化 Endpoint 选择 (参考 yonggekkk 脚本)
    local endpoint=""
    
    # 检测网络环境
    local has_ipv4=false
    local has_ipv6=false
    curl -s4m2 https://www.cloudflare.com/cdn-cgi/trace -k | grep -q "warp" && has_ipv4=true
    curl -s6m2 https://www.cloudflare.com/cdn-cgi/trace -k | grep -q "warp" && has_ipv6=true
    
    # 如果检测失败，尝试使用 ip route
    if [ "$has_ipv4" = false ] && [ "$has_ipv6" = false ]; then
        ip -4 route show default | grep -q default && has_ipv4=true
        ip -6 route show default | grep -q default && has_ipv6=true
    fi

    if [ "$has_ipv6" = true ] && [ "$has_ipv4" = false ]; then
        # 纯 IPv6 环境
        echo -e "${Info} 检测到纯 IPv6 环境，使用 IPv6 Endpoint"
        endpoint="[2606:4700:d0::a29f:c001]:2408"
    else
        # IPv4 或 双栈环境，使用通用域名或 IPv4 Endpoint
        echo -e "${Info} 使用 Cloudflare 通用 Endpoint"
        # 备选: 162.159.192.1:2408 (yonggekkk 优选)
        # 备选: engage.cloudflareclient.com:2408 (官方域名)
        endpoint="engage.cloudflareclient.com:2408"
    fi
    
    # 如果获取不到地址，给个默认值
    [ -z "$address_v4" ] && address_v4="172.16.0.2/32"
    [ -z "$address_v6" ] && address_v6="2606:4700:110:8f1a:c53:a4c5:2249:1546/128"
    
    # 创建 WireProxy 配置
    cat > "$WIREPROXY_CONFIG" << WIREPROXY_EOF
[Interface]
PrivateKey = ${private_key}
Address = ${address_v4}
Address = ${address_v6}
DNS = 1.1.1.1
DNS = 2606:4700:4700::1111
MTU = 1280

[Peer]
PublicKey = ${public_key}
AllowedIPs = 0.0.0.0/0
AllowedIPs = ::/0
Endpoint = ${endpoint}

# SOCKS5 代理配置
[Socks5]
BindAddress = 127.0.0.1:1080
WIREPROXY_EOF
    
    echo -e "${Info} 配置文件已创建: $WIREPROXY_CONFIG"
    
    # 创建 systemd 服务
    cat > "$WIREPROXY_SERVICE" << SERVICE_EOF
[Unit]
Description=WireProxy SOCKS5 Client
After=network.target

[Service]
Type=simple
WorkingDirectory=/etc/wireproxy
ExecStart=$WIREPROXY_BIN -c config.toml
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE_EOF
    
    systemctl daemon-reload
    systemctl enable wireproxy 2>/dev/null
    systemctl start wireproxy
    
    # 清理临时文件
    rm -rf "$wgcf_dir" "$wgcf_tmp"
    
    sleep 2
    
    # 验证
    if systemctl is-active wireproxy &>/dev/null; then
        echo -e "${Info} WireProxy 服务已启动"
        
        # 测试代理
        echo -e ""
        echo -e "${Info} 测试代理连接..."
        sleep 3
        local test_ip=$(curl -sx socks5h://127.0.0.1:1080 ip.sb --connect-timeout 10 2>/dev/null)
        
        if [ -n "$test_ip" ]; then
            echo -e "${Info} 代理测试成功!"
            echo -e "${Info} 出口 IP: ${Cyan}${test_ip}${Reset}"
        else
            echo -e "${Warning} 代理测试暂未成功，可能需要等待几秒"
            echo -e "${Tip} 手动测试: curl -x socks5h://127.0.0.1:1080 ip.sb"
        fi
    else
        echo -e "${Error} WireProxy 服务启动失败"
        echo -e "${Tip} 查看日志: journalctl -u wireproxy -f"
        return 1
    fi
    
    echo -e ""
    echo -e "${Info} ===== WireProxy 安装完成 ====="
    echo -e ""
    echo -e " SOCKS5 代理: ${Cyan}127.0.0.1:1080${Reset}"
    echo -e ""
    echo -e " 服务管理:"
    echo -e "   启动: systemctl start wireproxy"
    echo -e "   停止: systemctl stop wireproxy"
    echo -e "   状态: systemctl status wireproxy"
    echo -e ""
    echo -e " 配置文件: $WIREPROXY_CONFIG"
    echo -e ""
    
    # 询问是否配置 sing-box 出口代理
    echo -e "${Tip} 是否为 sing-box 启用 WARP 出口代理?"
    echo -e "     (让 sing-box 的流量通过 WARP 出站)"
    echo -e ""
    read -p "配置 sing-box 出口代理? [y/N]: " config_singbox
    
    if [[ $config_singbox =~ ^[Yy]$ ]]; then
        configure_singbox_warp_outbound
    fi
}

# 配置 sing-box WARP 出口代理
configure_singbox_warp_outbound() {
    echo -e ""
    echo -e "${Info} 配置 sing-box WARP 出口代理..."
    
    # 检查 sing-box 配置文件
    local singbox_config=""
    local possible_paths=(
        "$HOME/.vps-play/singbox/config.json"
        "/etc/sing-box/config.json"
        "/usr/local/etc/sing-box/config.json"
    )
    
    for path in "${possible_paths[@]}"; do
        if [ -f "$path" ]; then
            singbox_config="$path"
            break
        fi
    done
    
    if [ -z "$singbox_config" ]; then
        echo -e "${Warning} 未找到 sing-box 配置文件"
        echo -e "${Tip} 请手动添加以下出站配置到 sing-box:"
        echo -e ""
        echo -e "${Cyan}"
        cat << 'SINGBOX_EXAMPLE'
{
  "outbounds": [
    {
      "type": "socks",
      "tag": "warp-out",
      "server": "127.0.0.1",
      "server_port": 1080
    }
  ],
  "route": {
    "final": "warp-out"
  }
}
SINGBOX_EXAMPLE
        echo -e "${Reset}"
        return 0
    fi
    
    echo -e "${Info} 找到配置文件: $singbox_config"
    
    # 备份原配置
    cp "$singbox_config" "${singbox_config}.bak.$(date +%Y%m%d%H%M%S)"
    echo -e "${Info} 已备份原配置"
    
    # 检查是否已有 warp 出站
    if grep -q '"tag".*:.*"warp' "$singbox_config" 2>/dev/null; then
        echo -e "${Warning} 配置中已存在 WARP 相关出站"
        read -p "是否覆盖? [y/N]: " overwrite
        [[ ! $overwrite =~ ^[Yy]$ ]] && return 0
    fi
    
    # 检查是否有 jq
    if ! command -v jq &>/dev/null; then
        echo -e "${Warning} 未安装 jq，无法自动修改配置"
        echo -e "${Tip} 请手动添加以下出站配置:"
        echo -e ""
        echo -e "${Cyan}"
        cat << 'MANUAL_CONFIG'
在 "outbounds" 数组中添加:
{
  "type": "socks",
  "tag": "warp-out",
  "server": "127.0.0.1",
  "server_port": 1080
}

将 "route" 中的 "final" 改为 "warp-out"
MANUAL_CONFIG
        echo -e "${Reset}"
        return 0
    fi
    
    # 使用 jq 添加 WARP 出站
    local warp_outbound='{"type":"socks","tag":"warp-out","server":"127.0.0.1","server_port":1080}'
    
    # 添加出站并设置为 final
    local new_config=$(jq --argjson warp "$warp_outbound" '
        # 添加 warp 出站到 outbounds 数组
        .outbounds = (.outbounds // []) + [$warp] |
        # 如果没有 route，创建一个
        .route = (.route // {}) |
        # 设置 final 为 warp-out
        .route.final = "warp-out"
    ' "$singbox_config" 2>/dev/null)
    
    if [ -n "$new_config" ]; then
        echo "$new_config" > "$singbox_config"
        echo -e "${Info} sing-box 配置已更新"
        
        # 重启 sing-box
        echo -e "${Info} 重启 sing-box..."
        if systemctl restart sing-box 2>/dev/null; then
            echo -e "${Info} sing-box 已重启"
        elif pgrep -x sing-box &>/dev/null; then
            pkill -HUP sing-box 2>/dev/null
            echo -e "${Info} 已发送重载信号"
        fi
        
        echo -e ""
        echo -e "${Info} sing-box 现在通过 WARP 出站"
        echo -e "${Tip} 所有 sing-box 的流量都会使用 Cloudflare IP"
    else
        echo -e "${Error} 配置修改失败"
        echo -e "${Tip} 请手动编辑: $singbox_config"
    fi
}

# ==================== WARP+ 升级 ====================
upgrade_warp_plus() {
    echo -e "${Info} WARP+ 升级"
    echo -e "${Tip} 需要 WARP+ 许可证密钥"
    echo -e ""
    
    read -p "输入 WARP+ 许可证密钥: " license_key
    
    if [ -z "$license_key" ]; then
        echo -e "${Error} 密钥不能为空"
        return 1
    fi
    
    if [ ! -f "$WGCF_ACCOUNT" ]; then
        echo -e "${Error} 请先注册 WARP 账户"
        return 1
    fi
    
    cd "$WARP_DIR"
    
    echo -e "${Info} 升级到 WARP+..."
    
    if $WGCF_BIN update --license "$license_key" 2>/dev/null; then
        echo -e "${Info} WARP+ 升级成功"
        
        # 重新生成配置
        generate_config
        
        # 重启 WARP
        if wg show wgcf &>/dev/null 2>&1; then
            restart_warp
        fi
        
        return 0
    else
        echo -e "${Error} 升级失败，请检查许可证密钥"
        return 1
    fi
}

# ==================== 流媒体解锁检测 ====================
check_streaming() {
    echo -e "${Info} 检测流媒体解锁状态..."
    echo -e ""
    
    # Netflix
    echo -n " Netflix: "
    local nf=$(curl -sLm5 "https://www.netflix.com/title/81215567" 2>/dev/null)
    if echo "$nf" | grep -q "NSEZ-403"; then
        echo -e "${Red}未解锁${Reset}"
    elif echo "$nf" | grep -qE "page-title|Netflix"; then
        echo -e "${Green}已解锁${Reset}"
    else
        echo -e "${Yellow}检测超时${Reset}"
    fi
    
    # YouTube Premium
    echo -n " YouTube: "
    local yt=$(curl -sLm5 "https://www.youtube.com/premium" 2>/dev/null)
    if echo "$yt" | grep -q "Premium is not available"; then
        echo -e "${Red}无 Premium${Reset}"
    else
        echo -e "${Green}可访问${Reset}"
    fi
    
    # ChatGPT
    echo -n " ChatGPT: "
    local gpt=$(curl -sLm5 "https://chat.openai.com/" -H "User-Agent: Mozilla/5.0" 2>/dev/null)
    if echo "$gpt" | grep -qE "Sorry|unavailable|blocked"; then
        echo -e "${Red}不可用${Reset}"
    else
        echo -e "${Green}可访问${Reset}"
    fi
    
    # Google
    echo -n " Google:  "
    if curl -sLm5 "https://www.google.com" &>/dev/null; then
        echo -e "${Green}可访问${Reset}"
    else
        echo -e "${Red}不可访问${Reset}"
    fi
}

# ==================== 主菜单 ====================
show_warp_menu() {
    check_system
    
    # Serv00/HostUno 环境检测
    local is_serv00=false
    if [ -f /etc/os-release ]; then
        grep -qi "serv00\|hostuno" /etc/os-release 2>/dev/null && is_serv00=true
    fi
    # 通过主机名检测
    hostname 2>/dev/null | grep -qiE "serv00|hostuno" && is_serv00=true
    # 通过 devil 命令检测
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
        echo -e " 原因: WARP 需要 WireGuard 内核模块和 root 权限"
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
EOF
        echo -e "${Reset}"
        
        # 显示状态
        if wg show wgcf &>/dev/null 2>&1; then
            echo -e " 状态: ${Green}运行中${Reset}"
        else
            echo -e " 状态: ${Yellow}未运行${Reset}"
        fi
        
        if [ -f "$WGCF_ACCOUNT" ]; then
            echo -e " 账户: ${Green}已注册${Reset}"
        else
            echo -e " 账户: ${Red}未注册${Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== WARP 管理 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  一键安装 WARP ${Yellow}(传统模式)${Reset}"
        echo -e " ${Green}2.${Reset}  一键安装 WARP ${Cyan}(WireProxy 容器模式)${Reset}"
        echo -e " ${Green}3.${Reset}  卸载 WARP"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}4.${Reset}  下载 wgcf"
        echo -e " ${Green}5.${Reset}  注册账户"
        echo -e " ${Green}6.${Reset}  生成配置"
        echo -e " ${Green}7.${Reset}  升级 WARP+"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}8.${Reset}  启动 WARP"
        echo -e " ${Green}9.${Reset}  停止 WARP"
        echo -e " ${Green}10.${Reset} 重启 WARP"
        echo -e " ${Green}11.${Reset} 查看状态"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}12.${Reset} 查看当前 IP"
        echo -e " ${Green}13.${Reset} 流媒体解锁检测"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}14.${Reset} ${Cyan}Swap 管理${Reset} (小内存必备)"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}========================================================${Reset}"
        
        read -p " 请选择 [0-14]: " choice
        
        case "$choice" in
            1) quick_install ;;
            2) install_wireproxy ;;
            3) uninstall_warp ;;
            4) download_wgcf ;;
            5) register_warp ;;
            6) generate_config ;;
            7) upgrade_warp_plus ;;
            8) start_warp ;;
            9) stop_warp ;;
            10) restart_warp ;;
            11) status_warp ;;
            12) show_ip ;;
            13) check_streaming ;;
            14) manage_swap_menu ;;
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
