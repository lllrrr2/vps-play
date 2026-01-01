#!/bin/bash
# TUIC v5 模块 (对齐 Misaka tuic.sh)
#
# Copyright (C) 2025 VPS-play Contributors

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"

# ==================== 配置 ====================
TUIC_BIN="/usr/local/bin/tuic"
TUIC_CONFIG_DIR="/etc/tuic"
TUIC_CONFIG_FILE="$TUIC_CONFIG_DIR/tuic.json"
TUIC_SERVICE_FILE="/etc/systemd/system/tuic.service"
TUIC_CLIENT_DIR="/root/tuic"
TUIC_BING_DIR="/root/bing"

# 颜色定义
Red="\033[31m"
Green="\033[32m"
Yellow="\033[33m"
Cyan="\033[36m"
Reset="\033[0m"
Info="${Green}[信息]${Reset}"
Error="${Red}[错误]${Reset}"
Warning="${Yellow}[警告]${Reset}"

# ==================== 系统检测 ====================
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

tuic_archAffix() {
    case "$(uname -m)" in
        x86_64 | amd64) echo 'amd64' ;;
        armv8 | arm64 | aarch64) echo 'arm64' ;;
        *) echo -e "${Error} 不支持的架构" && exit 1 ;;
    esac
}

# 杀死占用端口的进程
tuic_kill_port_process() {
    local port=$1
    local pids=$(ss -tunlp | grep ":$port " | grep -oP 'pid=\K[0-9]+')
    if [ -n "$pids" ]; then
        echo -e "${Warning} 检测到端口 $port 被占用，正在释放..."
        for pid in $pids; do
            kill -9 $pid 2>/dev/null && echo -e "${Info} 已杀死进程 $pid"
        done
        sleep 1
    fi
}

tuic_realip() {
    ip=$(curl -s4m8 ip.sb -k) || ip=$(curl -s6m8 ip.sb -k)
}

tuic_check_ip() {
    warpv6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    warpv4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $warpv4 =~ on|plus || $warpv6 =~ on|plus ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        systemctl stop warp-go >/dev/null 2>&1
        tuic_realip
        systemctl start warp-go >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
    else
        tuic_realip
    fi
}

# ==================== 证书申请 ====================
tuic_cert() {
    echo -e "${Cyan}TUIC 协议证书申请方式如下：${Reset}"
    echo ""
    echo -e " ${Green}1.${Reset} 必应自签证书 ${Yellow}（默认）${Reset}"
    echo -e " ${Green}2.${Reset} Acme 脚本自动申请"
    echo -e " ${Green}3.${Reset} 自定义证书路径"
    echo ""
    read -rp "请输入选项 [1-3]: " certInput
    
    if [[ $certInput == 3 ]]; then
        read -p "请输入公钥文件 crt 的路径：" tuic_cert_path
        read -p "请输入密钥文件 key 的路径：" tuic_key_path
        read -p "请输入证书的域名：" tuic_domain
    elif [[ $certInput == 2 ]]; then
        tuic_cert_path="/root/cert.crt"
        tuic_key_path="/root/private.key"
        if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]] && [[ -f /root/ca.log ]]; then
            tuic_domain=$(cat /root/ca.log)
            echo -e "${Info} 检测到原有域名：$tuic_domain 的证书，正在应用"
        else
            tuic_realip
            read -p "请输入需要申请证书的域名：" tuic_domain
            [[ -z $tuic_domain ]] && echo -e "${Error} 未输入域名" && return 1
            
            ${PACKAGE_INSTALL[int]} curl wget sudo socat openssl
            if [[ $SYSTEM == "CentOS" ]]; then
                ${PACKAGE_INSTALL[int]} cronie && systemctl start crond && systemctl enable crond
            else
                ${PACKAGE_INSTALL[int]} cron && systemctl start cron && systemctl enable cron
            fi
            
            curl https://get.acme.sh | sh -s email=$(date +%s%N | md5sum | cut -c 1-16)@gmail.com
            source ~/.bashrc
            bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade
            bash ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
            
            if [[ -n $(echo $ip | grep ":") ]]; then
                bash ~/.acme.sh/acme.sh --issue -d ${tuic_domain} --standalone -k ec-256 --listen-v6 --insecure
            else
                bash ~/.acme.sh/acme.sh --issue -d ${tuic_domain} --standalone -k ec-256 --insecure
            fi
            bash ~/.acme.sh/acme.sh --install-cert -d ${tuic_domain} --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
            
            if [[ -f /root/cert.crt && -f /root/private.key ]]; then
                echo $tuic_domain > /root/ca.log
                echo -e "${Info} 证书申请成功"
            else
                echo -e "${Error} 证书申请失败"
                return 1
            fi
        fi
    else
        tuic_cert_path="$TUIC_BING_DIR/cert.crt"
        tuic_key_path="$TUIC_BING_DIR/private.key"
        tuic_domain="www.bing.com"
        
        mkdir -p "$TUIC_BING_DIR"
        cd "$TUIC_BING_DIR"
        openssl ecparam -genkey -name prime256v1 -out private.key
        openssl req -new -x509 -days 36500 -key private.key -out cert.crt -subj "/CN=www.bing.com"
    fi
}

# ==================== 端口配置 ====================
tuic_port() {
    if [ -n "$TUIC_PORT" ]; then
        echo -e "${Info} 使用预设端口: $TUIC_PORT"
        tuic_server_port="$TUIC_PORT"
    else
        read -p "设置 TUIC 端口 [1-65535]（回车则随机分配端口）：" tuic_server_port
        [[ -z $tuic_server_port ]] && tuic_server_port=$(shuf -i 2000-65535 -n 1)
        until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$tuic_server_port") ]]; do
            echo -e "${Error} $tuic_server_port 端口已被占用"
            read -p "设置 TUIC 端口 [1-65535]（回车则随机分配端口）：" tuic_server_port
            [[ -z $tuic_server_port ]] && tuic_server_port=$(shuf -i 2000-65535 -n 1)
        done
    fi
    echo -e "${Info} 将使用端口：$tuic_server_port"
    
    # 释放端口
    tuic_kill_port_process $tuic_server_port
}

# ==================== 安装逻辑 (V5) ====================
install_tuic() {
    echo -e "${Cyan}========== 安装 TUIC v5 (Misaka Logic) ==========${Reset}"
    
    # 清理旧配置
    echo -e "${Info} 清理旧配置文件..."
    systemctl stop tuic >/dev/null 2>&1
    systemctl disable tuic >/dev/null 2>&1
    rm -rf "$TUIC_CONFIG_DIR" "$TUIC_CLIENT_DIR" "$TUIC_BING_DIR"
    
    tuic_check_ip
    
    # 安装依赖
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} wget curl sudo
    
    # 下载 TUIC 二进制
    wget https://gitlab.com/Misaka-blog/tuic-script/-/raw/main/files/tuic-server-latest-linux-$(tuic_archAffix) -O "$TUIC_BIN"
    if [[ -f "$TUIC_BIN" ]]; then
        chmod +x "$TUIC_BIN"
        echo -e "${Info} TUIC v5 二进制安装成功"
    else
        echo -e "${Error} TUIC v5 安装失败"
        return 1
    fi
    
    # 配置证书、端口
    tuic_cert || return 1
    tuic_port
    
    # UUID 和密码
    read -p "设置 UUID（回车跳过为随机）：" tuic_uuid
    [[ -z $tuic_uuid ]] && tuic_uuid=$(cat /proc/sys/kernel/random/uuid)
    echo -e "${Info} UUID：$tuic_uuid"
    
    read -p "设置密码（回车跳过为随机）：" tuic_passwd
    [[ -z $tuic_passwd ]] && tuic_passwd=$(date +%s%N | md5sum | cut -c 1-8)
    echo -e "${Info} 密码：$tuic_passwd"
    
    # 确定域名
    if [[ $tuic_domain == "www.bing.com" ]]; then
        tuic_finaldomain=$ip
        tuic_snidomain=$tuic_domain
    else
        tuic_finaldomain=$tuic_domain
        tuic_snidomain=$tuic_domain
    fi
    
    # 生成服务端配置
    mkdir -p "$TUIC_CONFIG_DIR"
    cat << EOF > "$TUIC_CONFIG_FILE"
{
    "server": "[::]:$tuic_server_port",
    "users": {
        "$tuic_uuid": "$tuic_passwd"
    },
    "certificate": "$tuic_cert_path",
    "private_key": "$tuic_key_path",
    "congestion_control": "bbr",
    "alpn": ["h3"],
    "log_level": "warn"
}
EOF
    
    # 生成客户端配置
    mkdir -p "$TUIC_CLIENT_DIR"
    cat << EOF > "$TUIC_CLIENT_DIR/tuic-client.json"
{
    "relay": {
        "server": "$tuic_finaldomain:$tuic_server_port",
        "uuid": "$tuic_uuid",
        "password": "$tuic_passwd",
        "ip": "$ip",
        "congestion_control": "bbr",
        "alpn": ["h3"]
    },
    "local": {
        "server": "127.0.0.1:6080"
    },
    "log_level": "warn"
}
EOF
    
    # 分享链接
    tuic_url="tuic://$tuic_uuid:$tuic_passwd@$tuic_finaldomain:$tuic_server_port?congestion_control=bbr&udp_relay_mode=quic&alpn=h3#tuicv5-misaka"
    echo "$tuic_url" > "$TUIC_CLIENT_DIR/url.txt"
    
    # Clash Meta 配置
    cat << EOF > "$TUIC_CLIENT_DIR/clash-meta.yaml"
mixed-port: 7890
external-controller: 127.0.0.1:9090
allow-lan: false
mode: rule
log-level: debug
ipv6: true
dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  nameserver:
    - 8.8.8.8
    - 1.1.1.1
proxies:
  - name: Misaka-tuicV5
    server: $tuic_finaldomain
    port: $tuic_server_port
    type: tuic
    uuid: $tuic_uuid
    password: $tuic_passwd
    ip: $ip
    alpn: [h3]
    disable-sni: true
    reduce-rtt: true
    request-timeout: 8000
    udp-relay-mode: quic
    congestion-controller: bbr
    skip-cert-verify: true
    sni: $tuic_snidomain
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Misaka-tuicV5
rules:
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
EOF
    
    # 配置说明
    cat << EOF > "$TUIC_CLIENT_DIR/tuic.txt"
Sagernet、Nekobox 与小火箭配置说明：
{
    服务器地址：$tuic_finaldomain
    服务器端口：$tuic_server_port
    UUID: $tuic_uuid
    密码：$tuic_passwd
    SNI: $tuic_snidomain
    ALPN：h3
    UDP 转发：开启
    UDP 转发模式：QUIC
    拥塞控制：bbr
    跳过服务器证书验证：开启
}
EOF
    
    # Systemd 服务
    cat << EOF > "$TUIC_SERVICE_FILE"
[Unit]
Description=tuic Service
Documentation=https://gitlab.com/Misaka-blog/tuic-script
After=network.target
[Service]
User=root
ExecStart=$TUIC_BIN -c $TUIC_CONFIG_FILE
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable tuic
    systemctl start tuic
    
    if [[ -n $(systemctl status tuic 2>/dev/null | grep -w active) ]]; then
        echo -e "${Green}TUIC v5 服务启动成功${Reset}"
        echo ""
        echo -e "${Yellow}客户端配置文件已保存到 $TUIC_CLIENT_DIR/${Reset}"
        echo -e "${Yellow}分享链接:${Reset}"
        echo -e "${Cyan}$(cat $TUIC_CLIENT_DIR/url.txt)${Reset}"
    else
        echo -e "${Error} 服务启动失败，请运行 systemctl status tuic 查看"
    fi
}

uninstall_tuic() {
    echo -e "${Warning} 正在卸载 TUIC..."
    systemctl stop tuic >/dev/null 2>&1
    systemctl disable tuic >/dev/null 2>&1
    rm -f "$TUIC_SERVICE_FILE"
    rm -rf "$TUIC_BIN" "$TUIC_CONFIG_DIR" "$TUIC_CLIENT_DIR" "$TUIC_BING_DIR"
    systemctl daemon-reload
    echo -e "${Green}TUIC 已卸载${Reset}"
}

tuic_show_conf() {
    if [[ -f "$TUIC_CLIENT_DIR/url.txt" ]]; then
        echo -e "${Yellow}分享链接:${Reset}"
        cat "$TUIC_CLIENT_DIR/url.txt"
        echo ""
        echo -e "${Yellow}客户端配置:${Reset}"
        cat "$TUIC_CLIENT_DIR/tuic.txt"
    else
        echo -e "${Error} 配置文件不存在"
    fi
}

tuic_menu() {
    clear
    echo -e "${Cyan}========== TUIC v5 管理 (Misaka Logic) ==========${Reset}"
    echo -e " ${Green}1.${Reset} 安装 TUIC v5"
    echo -e " ${Green}2.${Reset} ${Red}卸载 TUIC v5${Reset}"
    echo " -------------"
    echo -e " ${Green}3.${Reset} 启动 TUIC"
    echo -e " ${Green}4.${Reset} 停止 TUIC"
    echo -e " ${Green}5.${Reset} 重启 TUIC"
    echo " -------------"
    echo -e " ${Green}6.${Reset} 查看配置信息"
    echo -e " ${Green}0.${Reset} 返回"
    echo "=================================================="
    read -p "请选择: " choice

    case "$choice" in
        1) install_tuic ;;
        2) uninstall_tuic ;;
        3) systemctl start tuic && systemctl enable tuic && echo -e "${Info} 已启动" ;;
        4) systemctl stop tuic && systemctl disable tuic && echo -e "${Info} 已停止" ;;
        5) systemctl restart tuic && echo -e "${Info} 已重启" ;;
        6) tuic_show_conf ;;
        0) return ;;
        *) echo -e "${Error} 无效选择" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    tuic_menu
fi
