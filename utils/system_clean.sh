#!/bin/bash
# VPS-play 系统清理与重置工具
# 功能: 清理缓存/日志、系统重置、恢复初始状态
# 支持: 普通VPS、FreeBSD、Serv00/Hostuno

# 加载环境检测
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
VPSPLAY_DIR="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"

# 颜色定义
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

# VPS-play 数据目录
VPSPLAY_DATA="$HOME/.vps-play"

# ==================== 环境检测 ====================
detect_env() {
    # 检测操作系统
    OS_TYPE=$(uname -s)
    
    # 检测是否为 Serv00/Hostuno
    if command -v devil &>/dev/null; then
        ENV_TYPE="serv00"
    elif [ "$OS_TYPE" = "FreeBSD" ]; then
        ENV_TYPE="freebsd"
    else
        ENV_TYPE="linux"
    fi
    
    # 检测是否有 root 权限
    if [ "$(id -u)" = "0" ]; then
        HAS_ROOT=true
    else
        HAS_ROOT=false
    fi
}

# ==================== 磁盘使用情况 ====================
show_disk_usage() {
    echo -e "${Info} 当前磁盘使用情况:"
    if [ "$ENV_TYPE" = "serv00" ]; then
        # Serv00 使用 devil 查看配额
        devil disk show 2>/dev/null || df -h "$HOME" | tail -1 | awk '{ print "  使用: " $5 " (" $3 "/" $2 ")" }'
    else
        df -h | grep -vE '^Filesystem|tmpfs|cdrom|devfs' | awk '{ print "  " $5 " " $6 }'
    fi
}

# ==================== 清理功能 ====================
# 清理包管理器缓存 (Linux)
clean_package_cache() {
    echo -e "${Info} 清理包管理器缓存..."
    
    case "$ENV_TYPE" in
        linux)
            if command -v apt-get &>/dev/null; then
                [ "$HAS_ROOT" = true ] && apt-get clean && apt-get autoremove -y
                [ "$HAS_ROOT" = true ] && rm -rf /var/lib/apt/lists/*
                echo -e "  ✓ APT 缓存已清理"
            elif command -v yum &>/dev/null; then
                [ "$HAS_ROOT" = true ] && yum clean all
                echo -e "  ✓ YUM 缓存已清理"
            elif command -v dnf &>/dev/null; then
                [ "$HAS_ROOT" = true ] && dnf clean all
                echo -e "  ✓ DNF 缓存已清理"
            elif command -v apk &>/dev/null; then
                [ "$HAS_ROOT" = true ] && apk cache clean
                echo -e "  ✓ APK 缓存已清理"
            elif command -v pacman &>/dev/null; then
                [ "$HAS_ROOT" = true ] && pacman -Scc --noconfirm
                echo -e "  ✓ Pacman 缓存已清理"
            fi
            ;;
        freebsd)
            if command -v pkg &>/dev/null; then
                [ "$HAS_ROOT" = true ] && pkg clean -a -y
                echo -e "  ✓ PKG 缓存已清理"
            fi
            ;;
        serv00)
            echo -e "  ${Yellow}跳过: Serv00 无包管理器权限${Reset}"
            ;;
    esac
}

# 清理系统日志
clean_logs() {
    echo -e "${Info} 清理系统日志..."
    
    case "$ENV_TYPE" in
        linux)
            # 清理 journald 日志
            if command -v journalctl &>/dev/null && [ "$HAS_ROOT" = true ]; then
                journalctl --vacuum-time=1d 2>/dev/null
                journalctl --vacuum-size=50M 2>/dev/null
                echo -e "  ✓ Journal 日志已清理"
            fi
            
            # 清理 /var/log
            if [ "$HAS_ROOT" = true ]; then
                find /var/log -type f -name "*.gz" -delete 2>/dev/null
                find /var/log -type f -name "*.log.[0-9]" -delete 2>/dev/null
                find /var/log -type f -name "*.log" -size +50M -exec truncate -s 0 {} \; 2>/dev/null
                echo -e "  ✓ /var/log 已清理"
            fi
            ;;
        freebsd)
            if [ "$HAS_ROOT" = true ]; then
                find /var/log -type f -name "*.gz" -delete 2>/dev/null
                find /var/log -type f -name "*.bz2" -delete 2>/dev/null
                newsyslog -C 2>/dev/null
                echo -e "  ✓ 日志已清理"
            fi
            ;;
        serv00)
            # 清理用户目录下的日志
            find "$HOME" -type f -name "*.log" -size +10M -exec truncate -s 0 {} \; 2>/dev/null
            find "$HOME" -type f -name "*.log.[0-9]*" -delete 2>/dev/null
            rm -rf "$HOME/logs"/*.gz 2>/dev/null
            echo -e "  ✓ 用户日志已清理"
            ;;
    esac
}

# 清理临时文件
clean_temp() {
    echo -e "${Info} 清理临时文件..."
    
    case "$ENV_TYPE" in
        linux|freebsd)
            if [ "$HAS_ROOT" = true ]; then
                rm -rf /tmp/* 2>/dev/null
                rm -rf /var/tmp/* 2>/dev/null
            fi
            ;;
        serv00)
            rm -rf "$HOME/tmp"/* 2>/dev/null
            rm -rf /tmp/user-$(id -u)/* 2>/dev/null
            ;;
    esac
    
    # 清理通用临时文件
    rm -rf "$HOME/.cache"/* 2>/dev/null
    rm -rf "$HOME/.local/share/Trash"/* 2>/dev/null
    echo -e "  ✓ 临时文件已清理"
}

# 清理 Docker
clean_docker() {
    if command -v docker &>/dev/null; then
        echo -e "${Info} 清理 Docker..."
        docker system prune -a -f --volumes 2>/dev/null
        echo -e "  ✓ Docker 已清理"
    fi
}

# 清理 VPS-play 缓存
clean_vpsplay_cache() {
    echo -e "${Info} 清理 VPS-play 缓存..."
    
    # 清理日志
    rm -rf "$VPSPLAY_DATA"/*/*.log 2>/dev/null
    rm -rf "$VPSPLAY_DATA"/logs/* 2>/dev/null
    
    # 清理临时下载
    rm -rf "$VPSPLAY_DATA"/*/*.tar.gz 2>/dev/null
    rm -rf "$VPSPLAY_DATA"/*/*.zip 2>/dev/null
    
    echo -e "  ✓ VPS-play 缓存已清理"
}

# 综合清理
clean_system() {
    clear
    echo -e "${Cyan}==================== 系统清理 ====================${Reset}"
    show_disk_usage
    echo -e "${Cyan}---------------------------------------------------${Reset}"
    echo -e ""
    
    clean_package_cache
    clean_logs
    clean_temp
    clean_docker
    clean_vpsplay_cache
    
    echo -e ""
    echo -e "${Cyan}---------------------------------------------------${Reset}"
    echo -e "${Green}清理完成!${Reset}"
    show_disk_usage
    echo -e "${Cyan}===================================================${Reset}"
}

# ==================== 系统重置功能 ====================
# 重置 VPS-play (删除所有数据和配置)
reset_vpsplay() {
    echo -e ""
    echo -e "${Yellow}========== 重置 VPS-play ==========${Reset}"
    echo -e ""
    echo -e "${Warning} 此操作将删除 VPS-play 的所有数据和配置:"
    echo -e "  - 所有模块的配置文件"
    echo -e "  - 所有节点信息和分享链接"
    echo -e "  - 所有跳板服务器配置"
    echo -e "  - 证书和密钥文件"
    echo -e "  - 环境缓存"
    echo -e ""
    
    read -p "确定要重置 VPS-play? [y/N]: " confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && { echo -e "${Info} 已取消"; return 0; }
    
    read -p "再次确认，输入 'RESET' 继续: " confirm2
    [ "$confirm2" != "RESET" ] && { echo -e "${Info} 已取消"; return 0; }
    
    echo -e ""
    echo -e "${Info} 停止所有运行中的服务..."
    
    # 停止所有可能的服务
    pkill -f "sing-box" 2>/dev/null
    pkill -f "xray" 2>/dev/null
    pkill -f "gost" 2>/dev/null
    pkill -f "cloudflared" 2>/dev/null
    pkill -f "nezha-agent" 2>/dev/null
    pkill -f "frpc" 2>/dev/null
    pkill -f "frps" 2>/dev/null
    
    echo -e "${Info} 删除 VPS-play 数据目录..."
    rm -rf "$VPSPLAY_DATA"
    
    # 重新创建空目录
    mkdir -p "$VPSPLAY_DATA"
    
    echo -e ""
    echo -e "${Green}✓ VPS-play 已重置${Reset}"
    echo -e "${Tip} 所有模块需要重新安装和配置"
}

# 重置单个模块
reset_module() {
    echo -e ""
    echo -e "${Cyan}========== 重置单个模块 ==========${Reset}"
    echo -e ""
    echo -e " ${Green}1.${Reset}  sing-box 节点"
    echo -e " ${Green}2.${Reset}  Argo 节点"
    echo -e " ${Green}3.${Reset}  GOST 中转"
    echo -e " ${Green}4.${Reset}  Cloudflared 隧道"
    echo -e " ${Green}5.${Reset}  跳板服务器"
    echo -e " ${Green}6.${Reset}  哪吒监控"
    echo -e " ${Green}7.${Reset}  FRPC 客户端"
    echo -e " ${Green}0.${Reset}  返回"
    echo -e ""
    
    read -p "选择要重置的模块 [0-7]: " module_choice
    
    local module_name=""
    local module_dir=""
    local process_name=""
    
    case "$module_choice" in
        1) module_name="sing-box"; module_dir="singbox"; process_name="sing-box" ;;
        2) module_name="Argo"; module_dir="argo"; process_name="xray|cloudflared" ;;
        3) module_name="GOST"; module_dir="gost"; process_name="gost" ;;
        4) module_name="Cloudflared"; module_dir="cloudflared"; process_name="cloudflared" ;;
        5) module_name="跳板服务器"; module_dir="jumper"; process_name="" ;;
        6) module_name="哪吒监控"; module_dir="nezha"; process_name="nezha-agent" ;;
        7) module_name="FRPC"; module_dir="frpc"; process_name="frpc" ;;
        0) return 0 ;;
        *) echo -e "${Error} 无效选择"; return 1 ;;
    esac
    
    echo -e ""
    echo -e "${Warning} 即将重置 ${module_name} 模块"
    read -p "确定继续? [y/N]: " confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    # 停止进程
    if [ -n "$process_name" ]; then
        echo -e "${Info} 停止 ${module_name}..."
        pkill -f "$process_name" 2>/dev/null
    fi
    
    # 删除数据目录
    echo -e "${Info} 删除数据..."
    rm -rf "$VPSPLAY_DATA/$module_dir"
    
    echo -e "${Green}✓ ${module_name} 已重置${Reset}"
}

# 系统级重置 (危险)
reset_system_full() {
    echo -e ""
    echo -e "${Red}========== 系统完全重置 ==========${Reset}"
    echo -e ""
    echo -e "${Red}⚠️  警告: 这是一个危险操作!${Reset}"
    echo -e ""
    echo -e "此操作将尝试恢复系统到接近初始状态:"
    echo -e ""
    
    case "$ENV_TYPE" in
        linux)
            echo -e " - 删除所有用户安装的包"
            echo -e " - 删除用户 home 目录下的配置文件"
            echo -e " - 清理 cron 任务"
            echo -e " - 删除 systemd 自定义服务"
            ;;
        freebsd)
            echo -e " - 删除用户安装的包"
            echo -e " - 删除用户配置文件"
            echo -e " - 清理 cron 任务"
            ;;
        serv00)
            echo -e " - 停止所有用户进程"
            echo -e " - 删除所有用户端口"
            echo -e " - 删除用户 home 目录下的程序和配置"
            echo -e " - 清理 cron 任务"
            ;;
    esac
    
    echo -e ""
    echo -e "${Yellow}注意: 此操作不可恢复!${Reset}"
    echo -e ""
    
    read -p "确定要执行系统重置? [y/N]: " confirm1
    [[ ! $confirm1 =~ ^[Yy]$ ]] && { echo -e "${Info} 已取消"; return 0; }
    
    read -p "再次确认，输入 'RESET-SYSTEM' 继续: " confirm2
    [ "$confirm2" != "RESET-SYSTEM" ] && { echo -e "${Info} 已取消"; return 0; }
    
    echo -e ""
    echo -e "${Info} 开始系统重置..."
    
    case "$ENV_TYPE" in
        linux)
            reset_linux_system
            ;;
        freebsd)
            reset_freebsd_system
            ;;
        serv00)
            reset_serv00_system
            ;;
    esac
}

# Linux 系统重置
reset_linux_system() {
    echo -e "${Info} 重置 Linux 系统..."
    
    # 停止所有用户进程
    echo -e "${Info} 停止用户进程..."
    pkill -u $(whoami) -9 2>/dev/null || true
    
    # 清理 cron
    echo -e "${Info} 清理 cron 任务..."
    crontab -r 2>/dev/null || true
    
    # 删除 systemd 自定义服务 (需要 root)
    if [ "$HAS_ROOT" = true ]; then
        echo -e "${Info} 删除自定义 systemd 服务..."
        for service in sing-box gost cloudflared nezha-agent frpc frps; do
            systemctl stop "$service" 2>/dev/null
            systemctl disable "$service" 2>/dev/null
            rm -f "/etc/systemd/system/${service}.service" 2>/dev/null
        done
        systemctl daemon-reload 2>/dev/null
    fi
    
    # 删除用户目录下的程序和配置
    echo -e "${Info} 删除用户程序和配置..."
    rm -rf "$HOME/.vps-play"
    rm -rf "$HOME/vps-play"
    rm -rf "$HOME/.acme.sh"
    rm -rf "$HOME/.cloudflared"
    rm -rf "$HOME/bin/vps-play"
    rm -rf "$HOME/bin/sing-box"
    rm -rf "$HOME/bin/gost"
    
    # 清理 bashrc 中的别名
    sed -i '/vps-play/d' "$HOME/.bashrc" 2>/dev/null
    sed -i '/vps-play/d' "$HOME/.profile" 2>/dev/null
    
    echo -e "${Green}✓ Linux 系统重置完成${Reset}"
}

# FreeBSD 系统重置
reset_freebsd_system() {
    echo -e "${Info} 重置 FreeBSD 系统..."
    
    # 停止所有用户进程
    echo -e "${Info} 停止用户进程..."
    pkill -u $(whoami) -9 2>/dev/null || true
    
    # 清理 cron
    echo -e "${Info} 清理 cron 任务..."
    crontab -r 2>/dev/null || true
    
    # 删除用户目录下的程序和配置
    echo -e "${Info} 删除用户程序和配置..."
    rm -rf "$HOME/.vps-play"
    rm -rf "$HOME/vps-play"
    rm -rf "$HOME/.acme.sh"
    rm -rf "$HOME/.cloudflared"
    rm -rf "$HOME/bin/vps-play"
    
    # 清理 rc.d 自定义脚本 (需要 root)
    if [ "$HAS_ROOT" = true ]; then
        rm -f /usr/local/etc/rc.d/sing-box 2>/dev/null
        rm -f /usr/local/etc/rc.d/gost 2>/dev/null
    fi
    
    echo -e "${Green}✓ FreeBSD 系统重置完成${Reset}"
}

# Serv00/Hostuno 系统重置
reset_serv00_system() {
    echo -e "${Info} 重置 Serv00/Hostuno 系统..."
    
    # 停止所有用户进程
    echo -e "${Info} 停止所有用户进程..."
    pkill -u $(whoami) -9 2>/dev/null || true
    
    # 删除所有用户端口
    echo -e "${Info} 删除所有用户端口..."
    if command -v devil &>/dev/null; then
        # 获取所有端口列表并删除
        local ports=$(devil port list 2>/dev/null | grep -oE '[0-9]+' | sort -u)
        for port in $ports; do
            devil port del tcp "$port" 2>/dev/null
            devil port del udp "$port" 2>/dev/null
        done
        echo -e "  ✓ 端口已清理"
    fi
    
    # 清理 cron 任务
    echo -e "${Info} 清理 cron 任务..."
    crontab -r 2>/dev/null || true
    
    # 删除所有程序和配置
    echo -e "${Info} 删除用户程序和配置..."
    
    # 保留系统必要目录，删除其他
    local dirs_to_clean=(
        "$HOME/.vps-play"
        "$HOME/vps-play"
        "$HOME/.acme.sh"
        "$HOME/.cloudflared"
        "$HOME/domains/*/public_html/.well-known"
        "$HOME/bin"
        "$HOME/.local/bin"
        "$HOME/.npm"
        "$HOME/.config"
        "$HOME/.cache"
    )
    
    for dir in "${dirs_to_clean[@]}"; do
        rm -rf $dir 2>/dev/null
    done
    
    # 删除二进制文件
    find "$HOME" -maxdepth 2 -type f \( -name "sing-box" -o -name "gost" -o -name "cloudflared" -o -name "xray" -o -name "nezha-agent" -o -name "frpc" \) -delete 2>/dev/null
    
    # 清理 shell 配置
    for rcfile in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.cshrc" "$HOME/.zshrc"; do
        if [ -f "$rcfile" ]; then
            sed -i.bak '/vps-play/d' "$rcfile" 2>/dev/null
            sed -i.bak '/PATH.*bin/d' "$rcfile" 2>/dev/null
            rm -f "${rcfile}.bak" 2>/dev/null
        fi
    done
    
    echo -e ""
    echo -e "${Green}✓ Serv00/Hostuno 系统重置完成${Reset}"
    echo -e ""
    echo -e "${Tip} 建议重新登录 SSH 以刷新环境"
}

# ==================== 主菜单 ====================
show_clean_menu() {
    detect_env
    
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔═╗╦  ╔═╗╔═╗╔╗╔  ┬  ┬─┐┌─┐┌─┐┌─┐┌┬┐
    ║  ║  ║╣ ╠═╣║║║  ┼  ├┬┘├┤ └─┐├┤  │ 
    ╚═╝╩═╝╚═╝╩ ╩╝╚╝  ·  ┴└─└─┘└─┘└─┘ ┴ 
    系统清理与重置
EOF
        echo -e "${Reset}"
        
        echo -e " 当前环境: ${Cyan}${ENV_TYPE}${Reset}"
        [ "$HAS_ROOT" = true ] && echo -e " 权限: ${Green}root${Reset}" || echo -e " 权限: ${Yellow}普通用户${Reset}"
        echo -e ""
        
        echo -e "${Green}==================== 系统清理 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  一键清理 (推荐)"
        echo -e " ${Green}2.${Reset}  清理包管理器缓存"
        echo -e " ${Green}3.${Reset}  清理系统日志"
        echo -e " ${Green}4.${Reset}  清理临时文件"
        echo -e " ${Green}5.${Reset}  清理 Docker"
        echo -e " ${Green}6.${Reset}  清理 VPS-play 缓存"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}系统重置${Reset}"
        echo -e " ${Green}7.${Reset}  重置 VPS-play"
        echo -e " ${Green}8.${Reset}  重置单个模块"
        echo -e " ${Red}9.${Reset}  ${Red}系统完全重置${Reset} ${Yellow}(危险)${Reset}"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}10.${Reset} 查看磁盘使用"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}===================================================${Reset}"
        
        read -p " 请选择 [0-10]: " choice
        
        case "$choice" in
            1) clean_system ;;
            2) clean_package_cache; read -p "按回车继续..." ;;
            3) clean_logs; read -p "按回车继续..." ;;
            4) clean_temp; read -p "按回车继续..." ;;
            5) clean_docker; read -p "按回车继续..." ;;
            6) clean_vpsplay_cache; read -p "按回车继续..." ;;
            7) reset_vpsplay; read -p "按回车继续..." ;;
            8) reset_module; read -p "按回车继续..." ;;
            9) reset_system_full; read -p "按回车继续..." ;;
            10) show_disk_usage; read -p "按回车继续..." ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
    done
}

# 导出函数
export -f clean_system
export -f show_clean_menu

# 如果直接运行脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_clean_menu
fi

