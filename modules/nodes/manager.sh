#!/bin/bash
# 节点管理 (Hysteria 2 / TUIC v5 / Sing-box Reality)
# 包含一键集合安装、端口预配置、状态管理和日志查看功能
#
# Copyright (C) 2025 VPS-play Contributors

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"

# 引入基础库
[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/port_manager.sh" ] && source "$VPSPLAY_DIR/utils/port_manager.sh"

# 引入子模块 (Namespaced)
[ -f "$VPSPLAY_DIR/modules/hysteria/manager.sh" ] && source "$VPSPLAY_DIR/modules/hysteria/manager.sh"
[ -f "$VPSPLAY_DIR/modules/tuic/manager.sh" ] && source "$VPSPLAY_DIR/modules/tuic/manager.sh"
[ -f "$VPSPLAY_DIR/modules/singbox/manager.sh" ] && source "$VPSPLAY_DIR/modules/singbox/manager.sh"

# 颜色定义
if [ -z "$Green" ]; then
    Red="\033[31m"
    Green="\033[32m"
    Yellow="\033[33m"
    Cyan="\033[36m"
    Reset="\033[0m"
    Info="${Green}[信息]${Reset}"
    Error="${Red}[错误]${Reset}"
    Warning="${Yellow}[警告]${Reset}"
    Tip="${Yellow}[提示]${Reset}"
fi

# ==================== 服务状态检查 ====================
get_service_status() {
    local service=$1
    if systemctl is-active --quiet $service 2>/dev/null; then
        echo -e "${Green}运行中${Reset}"
    else
        echo -e "${Red}已停止${Reset}"
    fi
}

show_all_status() {
    clear
    echo -e "${Cyan}========== 节点运行状态 ==========${Reset}"
    echo -e ""
    
    # Hysteria 2
    echo -e " ${Cyan}Hysteria 2${Reset}"
    if [ -f "/usr/local/bin/hysteria" ]; then
        echo -e "   状态: $(get_service_status hysteria-server)"
        local hy_port=$(cat /etc/hysteria/config.yaml 2>/dev/null | grep "listen:" | awk -F: '{print $NF}')
        [ -n "$hy_port" ] && echo -e "   端口: ${Yellow}$hy_port${Reset}"
    else
        echo -e "   状态: ${Yellow}未安装${Reset}"
    fi
    echo -e ""
    
    # TUIC
    echo -e " ${Cyan}TUIC v5${Reset}"
    if [ -f "/usr/local/bin/tuic" ]; then
        echo -e "   状态: $(get_service_status tuic)"
        local tuic_port=$(cat /etc/tuic/tuic.json 2>/dev/null | grep -o '"server"[^,]*' | grep -oE '[0-9]+')
        [ -n "$tuic_port" ] && echo -e "   端口: ${Yellow}$tuic_port${Reset}"
    else
        echo -e "   状态: ${Yellow}未安装${Reset}"
    fi
    echo -e ""
    
    # Sing-box Reality
    echo -e " ${Cyan}Sing-box Reality${Reset}"
    if command -v sing-box &>/dev/null; then
        echo -e "   状态: $(get_service_status sing-box)"
        local sb_port=$(cat /etc/sing-box/config.json 2>/dev/null | grep listen_port | awk -F: '{print $2}' | tr -d ' ,')
        [ -n "$sb_port" ] && echo -e "   端口: ${Yellow}$sb_port${Reset}"
    else
        echo -e "   状态: ${Yellow}未安装${Reset}"
    fi
    echo -e ""
}

# ==================== 服务控制 ====================
control_all_services() {
    local action=$1
    local action_name=""
    
    case $action in
        start) action_name="启动" ;;
        stop) action_name="停止" ;;
        restart) action_name="重启" ;;
    esac
    
    echo -e "${Info} 正在${action_name}所有节点服务..."
    
    # Hysteria
    if [ -f "/usr/local/bin/hysteria" ]; then
        systemctl $action hysteria-server 2>/dev/null && echo -e "  Hysteria 2: ${Green}${action_name}成功${Reset}" || echo -e "  Hysteria 2: ${Yellow}未运行${Reset}"
    fi
    
    # TUIC
    if [ -f "/usr/local/bin/tuic" ]; then
        systemctl $action tuic 2>/dev/null && echo -e "  TUIC v5: ${Green}${action_name}成功${Reset}" || echo -e "  TUIC v5: ${Yellow}未运行${Reset}"
    fi
    
    # Sing-box
    if command -v sing-box &>/dev/null; then
        systemctl $action sing-box 2>/dev/null && echo -e "  Sing-box: ${Green}${action_name}成功${Reset}" || echo -e "  Sing-box: ${Yellow}未运行${Reset}"
    fi
    
    echo -e "${Info} ${action_name}操作完成"
}

service_control_menu() {
    clear
    echo -e "${Cyan}========== 服务控制 ==========${Reset}"
    echo -e ""
    echo -e " ${Green}1.${Reset} 启动所有节点"
    echo -e " ${Green}2.${Reset} 停止所有节点"
    echo -e " ${Green}3.${Reset} 重启所有节点"
    echo -e " ${Green}0.${Reset} 返回"
    echo -e ""
    read -p "请选择: " choice
    
    case "$choice" in
        1) control_all_services start ;;
        2) control_all_services stop ;;
        3) control_all_services restart ;;
        0) return ;;
        *) echo -e "${Error} 无效选择" ;;
    esac
}

# ==================== 日志管理 ====================
view_logs_menu() {
    clear
    echo -e "${Cyan}========== 日志管理 ==========${Reset}"
    echo -e ""
    echo -e " ${Green}1.${Reset} 查看 Hysteria 2 日志"
    echo -e " ${Green}2.${Reset} 查看 TUIC v5 日志"
    echo -e " ${Green}3.${Reset} 查看 Sing-box 日志"
    echo -e " ${Green}4.${Reset} 查看所有日志 (实时)"
    echo -e " ${Green}0.${Reset} 返回"
    echo -e ""
    echo -e "${Tip} 按 Ctrl+C 退出日志查看"
    echo -e ""
    read -p "请选择: " choice
    
    case "$choice" in
        1)
            echo -e "${Info} 查看 Hysteria 2 日志 (最近 50 行)..."
            journalctl -u hysteria-server -n 50 --no-pager
            ;;
        2)
            echo -e "${Info} 查看 TUIC v5 日志 (最近 50 行)..."
            journalctl -u tuic -n 50 --no-pager
            ;;
        3)
            echo -e "${Info} 查看 Sing-box 日志 (最近 50 行)..."
            journalctl -u sing-box -n 50 --no-pager
            ;;
        4)
            echo -e "${Info} 实时查看所有节点日志 (按 Ctrl+C 退出)..."
            journalctl -u hysteria-server -u tuic -u sing-box -f
            ;;
        0) return ;;
        *) echo -e "${Error} 无效选择" ;;
    esac
}

# ==================== 端口预配置 ====================
preconfigure_ports() {
    local choices=("$@")
    
    echo -e ""
    echo -e "${Cyan}========== 端口预配置 ==========${Reset}"
    echo -e "${Info} 请为选中的协议设置端口 (回车使用默认值)"
    echo -e ""
    
    # 清除旧值
    export HY2_PORT=""
    export TUIC_PORT=""
    export SB_PORT=""
    
    for choice in "${choices[@]}"; do
        case "$choice" in
            1|hy2|hysteria)
                read -p "Hysteria 2 端口 [默认443]: " hp
                export HY2_PORT=${hp:-443}
                echo -e "${Info} Hysteria 2 将使用端口: $HY2_PORT"
                ;;
            2|tuic)
                read -p "TUIC v5 端口 [默认8443]: " tp
                export TUIC_PORT=${tp:-8443}
                echo -e "${Info} TUIC v5 将使用端口: $TUIC_PORT"
                ;;
            3|reality|sb)
                read -p "Sing-box Reality 端口 [回车随机]: " sp
                if [ -n "$sp" ]; then
                    export SB_PORT=$sp
                    echo -e "${Info} Reality 将使用端口: $SB_PORT"
                else
                    echo -e "${Info} Reality 将使用随机端口"
                fi
                ;;
        esac
    done
    
    echo -e ""
}

# ==================== 一键集合安装 ====================
combo_install() {
    clear
    echo -e "${Cyan}========== 一键集合安装 (全部协议) ==========${Reset}"
    echo -e ""
    echo -e "${Info} 即将安装以下协议:"
    echo -e "  ${Green}1.${Reset} Hysteria 2"
    echo -e "  ${Green}2.${Reset} TUIC v5"
    echo -e "  ${Green}3.${Reset} Sing-box Reality"
    echo -e ""
    
    read -p "确定继续? [Y/n]: " confirm
    [[ ! $confirm =~ ^[Yy]?$ ]] && echo -e "${Warning} 已取消" && return
    
    # 预配置所有端口
    preconfigure_ports 1 2 3
    
    echo -e "${Info} 开始批量安装..."
    echo -e ""
    
    # 安装 Hysteria 2
    echo -e "${Cyan}[1/3] 安装 Hysteria 2...${Reset}"
    install_hysteria
    echo -e ""
    read -p "按回车继续安装下一个..."
    
    # 安装 TUIC
    echo -e "${Cyan}[2/3] 安装 TUIC v5...${Reset}"
    install_tuic
    echo -e ""
    read -p "按回车继续安装下一个..."
    
    # 安装 Reality
    echo -e "${Cyan}[3/3] 安装 Sing-box Reality...${Reset}"
    install_reality
    
    echo -e ""
    echo -e "${Green}========== 集合安装完成 ==========${Reset}"
    echo -e "${Info} 请检查各项服务的运行状态"
    echo -e ""
    
    # 显示所有分享链接
    show_all_configs
}

# ==================== 自定义混合安装 ====================
custom_mixed_install() {
    clear
    echo -e "${Cyan}========== 自定义混合搭建 ==========${Reset}"
    echo -e "请选择要安装的协议 (可多选):"
    echo -e " ${Green}1.${Reset} Hysteria 2"
    echo -e " ${Green}2.${Reset} TUIC v5"
    echo -e " ${Green}3.${Reset} Sing-box Reality"
    echo -e ""
    echo -e "${Tip} 输入数字并用空格分隔 (例如: 1 3 或 1 2 3)"
    read -p "请选择: " -a custom_choices
    
    if [ ${#custom_choices[@]} -eq 0 ]; then
        echo -e "${Warning} 未选择任何协议"
        return
    fi
    
    # 预配置端口
    preconfigure_ports "${custom_choices[@]}"
    
    echo -e "${Info} 开始批量安装..."
    
    local count=1
    local total=${#custom_choices[@]}
    
    for choice in "${custom_choices[@]}"; do
        case "$choice" in
            1)
                echo -e "${Cyan}[$count/$total] 安装 Hysteria 2...${Reset}"
                install_hysteria
                echo -e ""
                ;;
            2)
                echo -e "${Cyan}[$count/$total] 安装 TUIC v5...${Reset}"
                install_tuic
                echo -e ""
                ;;
            3)
                echo -e "${Cyan}[$count/$total] 安装 Sing-box Reality...${Reset}"
                install_reality
                echo -e ""
                ;;
            *)
                echo -e "${Warning} 无效选择: $choice (跳过)"
                ;;
        esac
        
        count=$((count + 1))
        
        if [ $count -le $total ]; then
            read -p "按回车继续下一个..."
        fi
    done
    
    echo -e "${Green}混合安装流程结束${Reset}"
    echo -e ""
    
    # 显示所有分享链接
    show_all_configs
}

# ==================== 卸载所有节点 ====================
uninstall_all_nodes() {
    echo -e "${Warning} 即将卸载所有节点协议 (Hy2, Tuic, Reality)"
    read -p "确定? [y/N]: " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        uninstall_hysteria 2>/dev/null
        uninstall_tuic 2>/dev/null
        uninstall_reality 2>/dev/null
        echo -e "${Green}全部卸载完成${Reset}"
    fi
}

# ==================== 查看所有配置和分享链接 ====================
show_all_configs() {
    echo -e ""
    echo -e "${Cyan}========== 节点配置和分享链接汇总 ==========${Reset}"
    echo -e ""
    
    local has_nodes=false
    
    # Hysteria 2
    if [ -f "/root/hy/url.txt" ]; then
        has_nodes=true
        echo -e "${Yellow}━━━━━━━━━━ Hysteria 2 ━━━━━━━━━━${Reset}"
        echo -e "${Green}分享链接:${Reset}"
        cat /root/hy/url.txt
        echo -e ""
    fi
    
    # TUIC
    if [ -f "/root/tuic/url.txt" ]; then
        has_nodes=true
        echo -e "${Yellow}━━━━━━━━━━ TUIC v5 ━━━━━━━━━━${Reset}"
        echo -e "${Green}分享链接:${Reset}"
        cat /root/tuic/url.txt
        echo -e ""
    fi
    
    # Sing-box Reality
    if [ -f "/root/sing-box/share-link.txt" ]; then
        has_nodes=true
        echo -e "${Yellow}━━━━━━━━━━ Sing-box Reality ━━━━━━━━━━${Reset}"
        echo -e "${Green}分享链接:${Reset}"
        cat /root/sing-box/share-link.txt
        echo -e ""
    fi
    
    if [ "$has_nodes" = false ]; then
        echo -e "${Warning} 未检测到已安装的节点"
    else
        echo -e "${Cyan}=============================================${Reset}"
        echo -e "${Info} 以上链接可直接导入客户端使用"
    fi
}

# ==================== 主菜单 ====================
nodes_menu() {
    while true; do
        clear
        echo -e "${Cyan}========== 节点管理 (Hysteria/TUIC/Reality) ==========${Reset}"
        echo -e ""
        echo -e " ${Yellow}单独管理${Reset}"
        echo -e " ${Green}1.${Reset} Hysteria 2 管理"
        echo -e " ${Green}2.${Reset} TUIC v5 管理"
        echo -e " ${Green}3.${Reset} Sing-box Reality"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}批量安装${Reset}"
        echo -e " ${Green}4.${Reset} ${Cyan}一键集合安装${Reset} (安装全部协议)"
        echo -e " ${Green}5.${Reset} 自定义混合搭建 (选择性安装)"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}运维管理${Reset}"
        echo -e " ${Green}6.${Reset} 查看运行状态"
        echo -e " ${Green}7.${Reset} 服务控制 (启动/停止/重启)"
        echo -e " ${Green}8.${Reset} 日志管理"
        echo -e " ${Green}9.${Reset} ${Cyan}查看所有分享链接${Reset}"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}10.${Reset} ${Red}卸载所有节点${Reset}"
        echo -e " ${Green}0.${Reset} 返回主菜单"
        echo -e "${Green}=================================================${Reset}"
        
        read -p "请选择: " choice
        
        case "$choice" in
            1) hy2_menu ;;
            2) tuic_menu ;;
            3) sb_menu ;;
            4) combo_install ;;
            5) custom_mixed_install ;;
            6) show_all_status ;;
            7) service_control_menu ;;
            8) view_logs_menu ;;
            9) show_all_configs ;;
            10) uninstall_all_nodes ;;
            0) break ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    nodes_menu
fi
