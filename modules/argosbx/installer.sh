#!/bin/bash
# ArgosBX 安装器包装脚本
# 通过命令行参数调用 argosbx 脚本安装各类节点
# 支持: VLESS-Reality, Hysteria2, TUIC, XHTTP, AnyTLS, VMess-Argo, VLESS-WS-Argo 等

# 颜色定义
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Cyan="\033[36m"
Reset="\033[0m"
Info="${Green}[信息]${Reset}"
Error="${Red}[错误]${Reset}"
Warning="${Yellow}[警告]${Reset}"
Tip="${Cyan}[提示]${Reset}"

# ArgosBX 脚本地址
ARGOSBX_URL="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"

# 默认 CDN 优选域名 (用于 Argo 节点地址替换)
CDN_DOMAIN="cloudflare.182682.xyz"

# ==================== 显示 Logo ====================
show_logo() {
    clear
    echo -e "${Cyan}"
    cat << "EOF"
    ╔═╗╦═╗╔═╗╔═╗╔═╗╔╗ ═╗ ╦
    ╠═╣╠╦╝║ ╦║ ║╚═╗╠╩╗╔╩╦╝
    ╩ ╩╩╚═╚═╝╚═╝╚═╝╚═╝╩ ╚═
    ArgosBX 安装器
EOF
    echo -e "${Reset}"
}

# ==================== 协议选择变量 ====================
PORT_VLESS_REALITY=""
PORT_HYSTERIA2=""
PORT_TUIC=""
PORT_XHTTP=""
PORT_ANYTLS=""
PORT_VMESS_ARGO=""
PORT_VLESS_WS=""
ENABLE_WARP=""
CUSTOM_UUID=""
ARGO_DOMAIN=""
ARGO_AUTH=""

# ==================== 获取随机可用端口 ====================
get_random_port() {
    local min=${1:-10000}
    local max=${2:-65535}
    local port
    
    for i in {1..100}; do
        port=$((RANDOM % (max - min + 1) + min))
        if ! netstat -tuln 2>/dev/null | grep -q ":$port " && \
           ! ss -tuln 2>/dev/null | grep -q ":$port "; then
            echo "$port"
            return 0
        fi
    done
    
    # 如果找不到，返回随机端口
    echo $((RANDOM % (max - min + 1) + min))
}

# ==================== 选择协议 ====================
select_protocols() {
    echo -e ""
    echo -e "${Green}==================== 选择安装协议 ====================${Reset}"
    echo -e ""
    echo -e " ${Green}直连协议 (无需域名)${Reset}"
    echo -e " ${Green}1.${Reset}  VLESS-TCP-Reality      - Reality 协议"
    echo -e " ${Green}2.${Reset}  Hysteria2              - 高速 UDP 协议"
    echo -e " ${Green}3.${Reset}  TUIC v5                - 高速 UDP 协议"
    echo -e " ${Green}4.${Reset}  XHTTP-Reality-ENC      - XHTTP 加密协议"
    echo -e " ${Green}5.${Reset}  AnyTLS                 - 伪装 TLS 协议"
    echo -e ""
    echo -e " ${Cyan}Argo 隧道协议 (通过 Cloudflare)${Reset}"
    echo -e " ${Green}6.${Reset}  VMess-WS-Argo          - VMess WebSocket"
    echo -e " ${Green}7.${Reset}  VLESS-WS-Argo          - VLESS WebSocket"
    echo -e ""
    echo -e "${Green}======================================================${Reset}"
    echo -e ""
    echo -e " ${Yellow}提示: 输入多个数字用空格或逗号分隔，例如: 1 2 3 或 1,2,3${Reset}"
    echo -e ""
    
    read -p " 请选择要安装的协议 [1-7]: " choices
    
    # 将逗号替换为空格，支持两种分隔方式
    choices=$(echo "$choices" | tr ',' ' ')
    
    for choice in $choices; do
        case $choice in
            1)
                read -p " VLESS-Reality 端口 (留空自动分配): " port
                PORT_VLESS_REALITY="${port:-$(get_random_port 10000 20000)}"
                echo -e " ${Info} VLESS-Reality 端口: ${Cyan}${PORT_VLESS_REALITY}${Reset}"
                ;;
            2)
                read -p " Hysteria2 端口 (留空自动分配): " port
                PORT_HYSTERIA2="${port:-$(get_random_port 20001 30000)}"
                echo -e " ${Info} Hysteria2 端口: ${Cyan}${PORT_HYSTERIA2}${Reset}"
                ;;
            3)
                read -p " TUIC 端口 (留空自动分配): " port
                PORT_TUIC="${port:-$(get_random_port 30001 40000)}"
                echo -e " ${Info} TUIC 端口: ${Cyan}${PORT_TUIC}${Reset}"
                ;;
            4)
                read -p " XHTTP-Reality 端口 (留空自动分配): " port
                PORT_XHTTP="${port:-$(get_random_port 40001 50000)}"
                echo -e " ${Info} XHTTP-Reality 端口: ${Cyan}${PORT_XHTTP}${Reset}"
                ;;
            5)
                read -p " AnyTLS 端口 (留空自动分配): " port
                PORT_ANYTLS="${port:-$(get_random_port 50001 60000)}"
                echo -e " ${Info} AnyTLS 端口: ${Cyan}${PORT_ANYTLS}${Reset}"
                ;;
            6)
                read -p " VMess-WS-Argo 端口 (留空自动分配): " port
                PORT_VMESS_ARGO="${port:-$(get_random_port 8000 9000)}"
                echo -e " ${Info} VMess-WS-Argo 端口: ${Cyan}${PORT_VMESS_ARGO}${Reset}"
                ;;
            7)
                read -p " VLESS-WS-Argo 端口 (留空自动分配): " port
                PORT_VLESS_WS="${port:-$(get_random_port 8000 9000)}"
                echo -e " ${Info} VLESS-WS-Argo 端口: ${Cyan}${PORT_VLESS_WS}${Reset}"
                ;;
            *)
                echo -e " ${Warning} 无效选项: $choice，已忽略"
                ;;
        esac
    done
    
    # 检查是否选择了任何协议
    if [[ -z "$PORT_VLESS_REALITY" && -z "$PORT_HYSTERIA2" && -z "$PORT_TUIC" && \
          -z "$PORT_XHTTP" && -z "$PORT_ANYTLS" && -z "$PORT_VMESS_ARGO" && -z "$PORT_VLESS_WS" ]]; then
        echo -e ""
        echo -e " ${Error} 未选择任何协议"
        return 1
    fi
    
    return 0
}

# ==================== 询问 WARP ====================
ask_warp() {
    echo -e ""
    read -p " 是否启用 WARP 出站？(解锁 ChatGPT/Netflix 等) [y/N]: " warp_choice
    if [[ "$warp_choice" =~ ^[Yy]$ ]]; then
        ENABLE_WARP="yes"
        echo -e " ${Info} WARP 出站: ${Green}启用${Reset}"
    else
        echo -e " ${Info} WARP 出站: ${Yellow}禁用${Reset}"
    fi
}

# ==================== 询问自定义 UUID ====================
ask_uuid() {
    echo -e ""
    read -p " 自定义 UUID (留空自动生成): " uuid
    if [[ -n "$uuid" ]]; then
        CUSTOM_UUID="$uuid"
        echo -e " ${Info} UUID: ${Cyan}${CUSTOM_UUID}${Reset}"
    fi
}

# ==================== 配置 Argo 隧道 ====================
configure_argo() {
    # 只有选择了 Argo 协议才需要配置
    if [[ -z "$PORT_VMESS_ARGO" && -z "$PORT_VLESS_WS" ]]; then
        return 0
    fi
    
    echo -e ""
    echo -e "${Green}==================== Argo 隧道配置 ====================${Reset}"
    echo -e ""
    echo -e " ${Yellow}1.${Reset} 临时隧道 (无需配置，自动获取域名)"
    echo -e " ${Yellow}2.${Reset} 固定隧道 (需要 Cloudflare Token)"
    echo -e ""
    
    read -p " 选择隧道类型 [1/2] (默认1): " tunnel_type
    
    if [[ "$tunnel_type" == "2" ]]; then
        echo -e ""
        read -p " 输入 Argo 隧道域名: " domain
        read -p " 输入 Argo Token: " token
        
        if [[ -n "$domain" && -n "$token" ]]; then
            ARGO_DOMAIN="$domain"
            ARGO_AUTH="$token"
            echo -e " ${Info} Argo 域名: ${Cyan}${ARGO_DOMAIN}${Reset}"
            echo -e " ${Info} Argo Token: ${Cyan}${ARGO_AUTH:0:20}...${Reset}"
        else
            echo -e " ${Warning} 域名或 Token 为空，将使用临时隧道"
        fi
    else
        echo -e " ${Info} 将使用临时隧道"
    fi
    
    # Argo 节点地址替换提示
    echo -e ""
    echo -e " ${Info} Argo 节点地址将替换为: ${Cyan}${CDN_DOMAIN}${Reset}"
}

# ==================== 构建安装命令 ====================
build_install_command() {
    local cmd_params=""
    
    # 协议端口参数
    [[ -n "$PORT_VLESS_REALITY" ]] && cmd_params+="vlpt=\"$PORT_VLESS_REALITY\" "
    [[ -n "$PORT_HYSTERIA2" ]] && cmd_params+="hypt=\"$PORT_HYSTERIA2\" "
    [[ -n "$PORT_TUIC" ]] && cmd_params+="tupt=\"$PORT_TUIC\" "
    [[ -n "$PORT_XHTTP" ]] && cmd_params+="xhpt=\"$PORT_XHTTP\" "
    [[ -n "$PORT_ANYTLS" ]] && cmd_params+="anpt=\"$PORT_ANYTLS\" "
    [[ -n "$PORT_VMESS_ARGO" ]] && cmd_params+="vmpt=\"$PORT_VMESS_ARGO\" "
    [[ -n "$PORT_VLESS_WS" ]] && cmd_params+="vwpt=\"$PORT_VLESS_WS\" "
    
    # WARP 出站
    [[ "$ENABLE_WARP" == "yes" ]] && cmd_params+="warp=\"\" "
    
    # 自定义 UUID
    [[ -n "$CUSTOM_UUID" ]] && cmd_params+="uuid=\"$CUSTOM_UUID\" "
    
    # Argo 隧道节点处理 - 添加 CDN 优选域名
    if [[ -n "$PORT_VMESS_ARGO" ]] || [[ -n "$PORT_VLESS_WS" ]]; then
        cmd_params+="cdnym=\"$CDN_DOMAIN\" "
        
        # 如果有 Token，添加域名和认证
        [[ -n "$ARGO_DOMAIN" ]] && cmd_params+="agn=\"$ARGO_DOMAIN\" "
        [[ -n "$ARGO_AUTH" ]] && cmd_params+="agk=\"$ARGO_AUTH\" "
    fi
    
    echo "$cmd_params"
}

# ==================== 显示安装命令 ====================
show_install_command() {
    local cmd_params=$(build_install_command)
    
    echo -e ""
    echo -e "${Green}==================== 安装命令预览 ====================${Reset}"
    echo -e ""
    echo -e "${Cyan}${cmd_params}bash <(curl -Ls $ARGOSBX_URL)${Reset}"
    echo -e ""
    echo -e "${Green}======================================================${Reset}"
}

# ==================== 执行安装 ====================
execute_install() {
    local cmd_params=$(build_install_command)
    
    echo -e ""
    echo -e "${Info} 开始执行安装..."
    echo -e ""
    
    # 执行安装命令
    eval "${cmd_params}bash <(curl -Ls $ARGOSBX_URL)"
    
    local exit_code=$?
    
    echo -e ""
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${Info} 安装完成!"
        echo -e ""
        echo -e "${Tip} 管理命令: ${Cyan}agsbx${Reset}"
        echo -e "${Tip} 查看节点: ${Cyan}agsbx list${Reset}"
        echo -e "${Tip} 删除节点: ${Cyan}agsbx del${Reset}"
    else
        echo -e "${Error} 安装过程中出现错误 (退出码: $exit_code)"
    fi
    
    return $exit_code
}

# ==================== 快速安装菜单 ====================
quick_install_menu() {
    echo -e ""
    echo -e "${Green}==================== 快速安装 ====================${Reset}"
    echo -e ""
    echo -e " ${Green}1.${Reset}  Hysteria2               - 推荐，高速稳定"
    echo -e " ${Green}2.${Reset}  Hysteria2 + WARP        - 解锁流媒体"
    echo -e " ${Green}3.${Reset}  VLESS-Reality           - 抗检测强"
    echo -e " ${Green}4.${Reset}  TUIC v5                 - 低延迟"
    echo -e " ${Green}5.${Reset}  Hy2 + TUIC + Reality    - 全协议组合"
    echo -e " ${Green}6.${Reset}  VMess-WS-Argo           - 通过CF隧道"
    echo -e " ${Green}0.${Reset}  返回"
    echo -e ""
    echo -e "${Green}===================================================${Reset}"
    
    read -p " 请选择 [0-6]: " quick_choice
    
    case "$quick_choice" in
        1)
            PORT_HYSTERIA2=$(get_random_port 20001 30000)
            ;;
        2)
            PORT_HYSTERIA2=$(get_random_port 20001 30000)
            ENABLE_WARP="yes"
            ;;
        3)
            PORT_VLESS_REALITY=$(get_random_port 10000 20000)
            ;;
        4)
            PORT_TUIC=$(get_random_port 30001 40000)
            ;;
        5)
            PORT_HYSTERIA2=$(get_random_port 20001 30000)
            PORT_TUIC=$(get_random_port 30001 40000)
            PORT_VLESS_REALITY=$(get_random_port 10000 20000)
            ;;
        6)
            PORT_VMESS_ARGO=$(get_random_port 8000 9000)
            ;;
        0)
            return 1
            ;;
        *)
            echo -e "${Error} 无效选择"
            return 1
            ;;
    esac
    
    return 0
}

# ==================== 主菜单 ====================
main_menu() {
    while true; do
        show_logo
        
        echo -e "${Green}==================== 主菜单 ====================${Reset}"
        echo -e ""
        echo -e " ${Green}1.${Reset}  快速安装         - 一键安装常用配置"
        echo -e " ${Green}2.${Reset}  自定义安装       - 选择协议和端口"
        echo -e " ${Green}3.${Reset}  查看节点信息     - agsbx list"
        echo -e " ${Green}4.${Reset}  删除所有节点     - agsbx del"
        echo -e " ${Green}0.${Reset}  返回上级菜单"
        echo -e ""
        echo -e "${Green}=================================================${Reset}"
        
        read -p " 请选择 [0-4]: " main_choice
        
        case "$main_choice" in
            1)
                if quick_install_menu; then
                    show_install_command
                    read -p " 确认执行安装? [Y/n]: " confirm
                    if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                        execute_install
                    fi
                fi
                ;;
            2)
                # 重置变量
                PORT_VLESS_REALITY=""
                PORT_HYSTERIA2=""
                PORT_TUIC=""
                PORT_XHTTP=""
                PORT_ANYTLS=""
                PORT_VMESS_ARGO=""
                PORT_VLESS_WS=""
                ENABLE_WARP=""
                CUSTOM_UUID=""
                ARGO_DOMAIN=""
                ARGO_AUTH=""
                
                if select_protocols; then
                    ask_warp
                    ask_uuid
                    configure_argo
                    show_install_command
                    
                    read -p " 确认执行安装? [Y/n]: " confirm
                    if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                        execute_install
                    fi
                fi
                ;;
            3)
                echo -e ""
                echo -e "${Info} 执行: agsbx list"
                echo -e ""
                if command -v agsbx &>/dev/null; then
                    agsbx list
                else
                    echo -e "${Warning} agsbx 命令未找到，可能未安装过节点"
                fi
                ;;
            4)
                echo -e ""
                read -p " 确定删除所有节点? [y/N]: " del_confirm
                if [[ "$del_confirm" =~ ^[Yy]$ ]]; then
                    if command -v agsbx &>/dev/null; then
                        agsbx del
                    else
                        echo -e "${Warning} agsbx 命令未找到"
                    fi
                fi
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${Error} 无效选择"
                ;;
        esac
        
        echo -e ""
        read -p " 按回车继续..."
    done
}

# ==================== 主入口 ====================
main() {
    main_menu
}

# 执行主函数
main "$@"
