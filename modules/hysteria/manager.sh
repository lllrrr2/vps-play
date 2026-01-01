#!/bin/bash
# Hysteria 2 模块 (对齐 Misaka hysteria.sh)
#
# Copyright (C) 2025 VPS-play Contributors

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"

# ==================== 配置 ====================
HY2_BIN="/usr/local/bin/hysteria"
HY2_CONFIG_DIR="/etc/hysteria"
HY2_CONFIG_FILE="$HY2_CONFIG_DIR/config.yaml"
HY2_SERVICE_FILE="/etc/systemd/system/hysteria-server.service"
HY2_CLIENT_DIR="/root/hy"

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

hy2_realip() {
    ip=$(curl -s4m8 ip.sb -k) || ip=$(curl -s6m8 ip.sb -k)
}

hy2_archAffix() {
    case "$(uname -m)" in
        x86_64 | amd64) echo 'amd64' ;;
        armv8 | arm64 | aarch64) echo 'arm64' ;;
        *) echo -e "${Error} 不支持的架构" && exit 1 ;;
    esac
}

# ==================== 证书申请 ====================
hy2_inst_cert() {
    echo -e "${Cyan}Hysteria 2 协议证书申请方式如下：${Reset}"
    echo ""
    echo -e " ${Green}1.${Reset} 必应自签证书 ${Yellow}（默认）${Reset}"
    echo -e " ${Green}2.${Reset} Acme 脚本自动申请"
    echo -e " ${Green}3.${Reset} 自定义证书路径"
    echo ""
    read -rp "请输入选项 [1-3]: " certInput
    
    if [[ $certInput == 2 ]]; then
        hy2_cert_path="/root/cert.crt"
        hy2_key_path="/root/private.key"
        
        if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]] && [[ -f /root/ca.log ]]; then
            hy2_domain=$(cat /root/ca.log)
            echo -e "${Info} 检测到原有域名：$hy2_domain 的证书，正在应用"
        else
            hy2_realip
            read -p "请输入需要申请证书的域名：" hy2_domain
            [[ -z $hy2_domain ]] && echo -e "${Error} 未输入域名" && return 1
            
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
                bash ~/.acme.sh/acme.sh --issue -d ${hy2_domain} --standalone -k ec-256 --listen-v6 --insecure
            else
                bash ~/.acme.sh/acme.sh --issue -d ${hy2_domain} --standalone -k ec-256 --insecure
            fi
            bash ~/.acme.sh/acme.sh --install-cert -d ${hy2_domain} --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
            
            if [[ -f /root/cert.crt && -f /root/private.key ]]; then
                echo $hy2_domain > /root/ca.log
                echo -e "${Info} 证书申请成功"
            else
                echo -e "${Error} 证书申请失败"
                return 1
            fi
        fi
    elif [[ $certInput == 3 ]]; then
        read -p "请输入公钥文件 crt 的路径：" hy2_cert_path
        read -p "请输入密钥文件 key 的路径：" hy2_key_path
        read -p "请输入证书的域名：" hy2_domain
    else
        echo -e "${Info} 将使用必应自签证书"
        mkdir -p "$HY2_CONFIG_DIR"
        hy2_cert_path="$HY2_CONFIG_DIR/cert.crt"
        hy2_key_path="$HY2_CONFIG_DIR/private.key"
        openssl ecparam -genkey -name prime256v1 -out "$hy2_key_path"
        openssl req -new -x509 -days 36500 -key "$hy2_key_path" -out "$hy2_cert_path" -subj "/CN=www.bing.com"
        chmod 777 "$hy2_cert_path" "$hy2_key_path"
        hy2_domain="www.bing.com"
    fi
}

# ==================== 端口配置 ====================
hy2_inst_port() {
    if [ -n "$HY2_PORT" ]; then
        echo -e "${Info} 使用预设端口: $HY2_PORT"
        hy2_port="$HY2_PORT"
    else
        read -p "设置 Hysteria 2 端口 [1-65535]（回车则随机分配端口）：" hy2_port
        [[ -z $hy2_port ]] && hy2_port=$(shuf -i 2000-65535 -n 1)
        until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$hy2_port") ]]; do
            echo -e "${Error} $hy2_port 端口已被占用"
            read -p "设置 Hysteria 2 端口 [1-65535]（回车则随机分配端口）：" hy2_port
            [[ -z $hy2_port ]] && hy2_port=$(shuf -i 2000-65535 -n 1)
        done
    fi
    echo -e "${Info} 将使用端口：$hy2_port"
    
    # 端口跳跃
    read -p "是否启用端口跳跃? [y/N]: " jumpInput
    if [[ $jumpInput =~ ^[Yy]$ ]]; then
        read -p "设置起始端口 (建议10000-65535)：" hy2_firstport
        read -p "设置末尾端口 (需大于起始端口)：" hy2_endport
        if [[ $hy2_firstport -lt $hy2_endport ]]; then
            iptables -t nat -A PREROUTING -p udp --dport $hy2_firstport:$hy2_endport -j DNAT --to-destination :$hy2_port
            ip6tables -t nat -A PREROUTING -p udp --dport $hy2_firstport:$hy2_endport -j DNAT --to-destination :$hy2_port
            netfilter-persistent save >/dev/null 2>&1
        fi
    fi
}

# ==================== 安装逻辑 ====================
install_hysteria() {
    echo -e "${Cyan}========== 安装 Hysteria 2 (Misaka Logic) ==========${Reset}"
    
    # 检测 WARP 并获取真实 IP
    warpv6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    warpv4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $warpv4 =~ on|plus || $warpv6 =~ on|plus ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        systemctl stop warp-go >/dev/null 2>&1
        hy2_realip
        systemctl start warp-go >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
    else
        hy2_realip
    fi
    
    # 安装依赖
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl wget sudo qrencode procps iptables-persistent netfilter-persistent
    
    # 下载官方安装脚本
    wget -N https://raw.githubusercontent.com/Misaka-blog/hysteria-install/main/hy2/install_server.sh
    bash install_server.sh
    rm -f install_server.sh
    
    if [[ ! -f "$HY2_BIN" ]]; then
        echo -e "${Error} Hysteria 2 安装失败"
        return 1
    fi
    echo -e "${Info} Hysteria 2 安装成功"
    
    # 配置证书、端口、密码
    hy2_inst_cert || return 1
    hy2_inst_port
    
    read -p "设置密码（回车跳过为随机）：" hy2_auth_pwd
    [[ -z $hy2_auth_pwd ]] && hy2_auth_pwd=$(date +%s%N | md5sum | cut -c 1-8)
    
    read -rp "请输入伪装网站地址 (去除https://) [默认 maimai.sega.jp]：" hy2_proxysite
    [[ -z $hy2_proxysite ]] && hy2_proxysite="maimai.sega.jp"
    
    # 生成服务端配置
    mkdir -p "$HY2_CONFIG_DIR"
    cat << EOF > "$HY2_CONFIG_FILE"
listen: :$hy2_port

tls:
  cert: $hy2_cert_path
  key: $hy2_key_path

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

auth:
  type: password
  password: $hy2_auth_pwd

masquerade:
  type: proxy
  proxy:
    url: https://$hy2_proxysite
    rewriteHost: true
EOF

    # 确定最终端口
    if [[ -n $hy2_firstport ]]; then
        hy2_last_port="$hy2_port,$hy2_firstport-$hy2_endport"
    else
        hy2_last_port=$hy2_port
    fi
    
    # IPv6 地址加中括号
    if [[ -n $(echo $ip | grep ":") ]]; then
        hy2_last_ip="[$ip]"
    else
        hy2_last_ip=$ip
    fi
    
    # 生成客户端配置
    mkdir -p "$HY2_CLIENT_DIR"
    cat << EOF > "$HY2_CLIENT_DIR/hy-client.yaml"
server: $hy2_last_ip:$hy2_last_port
auth: $hy2_auth_pwd
tls:
  sni: $hy2_domain
  insecure: true
quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432
fastOpen: true
socks5:
  listen: 127.0.0.1:5080
transport:
  udp:
    hopInterval: 30s
EOF
    
    # 分享链接
    hy2_url="hysteria2://$hy2_auth_pwd@$hy2_last_ip:$hy2_last_port/?insecure=1&sni=$hy2_domain#Misaka-Hysteria2"
    echo "$hy2_url" > "$HY2_CLIENT_DIR/url.txt"
    
    # Clash Meta 配置
    cat << EOF > "$HY2_CLIENT_DIR/clash-meta.yaml"
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
  - name: Misaka-Hysteria2
    type: hysteria2
    server: $hy2_last_ip
    port: $hy2_port
    password: $hy2_auth_pwd
    sni: $hy2_domain
    skip-cert-verify: true
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Misaka-Hysteria2
rules:
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
EOF
    
    # 启动服务
    systemctl daemon-reload
    systemctl enable hysteria-server
    systemctl start hysteria-server
    
    if [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) ]]; then
        echo -e "${Green}Hysteria 2 服务启动成功${Reset}"
        echo ""
        echo -e "${Yellow}客户端配置文件已保存到 $HY2_CLIENT_DIR/${Reset}"
        echo -e "${Yellow}分享链接:${Reset}"
        echo -e "${Cyan}$(cat $HY2_CLIENT_DIR/url.txt)${Reset}"
    else
        echo -e "${Error} 服务启动失败，请运行 systemctl status hysteria-server 查看"
    fi
}

uninstall_hysteria() {
    echo -e "${Warning} 正在卸载 Hysteria 2..."
    systemctl stop hysteria-server >/dev/null 2>&1
    systemctl disable hysteria-server >/dev/null 2>&1
    rm -f /lib/systemd/system/hysteria-server.service /lib/systemd/system/hysteria-server@.service
    rm -rf "$HY2_BIN" "$HY2_CONFIG_DIR" "$HY2_CLIENT_DIR"
    iptables -t nat -F PREROUTING >/dev/null 2>&1
    netfilter-persistent save >/dev/null 2>&1
    echo -e "${Green}Hysteria 2 已卸载${Reset}"
}

hy2_show_conf() {
    if [[ -f "$HY2_CLIENT_DIR/url.txt" ]]; then
        echo -e "${Yellow}分享链接:${Reset}"
        cat "$HY2_CLIENT_DIR/url.txt"
        echo ""
        echo -e "${Yellow}客户端 YAML 配置:${Reset}"
        cat "$HY2_CLIENT_DIR/hy-client.yaml"
    else
        echo -e "${Error} 配置文件不存在"
    fi
}

hy2_menu() {
    clear
    echo -e "${Cyan}========== Hysteria 2 管理 (Misaka Logic) ==========${Reset}"
    echo -e " ${Green}1.${Reset} 安装 Hysteria 2"
    echo -e " ${Green}2.${Reset} ${Red}卸载 Hysteria 2${Reset}"
    echo " -------------"
    echo -e " ${Green}3.${Reset} 启动 Hysteria 2"
    echo -e " ${Green}4.${Reset} 停止 Hysteria 2"
    echo -e " ${Green}5.${Reset} 重启 Hysteria 2"
    echo " -------------"
    echo -e " ${Green}6.${Reset} 查看配置信息"
    echo -e " ${Green}0.${Reset} 返回"
    echo "=================================================="
    read -p "请选择: " choice

    case "$choice" in
        1) install_hysteria ;;
        2) uninstall_hysteria ;;
        3) systemctl start hysteria-server && systemctl enable hysteria-server && echo -e "${Info} 已启动" ;;
        4) systemctl stop hysteria-server && systemctl disable hysteria-server && echo -e "${Info} 已停止" ;;
        5) systemctl restart hysteria-server && echo -e "${Info} 已重启" ;;
        6) hy2_show_conf ;;
        0) return ;;
        *) echo -e "${Error} 无效选择" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    hy2_menu
fi
