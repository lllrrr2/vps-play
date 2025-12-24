#!/bin/bash
# VPS-play 卸载脚本
# 完全移除 VPS-play 及其所有数据

Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Cyan="\033[36m"
Reset="\033[0m"

PROJECT_NAME="vps-play"
INSTALL_DIR="$HOME/$PROJECT_NAME"
DATA_DIR="$HOME/.vps-play"

echo -e "${Cyan}"
cat << "EOF"
    ╦  ╦╔═╗╔═╗   ╔═╗╦  ╔═╗╦ ╦
    ╚╗╔╝╠═╝╚═╗───╠═╝║  ╠═╣╚╦╝
     ╚╝ ╩  ╚═╝   ╩  ╩═╝╩ ╩ ╩ 
    卸载程序
EOF
echo -e "${Reset}"

echo -e "${Yellow}========== VPS-play 卸载 ==========${Reset}"
echo -e ""
echo -e "此操作将执行以下步骤:"
echo -e " 1. 停止所有运行中的服务"
echo -e " 2. 删除安装目录: ${Cyan}${INSTALL_DIR}${Reset}"
echo -e " 3. 删除数据目录: ${Cyan}${DATA_DIR}${Reset}"
echo -e " 4. 删除快捷命令: ${Cyan}$HOME/bin/vps-play${Reset}"
echo -e " 5. 删除 systemd 服务 (如果有)"
echo -e ""
echo -e "${Red}警告: 此操作不可恢复！${Reset}"
echo -e ""

read -p "确定要卸载 VPS-play? [y/N]: " confirm
[[ ! $confirm =~ ^[Yy]$ ]] && { echo -e "${Green}[信息]${Reset} 已取消卸载"; exit 0; }

read -p "再次确认，输入 'UNINSTALL' 继续: " confirm2
[ "$confirm2" != "UNINSTALL" ] && { echo -e "${Green}[信息]${Reset} 已取消卸载"; exit 0; }

echo -e ""
echo -e "${Green}[信息]${Reset} 开始卸载..."

# 1. 停止所有运行中的服务
echo -e "${Green}[信息]${Reset} 停止所有服务..."
pkill -f "sing-box" 2>/dev/null
pkill -f "xray" 2>/dev/null
pkill -f "gost" 2>/dev/null
pkill -f "cloudflared" 2>/dev/null
pkill -f "nezha-agent" 2>/dev/null
pkill -f "frpc" 2>/dev/null
pkill -f "frps" 2>/dev/null

# 2. 删除 systemd 服务 (如果是 root 且存在)
if [ "$(id -u)" = "0" ]; then
    echo -e "${Green}[信息]${Reset} 删除 systemd 服务..."
    for service in sing-box gost cloudflared nezha-agent frpc frps; do
        if [ -f "/etc/systemd/system/${service}.service" ]; then
            systemctl stop "$service" 2>/dev/null
            systemctl disable "$service" 2>/dev/null
            rm -f "/etc/systemd/system/${service}.service"
            echo -e "  ✓ 已删除 ${service} 服务"
        fi
    done
    systemctl daemon-reload 2>/dev/null
fi

# 3. 删除 cron 任务 (可选)
echo -e "${Green}[信息]${Reset} 清理 cron 任务..."
crontab -l 2>/dev/null | grep -v "vps-play" | grep -v "sing-box" | grep -v "gost" | crontab - 2>/dev/null

# 4. 删除安装目录
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${Green}[信息]${Reset} 删除安装目录..."
    rm -rf "$INSTALL_DIR"
    echo -e "  ✓ 已删除 ${INSTALL_DIR}"
fi

# 5. 删除数据目录
if [ -d "$DATA_DIR" ]; then
    echo -e "${Green}[信息]${Reset} 删除数据目录..."
    rm -rf "$DATA_DIR"
    echo -e "  ✓ 已删除 ${DATA_DIR}"
fi

# 6. 删除快捷命令
if [ -f "$HOME/bin/vps-play" ]; then
    echo -e "${Green}[信息]${Reset} 删除快捷命令..."
    rm -f "$HOME/bin/vps-play"
    echo -e "  ✓ 已删除 vps-play 命令"
fi

# 7. 清理 shell 配置 (可选)
echo -e "${Green}[信息]${Reset} 清理 shell 配置..."
for rcfile in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc"; do
    if [ -f "$rcfile" ]; then
        # 移除 vps-play 相关的 PATH
        sed -i.bak '/HOME\/bin/d' "$rcfile" 2>/dev/null
        rm -f "${rcfile}.bak"
    fi
done

# 8. 删除其他相关文件
echo -e "${Green}[信息]${Reset} 清理其他文件..."
rm -rf "$HOME/.cloudflared" 2>/dev/null
rm -rf "$HOME/.acme.sh" 2>/dev/null

echo -e ""
echo -e "${Green}==================== 卸载完成 ====================${Reset}"
echo -e ""
echo -e "VPS-play 已完全卸载。"
echo -e ""
echo -e "${Cyan}如需重新安装，请运行:${Reset}"
echo -e "  curl -sL https://raw.githubusercontent.com/hxzlplp7/vps-play/main/install.sh | bash"
echo -e ""
echo -e "${Green}=================================================${Reset}"
