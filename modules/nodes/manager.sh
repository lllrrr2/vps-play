#!/bin/bash
# 节点管理 (Hysteria 2 / TUIC v5 / Sing-box Reality)
#
# Copyright (C) 2025 VPS-play Contributors

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"

# 引入基础库
[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/port_manager.sh" ] && source "$VPSPLAY_DIR/utils/port_manager.sh"
[ -f "$VPSPLAY_DIR/utils/process_manager.sh" ] && source "$VPSPLAY_DIR/utils/process_manager.sh"
[ -f "$VPSPLAY_DIR/utils/network.sh" ] && source "$VPSPLAY_DIR/utils/network.sh"

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
fi

custom_mixed_install() {
    clear
    echo -e "${Cyan}========== 自定义混合搭建 (Misaka Logic) ==========${Reset}"
    echo -e "请选择要安装的协议 (可多选):"
    echo -e " ${Green}1.${Reset} Hysteria 2"
    echo -e " ${Green}2.${Reset} TUIC v5"
    echo -e " ${Green}3.${Reset} Sing-box Reality"
    echo -e ""
    echo -e "${Tip} 输入数字并用空格分隔 (例如: 1 3 或 1 2 3)"
    read -p "请选择: " -a custom_choices
    
    for choice in "${custom_choices[@]}"; do
        case "$choice" in
            1)
                install_hysteria
                echo -e "${Info} 按回车继续下一个..."
                read
                ;;
            2)
                install_tuic
                echo -e "${Info} 按回车继续下一个..."
                read
                ;;
            3)
                install_reality
                echo -e "${Info} 按回车继续下一个..."
                read
                ;;
            *)
                echo -e "${Warning} 无效选择: $choice (跳过)"
                ;;
        esac
    done
    
    echo -e "${Green}混合安装流程结束${Reset}"
    echo -e "${Info} 请检查各项服务的运行状态"
}

uninstall_all_nodes() {
    echo -e "${Warning} 即将卸载所有节点协议 (Hy2, Tuic, Reality)"
    read -p "确定? [y/N]: " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        uninstall_hysteria
        uninstall_tuic
        uninstall_reality
        echo -e "${Green}全部卸载完成${Reset}"
    fi
}

nodes_menu() {
    while true; do
        clear
        echo -e "${Cyan}========== 节点管理 (Hysteria/TUIC/Reality) ==========${Reset}"
        echo -e " ${Green}1.${Reset} Hysteria 2 管理 ${Yellow}(原生/Misaka)${Reset}"
        echo -e " ${Green}2.${Reset} TUIC v5 管理 ${Yellow}(原生/Misaka)${Reset}"
        echo -e " ${Green}3.${Reset} Reality 管理 ${Yellow}(Sing-box/Misaka)${Reset}"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}4.${Reset} ${Cyan}自定义混合搭建${Reset} (批量安装)"
        echo -e " ${Green}5.${Reset} ${Red}卸载所有节点${Reset}"
        echo -e " ${Green}0.${Reset} 返回主菜单"
        echo -e "${Green}=================================================${Reset}"
        
        read -p "请选择: " choice
        
        case "$choice" in
            1) hy2_menu ;;
            2) tuic_menu ;;
            3) sb_menu ;;
            4) custom_mixed_install ;;
            5) uninstall_all_nodes ;;
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
