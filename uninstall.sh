#!/bin/bash
# VPS-play 卸载脚本
# 完全移除 VPS-play 及其所有数据
#
# 安全特性:
# - 使用 safe_ops.sh 安全函数
# - rm -rf 有白名单保护
# - 进程停止使用 PID 文件优先
#
# Copyright (C) 2025 VPS-play Contributors

# ==================== 严格模式 ====================
set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo -e "\033[31m[错误]\033[0m 脚本执行失败 (行 $LINENO)"; exit 1' ERR

# ==================== 变量定义 ====================
PROJECT_NAME="vps-play"
INSTALL_DIR="$HOME/$PROJECT_NAME"
DATA_DIR="$HOME/.vps-play"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# 颜色定义
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Cyan="\033[36m"
Reset="\033[0m"

# ==================== 加载安全函数库 ====================
if [[ -f "$SCRIPT_DIR/utils/safe_ops.sh" ]]; then
    source "$SCRIPT_DIR/utils/safe_ops.sh"
elif [[ -f "$INSTALL_DIR/utils/safe_ops.sh" ]]; then
    source "$INSTALL_DIR/utils/safe_ops.sh"
else
    # 回退: 定义最小化的安全函数
    safe_rm() {
        local target="$1"
        [[ -z "$target" ]] && return 1
        # 严格白名单校验
        if [[ "$target" == "$HOME/.vps-play" || "$target" == "$HOME/.vps-play"/* || 
              "$target" == "$HOME/vps-play" || "$target" == "$HOME/vps-play"/* ]]; then
            rm -rf "$target"
        else
            echo -e "${Red}[错误]${Reset} 拒绝删除非法路径: $target" >&2
            return 1
        fi
    }
    safe_kill() {
        local name="$1"
        local pid_file="$HOME/.vps-play/run/${name}.pid"
        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file")
            kill "$pid" 2>/dev/null || true
            rm -f "$pid_file"
        fi
        # 回退: 限定路径的 pkill
        pkill -f "$HOME/.vps-play.*$name" 2>/dev/null || true
    }
fi

# ==================== 路径白名单校验 ====================
# 在任何删除操作前验证路径
validate_paths() {
    # DATA_DIR 必须是 $HOME/.vps-play
    if [[ "$DATA_DIR" != "$HOME/.vps-play" ]]; then
        echo -e "${Red}[错误]${Reset} 数据目录路径异常: $DATA_DIR"
        echo -e "期望: $HOME/.vps-play"
        exit 1
    fi
    
    # INSTALL_DIR 必须是 $HOME/vps-play
    if [[ "$INSTALL_DIR" != "$HOME/vps-play" ]]; then
        echo -e "${Red}[错误]${Reset} 安装目录路径异常: $INSTALL_DIR"
        echo -e "期望: $HOME/vps-play"
        exit 1
    fi
    
    # 防止在 root 目录下操作
    if [[ "$HOME" == "/" ]]; then
        echo -e "${Red}[错误]${Reset} HOME 目录异常，拒绝执行"
        exit 1
    fi
}

# ==================== 显示 Logo ====================
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

# ==================== 用户确认 ====================
read -rp "确定要卸载 VPS-play? [y/N]: " confirm
[[ ! $confirm =~ ^[Yy]$ ]] && { echo -e "${Green}[信息]${Reset} 已取消卸载"; exit 0; }

read -rp "再次确认，输入 'UNINSTALL' 继续: " confirm2
[[ "$confirm2" != "UNINSTALL" ]] && { echo -e "${Green}[信息]${Reset} 已取消卸载"; exit 0; }

# ==================== 执行路径校验 ====================
validate_paths

echo -e ""
echo -e "${Green}[信息]${Reset} 开始卸载..."

# ==================== 1. 停止所有运行中的服务 ====================
echo -e "${Green}[信息]${Reset} 停止所有服务..."

# 优先使用 PID 文件停止
for service in sing-box xray gost cloudflared nezha-agent frpc frps hysteria tuic; do
    safe_kill "$service" 2>/dev/null || true
done

# 回退: 限定到项目路径的 pkill (防止误杀)
for proc in sing-box xray gost cloudflared nezha-agent frpc frps hysteria tuic; do
    pkill -f "$HOME/.vps-play.*$proc" 2>/dev/null || true
    pkill -f "$HOME/vps-play.*$proc" 2>/dev/null || true
done

# ==================== 2. 删除 systemd 服务 ====================
if [[ "$(id -u)" == "0" ]]; then
    echo -e "${Green}[信息]${Reset} 删除 systemd 服务..."
    for service in sing-box gost cloudflared nezha-agent frpc frps hysteria-server tuic; do
        if [[ -f "/etc/systemd/system/${service}.service" ]]; then
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
            rm -f "/etc/systemd/system/${service}.service"
            echo -e "  ✓ 已删除 ${service} 服务"
        fi
    done
    systemctl daemon-reload 2>/dev/null || true
fi

# ==================== 3. 清理 cron 任务 ====================
echo -e "${Green}[信息]${Reset} 清理 cron 任务..."
if command -v crontab &>/dev/null; then
    crontab -l 2>/dev/null | grep -v "vps-play" | grep -v "sing-box" | grep -v "gost" | crontab - 2>/dev/null || true
fi

# ==================== 4. 使用安全函数删除目录 ====================
if [[ -d "$INSTALL_DIR" ]]; then
    echo -e "${Green}[信息]${Reset} 删除安装目录..."
    if safe_rm "$INSTALL_DIR"; then
        echo -e "  ✓ 已删除 ${INSTALL_DIR}"
    else
        echo -e "  ${Red}✗${Reset} 删除失败: ${INSTALL_DIR}"
    fi
fi

if [[ -d "$DATA_DIR" ]]; then
    echo -e "${Green}[信息]${Reset} 删除数据目录..."
    if safe_rm "$DATA_DIR"; then
        echo -e "  ✓ 已删除 ${DATA_DIR}"
    else
        echo -e "  ${Red}✗${Reset} 删除失败: ${DATA_DIR}"
    fi
fi

# ==================== 5. 删除快捷命令 ====================
if [[ -f "$HOME/bin/vps-play" ]]; then
    echo -e "${Green}[信息]${Reset} 删除快捷命令..."
    rm -f "$HOME/bin/vps-play"
    echo -e "  ✓ 已删除 vps-play 命令"
fi

# ==================== 6. 清理 shell 配置 ====================
echo -e "${Green}[信息]${Reset} 清理 shell 配置..."
for rcfile in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc"; do
    if [[ -f "$rcfile" ]]; then
        # 移除 vps-play 相关的 PATH (使用 grep -v 而非 sed -i 以兼容 BSD)
        if grep -q "vps-play" "$rcfile" 2>/dev/null; then
            grep -v "vps-play" "$rcfile" > "${rcfile}.tmp" && mv "${rcfile}.tmp" "$rcfile"
        fi
    fi
done

# ==================== 7. 清理其他相关文件 (可选，不强制) ====================
echo -e "${Green}[信息]${Reset} 清理其他文件..."
# 注意: 这些目录可能包含其他工具的配置，询问用户
if [[ -d "$HOME/.cloudflared" ]]; then
    read -rp "是否删除 ~/.cloudflared? [y/N]: " del_cf
    [[ $del_cf =~ ^[Yy]$ ]] && rm -rf "$HOME/.cloudflared" && echo -e "  ✓ 已删除 ~/.cloudflared"
fi

# ==================== 完成 ====================
echo -e ""
echo -e "${Green}==================== 卸载完成 ====================${Reset}"
echo -e ""
echo -e "VPS-play 已完全卸载。"
echo -e ""
echo -e "${Cyan}如需重新安装，请运行:${Reset}"
echo -e "  curl -sL https://raw.githubusercontent.com/hxzlplp7/vps-play/main/install.sh | bash"
echo -e ""
echo -e "${Green}=================================================${Reset}"
