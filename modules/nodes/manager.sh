#!/bin/bash
# 节点管理 (Hysteria 2 / TUIC v5 / Sing-box Reality)
# 包含一键集合安装和端口预配置功能
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

# ==================== 主菜单 ====================
nodes_menu() {
    while true; do
        clear
        echo -e "${Cyan}========== 节点管理 (Hysteria/TUIC/Reality) ==========${Reset}"
        echo -e ""
        echo -e " ${Green}单独管理${Reset}"
        echo -e " ${Green}1.${Reset} Hysteria 2 管理 ${Yellow}(原生/Misaka)${Reset}"
        echo -e " ${Green}2.${Reset} TUIC v5 管理 ${Yellow}(原生/Misaka)${Reset}"
        echo -e " ${Green}3.${Reset} Sing-box Reality ${Yellow}(Misaka)${Reset}"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}批量操作${Reset}"
        echo -e " ${Green}4.${Reset} ${Cyan}一键集合安装${Reset} (安装全部协议)"
        echo -e " ${Green}5.${Reset} 自定义混合搭建 (选择性安装)"
        echo -e " ${Green}6.${Reset} ${Red}卸载所有节点${Reset}"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset} 返回主菜单"
        echo -e "${Green}=================================================${Reset}"
        
        read -p "请选择: " choice
        
        case "$choice" in
            1) hy2_menu ;;
            2) tuic_menu ;;
            3) sb_menu ;;
            4) combo_install ;;
            5) custom_mixed_install ;;
            6) uninstall_all_nodes ;;
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
