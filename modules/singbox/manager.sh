#!/bin/bash
# sing-box 讓｡蝮� - VPS-play
# 螟壼刻隶ｮ莉｣逅�鰍轤ｹ邂｡逅?
#
# Copyright (C) 2025 VPS-play Contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/singbox"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"
[ -z "$VPSPLAY_DIR" ] && VPSPLAY_DIR="$HOME/vps-play"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/port_manager.sh" ] && source "$VPSPLAY_DIR/utils/port_manager.sh"
[ -f "$VPSPLAY_DIR/utils/process_manager.sh" ] && source "$VPSPLAY_DIR/utils/process_manager.sh"
[ -f "$VPSPLAY_DIR/utils/network.sh" ] && source "$VPSPLAY_DIR/utils/network.sh"

# ==================== 鬚懆牡螳壻ｹ� ====================
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Cyan="\033[36m"
Reset="\033[0m"
Info="${Green}[菫｡諱ｯ]${Reset}"
Error="${Red}[髞呵ｯｯ]${Reset}"
Warning="${Yellow}[隴ｦ蜻馨${Reset}"
Tip="${Cyan}[謠千､ｺ]${Reset}"

# ==================== 驟咲ｽｮ ====================
SINGBOX_DIR="$HOME/.vps-play/singbox"
SINGBOX_BIN="$SINGBOX_DIR/sing-box"
SINGBOX_CONF="$SINGBOX_DIR/config.json"
SINGBOX_LOG="$SINGBOX_DIR/sing-box.log"
CERT_DIR="$SINGBOX_DIR/cert"
CONFIG_DIR="$SINGBOX_DIR/config"

# 豬�㍼扈溯ｮ｡ API 遶ｯ蜿｣ (clash_api)
SINGBOX_API_PORT=9090

# sing-box 迚域悽
SINGBOX_VERSION="1.12.0"
SINGBOX_REPO="https://github.com/SagerNet/sing-box"

mkdir -p "$SINGBOX_DIR" "$CERT_DIR" "$CONFIG_DIR"

# ==================== 蜿よ焚謖∽ｹ�喧蟄伜�?(蜿ら�argosbx) ====================
DATA_DIR="$SINGBOX_DIR/data"
LINKS_FILE="$SINGBOX_DIR/links.txt"
mkdir -p "$DATA_DIR"

# 蛻晏ｧ句�?闔ｷ蜿� UUID (蜿ら�argosbx逧�nsuuid蜃ｽ謨ｰ, 菫ｮ螟孝reeBSD蜈ｼ螳ｹ諤?
init_uuid() {
    # 鬥門�蟆晁ｯ穂ｻ取枚莉ｶ隸ｻ蜿厄ｼ亥ｦよ棡譁�ｻｶ蟄伜惠荳秘撼遨ｺ��
    if [ -s "$DATA_DIR/uuid" ]; then
        uuid=$(cat "$DATA_DIR/uuid")
    fi
    
    # 螯よ棡 uuid 荳ｺ遨ｺ�悟�逕滓�譁ｰ逧�
    if [ -z "$uuid" ]; then
        # 譁ｹ豕�1: 菴ｿ逕ｨ sing-box 逕滓�
        if [ -x "$SINGBOX_BIN" ]; then
            uuid=$("$SINGBOX_BIN" generate uuid 2>/dev/null)
        fi
        # 譁ｹ豕�2: Linux /proc
        [ -z "$uuid" ] && uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
        # 譁ｹ豕�3: uuidgen
        [ -z "$uuid" ] && uuid=$(uuidgen 2>/dev/null)
        # 譁ｹ豕�4: 謇句勘逕滓� (FreeBSD蜈ｼ螳ｹ�御ｽｿ逕?LC_ALL=C 驕ｿ蜈� Illegal byte sequence)
        if [ -z "$uuid" ]; then
            uuid=$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 8)-$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 4)-$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 4)-$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 4)-$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 12)
        fi
        # 譁ｹ豕�5: 菴ｿ逕ｨ od 菴應ｸｺ譛蜷主､��?(FreeBSD)
        if [ -z "$uuid" ] || [ ${#uuid} -lt 32 ]; then
            uuid=$(od -An -tx1 -N 16 /dev/urandom 2>/dev/null | tr -d ' \n' | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/')
        fi
        
        # 菫晏ｭ伜芦譁�ｻ?
        if [ -n "$uuid" ]; then
            if [ ! -d "$DATA_DIR" ]; then
                mkdir -p "$DATA_DIR"
            fi
            echo "$uuid" > "$DATA_DIR/uuid"
        fi
    fi
    
    # 譛扈磯ｪ瑚ｯ?
    if [ -z "$uuid" ]; then
        echo -e "${Error} UUID 逕滓�螟ｱ雍･"
        return 1
    fi
    
    echo -e "${Info} UUID/蟇���ｼ?{Cyan}$uuid${Reset}"
}

# 菫晏ｭ倡ｫｯ蜿｣蛻ｰ譁�ｻ?
save_port() {
    local proto=$1
    local port=$2
    echo "$port" > "$DATA_DIR/port_${proto}"
}

# 隸ｻ蜿也ｫｯ蜿｣
load_port() {
    local proto=$1
    cat "$DATA_DIR/port_${proto}" 2>/dev/null
}

# 闔ｷ蜿匁恪蜉｡蝎ｨIP (蜿ら�argosbx逧�pbest蜃ｽ謨ｰ)
get_server_ip() {
    local serip
    serip=$(curl -s4m5 -k https://icanhazip.com 2>/dev/null || curl -s6m5 -k https://icanhazip.com 2>/dev/null)
    [ -z "$serip" ] && serip=$(curl -s4m5 ip.sb 2>/dev/null || curl -s6m5 ip.sb 2>/dev/null)
    [ -z "$serip" ] && serip="$PUBLIC_IP"
    
    if echo "$serip" | grep -q ':'; then
        server_ip="[$serip]"
    else
        server_ip="$serip"
    fi
    echo "$server_ip" > "$DATA_DIR/server_ip"
    echo "$server_ip"
}

# 逕滓� experimental 驟咲ｽｮ蝮?(蜿ｯ騾会ｼ檎岼蜑堺ｸ堺ｽｿ逕?
# 豬�㍼扈溯ｮ｡蟾ｲ謾ｹ荳ｺ隸ｻ蜿?VPS 邉ｻ扈溽ｽ醍ｻ懈磁蜿｣豬�㍼
get_experimental_config() {
    # 霑泌屓遨ｺ�御ｸ肴ｷｻ蜉?experimental 驟咲ｽｮ
    echo ""
}

# ==================== WARP 蜀�ｽｮ謾ｯ謖� (蜿ら� argosbx) ====================
WARP_DATA_DIR="$SINGBOX_DIR/warp"
mkdir -p "$WARP_DATA_DIR"

# 蜈ｨ螻蜿倬㍼�梧��ｮｰ譏ｯ蜷ｦ蜷ｯ逕?WARP 蜃ｺ遶�
WARP_ENABLED=false

# 蛻晏ｧ句�?闔ｷ蜿� WARP 驟咲ｽｮ (逶ｴ謗･驥�畑 argosbx 逧�婿譯?
init_warp_config() {
    echo -e "${Info} 闔ｷ蜿� WARP 驟咲ｽｮ..."
    
    # 蟆晁ｯ穂ｻ主窮蜩･逧� API 闔ｷ蜿夜｢�ｳｨ蜀碁�鄂?
    local warpurl=""
    warpurl=$(curl -sm5 -k https://ygkkk-warp.renky.eu.org 2>/dev/null) || \
    warpurl=$(wget -qO- --timeout=5 https://ygkkk-warp.renky.eu.org 2>/dev/null)
    
    if echo "$warpurl" | grep -q ygkkk; then
        WARP_PRIVATE_KEY=$(echo "$warpurl" | awk -F'�? '/Private_key/{print $2}' | xargs)
        WARP_IPV6=$(echo "$warpurl" | awk -F'�? '/IPV6/{print $2}' | xargs)
        WARP_RESERVED=$(echo "$warpurl" | awk -F'�? '/reserved/{print $2}' | xargs)
        echo -e "${Info} WARP 驟咲ｽｮ闔ｷ蜿匁�蜉� (霑懃ｨ�)"
    else
        # 螟�畑遑ｬ郛也���鄂?(蜥?argosbx 荳譬?
        WARP_IPV6='2606:4700:110:8d8d:1845:c39f:2dd5:a03a'
        WARP_PRIVATE_KEY='52cuYFgCJXp0LAq7+nWJIbCXXgU9eGggOc+Hlfz5u6A='
        WARP_RESERVED='[215, 69, 233]'
        echo -e "${Info} WARP 驟咲ｽｮ闔ｷ蜿匁�蜉� (螟�畑)"
    fi
    
    # 菫晏ｭ倬�鄂ｮ萓帛錘扈ｭ菴ｿ逕?(遑ｮ菫晉岼蠖募ｭ伜惠)
    mkdir -p "$WARP_DATA_DIR"
    echo "$WARP_PRIVATE_KEY" > "$WARP_DATA_DIR/private_key"
    echo "$WARP_RESERVED" > "$WARP_DATA_DIR/reserved"
    echo "$WARP_IPV6" > "$WARP_DATA_DIR/ipv6"
    
    return 0
}

# 隸｢髣ｮ譏ｯ蜷ｦ蜷ｯ逕ｨ WARP 蜃ｺ遶�
ask_warp_outbound() {
    echo -e ""
    echo -e "${Cyan}譏ｯ蜷ｦ蜷ｯ逕ｨ WARP 蜃ｺ遶吩ｻ｣逅�?${Reset}"
    echo -e "${Tip} 蜷ｯ逕ｨ蜷趣ｼ瑚鰍轤ｹ豬�㍼蟆�夊ｿ� Cloudflare WARP 蜃ｺ遶�"
    echo -e "${Tip} 蜿ｯ逕ｨ莠手ｧ｣髞∵ｵ∝ｪ剃ｽ薙�嚼阯冗悄螳?IP 遲?
    echo -e ""
    read -p "蜷ｯ逕ｨ WARP 蜃ｺ遶�? [y/N]: " enable_warp
    
    if [[ "$enable_warp" =~ ^[Yy]$ ]]; then
        if init_warp_config; then
            WARP_ENABLED=true
            echo -e "${Info} WARP 蜃ｺ遶吝ｷｲ蜷ｯ逕?
            
            # 譽譟･譏ｯ蜷ｦ蟾ｲ譛我ｼ倬?Endpoint
            local warp_endpoint_file="$HOME/.vps-play/warp/data/endpoint"
            if [ ! -f "$warp_endpoint_file" ]; then
                echo -e ""
                echo -e "${Tip} 譽豬句芦蟆壽悴霑幄｡� Endpoint 莨倬?
                echo -e "${Tip} 莨倬牙庄莉･謇ｾ蛻ｰ譛菴ｳ逧� WARP 霑樊磁轤ｹ�梧署蜊�溷ｺｦ"
                read -p "譏ｯ蜷ｦ霑幄｡� Endpoint IP 莨倬? [y/N]: " do_optimize
                
                if [[ "$do_optimize" =~ ^[Yy]$ ]]; then
                    # 隹�畑 WARP 讓｡蝮礼噪莨倬牙�謨?
                    local warp_manager="$VPSPLAY_DIR/modules/warp/manager.sh"
                    if [ -f "$warp_manager" ]; then
                        source "$warp_manager"
                        run_endpoint_optimize false
                    else
                        echo -e "${Warning} WARP 讓｡蝮玲悴謇ｾ蛻ｰ�瑚ｷｳ霑�ｼ倬?
                    fi
                fi
            else
                local current_ep=$(cat "$warp_endpoint_file" 2>/dev/null)
                echo -e "${Info} 菴ｿ逕ｨ蟾ｲ菫晏ｭ倡噪莨倬?Endpoint: ${Cyan}$current_ep${Reset}"
            fi
        else
            WARP_ENABLED=false
            echo -e "${Warning} WARP 驟咲ｽｮ螟ｱ雍･�悟ｰ�ｽｿ逕ｨ逶ｴ霑槫�遶�"
        fi
    else
        WARP_ENABLED=false
    fi
}

# 闔ｷ蜿� WARP Endpoint 驟咲ｽｮ (莨伜�菴ｿ逕ｨ WARP 讓｡蝮礼噪莨倬臥ｻ捺�?
# 闔ｷ蜿� WARP Endpoint 驟咲ｽｮ (莨伜�菴ｿ逕ｨ WARP 讓｡蝮礼噪莨倬臥ｻ捺�?
get_warp_endpoint() {
    # 莨伜�隸ｻ蜿� WARP 讓｡蝮嶺ｿ晏ｭ倡噪莨倬?Endpoint
    local warp_endpoint_file="$HOME/.vps-play/warp/data/endpoint"
    if [ -f "$warp_endpoint_file" ]; then
        local saved_ep=$(cat "$warp_endpoint_file" 2>/dev/null)
        if [ -n "$saved_ep" ]; then
            echo "$saved_ep"
            return 0
        fi
    fi
    
    # 蝗樣: 譽豬狗ｽ醍ｻ懃識蠅�画叫鮟倩ｮ､ Endpoint
    local has_ipv4=false
    local has_ipv6=false
    
    # 譽豬狗ｽ醍ｻ懃識蠅?
    curl -s4m2 https://www.cloudflare.com/cdn-cgi/trace -k 2>/dev/null | grep -q "warp" && has_ipv4=true
    curl -s6m2 https://www.cloudflare.com/cdn-cgi/trace -k 2>/dev/null | grep -q "warp" && has_ipv6=true
    
    # 螟�畑譽豬?
    if [ "$has_ipv4" = false ] && [ "$has_ipv6" = false ]; then
        ip -4 route show default 2>/dev/null | grep -q default && has_ipv4=true
        ip -6 route show default 2>/dev/null | grep -q default && has_ipv6=true
    fi
    
    if [ "$has_ipv6" = true ] && [ "$has_ipv4" = false ]; then
        # 郤?IPv6 邇ｯ蠅�
        echo "[2606:4700:d0::a29f:c001]:2408"
    else
        # IPv4 謌門曙譬茨ｼ御ｽｿ逕ｨ鮟倩ｮ､ IP
        echo "162.159.192.1:2408"
    fi
}

# 逕滓� outbounds 蜥?route 驟咲ｽｮ
# 蜿よ焚: $1 = 譏ｯ蜷ｦ蜷ｯ逕ｨ WARP (true/false)
# 蜿ら� argosbx 逧�ｮ樒鴫��
# - 荳榊星逕?WARP: 蜿ｪ譛� direct outbound�梧裏 route 驟咲ｽｮ
# - 蜷ｯ逕ｨ WARP: outbounds (direct) + endpoints (warp-out) + route (final謖�髄warp-out)
get_outbounds_config() {
    local enable_warp=${1:-false}
    
    if [ "$enable_warp" = true ] && [ -n "$WARP_PRIVATE_KEY" ]; then
        local warp_endpoint=$(get_warp_endpoint)
        local warp_ipv6="${WARP_IPV6:-2606:4700:110:8f1a:c53:a4c5:2249:1546}"
        local warp_reserved="${WARP_RESERVED:-[0,0,0]}"
        
        # 隗｣譫� Endpoint IP 蜥檎ｫｯ蜿?
        local ep_ip=""
        local ep_port="2408"
        
        if echo "$warp_endpoint" | grep -q "]:"; then
            # IPv6 譬ｼ蠑� [ip]:port
            ep_ip=$(echo "$warp_endpoint" | sed 's/\]:.*/]/' | sed 's/^\[//' | sed 's/\]$//')
            ep_port=$(echo "$warp_endpoint" | sed 's/.*\]://')
        elif echo "$warp_endpoint" | grep -q ":"; then
            # IPv4 譬ｼ蠑� ip:port
            ep_ip=$(echo "$warp_endpoint" | cut -d: -f1)
            ep_port=$(echo "$warp_endpoint" | cut -d: -f2)
        else
            ep_ip="$warp_endpoint"
        fi
        
        # 菴ｿ逕ｨ Sing-box 1.12+ 逧?endpoints 蟄玲ｮｵ (argosbx 譁ｹ譯�)
        cat << WARP_EOF
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp-out",
      "address": [
        "172.16.0.2/32",
        "${warp_ipv6}/128"
      ],
      "private_key": "${WARP_PRIVATE_KEY}",
      "peers": [
        {
          "address": "${ep_ip}",
          "port": ${ep_port},
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": [
            "0.0.0.0/0",
            "::/0"
          ],
          "reserved": ${warp_reserved}
        }
      ]
    }
  ],
  "route": {
    "rules": [
      {
        "action": "sniff"
      },
      {
        "action": "resolve",
        "strategy": "prefer_ipv4"
      }
    ],
    "final": "warp-out"
  }
WARP_EOF
    else
        # 鮟倩ｮ､逶ｴ霑槫�遶� (蜿ら� argosbx: 荳榊星逕?WARP 譌ｶ譌� route 驟咲ｽｮ)
        cat << DIRECT_EOF
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
DIRECT_EOF
    fi
}

# ==================== 邉ｻ扈滓｣豬?====================
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Alpine")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "apk update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "apk add")

detect_system() {
    if [ -z "$OS_DISTRO" ]; then
        for i in /etc/os-release /etc/lsb-release /etc/redhat-release; do
            [ -f "$i" ] && SYS=$(cat "$i" | tr '[:upper:]' '[:lower:]')
        done
        
        for ((int = 0; int < ${#REGEX[@]}; int++)); do
            if [[ $SYS =~ ${REGEX[int]} ]]; then
                SYSTEM="${RELEASE[int]}"
                PKG_UPDATE="${PACKAGE_UPDATE[int]}"
                PKG_INSTALL="${PACKAGE_INSTALL[int]}"
                break
            fi
        done
    fi
}

# ==================== 闔ｷ蜿� IP ====================
get_ip() {
    ip=$(curl -s4m5 ip.sb 2>/dev/null) || ip=$(curl -s6m5 ip.sb 2>/dev/null)
    [ -z "$ip" ] && ip="$PUBLIC_IP"
    echo "$ip"
}

# ==================== 隸∽ｹｦ邂｡逅� ====================
generate_self_signed_cert() {
    local domain=${1:-www.bing.com}
    
    echo -e "${Info} 逕滓�閾ｪ遲ｾ蜷崎ｯ∽ｹ?(蝓溷錐: $domain)..."
    
    if [ ! -d "$CERT_DIR" ]; then
        mkdir -p "$CERT_DIR"
    fi
    
    # 蜿ら� argosbx: 菴ｿ逕ｨ openssl 逕滓� EC 隸∽ｹｦ
    if command -v openssl >/dev/null 2>&1; then
        openssl ecparam -genkey -name prime256v1 -out "$CERT_DIR/private.key" >/dev/null 2>&1
        openssl req -new -x509 -days 36500 -key "$CERT_DIR/private.key" -out "$CERT_DIR/cert.pem" -subj "/CN=$domain" >/dev/null 2>&1
    fi
    
    # 螯よ棡逕滓�螟ｱ雍･�御ｻ� GitHub 荳玖ｽｽ螟�ｻｽ隸∽ｹｦ (蜿ら� argosbx)
    if [ ! -f "$CERT_DIR/private.key" ] || [ ! -f "$CERT_DIR/cert.pem" ]; then
        echo -e "${Warning} 譛ｬ蝨ｰ隸∽ｹｦ逕滓�螟ｱ雍･�梧ｭ｣蝨ｨ荳玖ｽｽ螟�畑隸∽ｹ?.."
        
        if command -v curl >/dev/null 2>&1; then
            curl -Ls -o "$CERT_DIR/private.key" "https://github.com/yonggekkk/argosbx/releases/download/argosbx/private.key" 2>/dev/null
            curl -Ls -o "$CERT_DIR/cert.pem" "https://github.com/yonggekkk/argosbx/releases/download/argosbx/cert.pem" 2>/dev/null
        elif command -v wget >/dev/null 2>&1; then
            timeout 3 wget -q -O "$CERT_DIR/private.key" "https://github.com/yonggekkk/argosbx/releases/download/argosbx/private.key" --tries=2 2>/dev/null
            timeout 3 wget -q -O "$CERT_DIR/cert.pem" "https://github.com/yonggekkk/argosbx/releases/download/argosbx/cert.pem" --tries=2 2>/dev/null
        fi
    fi
    
    if [ -f "$CERT_DIR/cert.pem" ] && [ -f "$CERT_DIR/private.key" ]; then
        chmod 644 "$CERT_DIR/cert.pem" "$CERT_DIR/private.key"
        echo -e "${Info} 隸∽ｹｦ蜃�､�ｮ梧�"
        echo -e " 隸∽ｹｦ霍ｯ蠕�: ${Cyan}$CERT_DIR/cert.pem${Reset}"
        echo -e " 遘�徴霍ｯ蠕�: ${Cyan}$CERT_DIR/private.key${Reset}"
        return 0
    else
        echo -e "${Error} 隸∽ｹｦ逕滓�/荳玖ｽｽ螟ｱ雍･"
        return 1
    fi
}

apply_acme_cert() {
    echo -e "${Info} 菴ｿ逕ｨ ACME 逕ｳ隸ｷ逵溷ｮ櫁ｯ∽ｹｦ"
    
    read -p "隸ｷ霎灘�蝓溷�? " domain
    [ -z "$domain" ] && { echo -e "${Error} 蝓溷錐荳崎�荳ｺ遨ｺ"; return 1; }
    
    # 譽譟･蝓溷錐隗｣譫?
    local domain_ip=$(dig +short "$domain" 2>/dev/null | head -1)
    local server_ip=$(get_ip)
    
    if [ "$domain_ip" != "$server_ip" ]; then
        echo -e "${Warning} 蝓溷錐隗｣譫千�?IP ($domain_ip) 荳取恪蜉｡蝎ｨ IP ($server_ip) 荳榊源驟?
        read -p "譏ｯ蜷ｦ扈ｧ扈ｭ? [y/N]: " continue_acme
        [[ ! $continue_acme =~ ^[Yy]$ ]] && return 1
    fi
    
    # 螳芽｣� acme.sh
    if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        echo -e "${Info} 螳芽｣� acme.sh..."
        curl https://get.acme.sh | sh -s email=$(date +%s)@gmail.com
    fi
    
    # 逕ｳ隸ｷ隸∽ｹｦ
    echo -e "${Info} 逕ｳ隸ｷ隸∽ｹｦ..."
    ~/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 --insecure
    ~/.acme.sh/acme.sh --install-cert -d "$domain" \
        --key-file "$CERT_DIR/private.key" \
        --fullchain-file "$CERT_DIR/cert.pem" \
        --ecc
    
    if [ -f "$CERT_DIR/cert.pem" ] && [ -s "$CERT_DIR/cert.pem" ]; then
        echo "$domain" > "$CERT_DIR/domain.txt"
        echo -e "${Info} 隸∽ｹｦ逕ｳ隸ｷ謌仙粥"
        return 0
    else
        echo -e "${Error} 隸∽ｹｦ逕ｳ隸ｷ螟ｱ雍･"
        return 1
    fi
}

cert_menu() {
    echo -e ""
    echo -e "${Info} 隸∽ｹｦ逕ｳ隸ｷ譁ｹ蠑�:"
    echo -e " ${Green}1.${Reset} 閾ｪ遲ｾ蜷崎ｯ∽ｹ?(鮟倩ｮ､�梧耳闕?"
    echo -e " ${Green}2.${Reset} ACME 逕ｳ隸ｷ逵溷ｮ櫁ｯ∽ｹｦ"
    echo -e " ${Green}3.${Reset} 菴ｿ逕ｨ蟾ｲ譛芽ｯ∽ｹｦ"
    
    read -p "隸ｷ騾画叫 [1-3]: " cert_choice
    cert_choice=${cert_choice:-1}
    
    case "$cert_choice" in
        1)
            read -p "莨ｪ陬�沺蜷� [www.bing.com]: " fake_domain
            fake_domain=${fake_domain:-www.bing.com}
            if ! generate_self_signed_cert "$fake_domain"; then
                return 1
            fi
            CERT_DOMAIN="$fake_domain"
            ;;
        2)
            if ! apply_acme_cert; then
                return 1
            fi
            CERT_DOMAIN=$(cat "$CERT_DIR/domain.txt" 2>/dev/null)
            ;;
        3)
            read -p "隸∽ｹｦ霍ｯ蠕�: " custom_cert
            read -p "遘�徴霍ｯ蠕�: " custom_key
            if [ -f "$custom_cert" ] && [ -f "$custom_key" ]; then
                cp "$custom_cert" "$CERT_DIR/cert.pem"
                cp "$custom_key" "$CERT_DIR/private.key"
                read -p "隸∽ｹｦ蝓溷錐: " CERT_DOMAIN
            else
                echo -e "${Error} 隸∽ｹｦ譁�ｻｶ荳榊ｭ伜�?
                return 1
            fi
            ;;
    esac
}

# ==================== 遶ｯ蜿｣驟咲ｽｮ ====================
config_port() {
    local proto_name=$1
    local default_port=$2
    
    echo -e "" >&2
    # read -p 霎灘�鮟倩ｮ､蟆ｱ譏ｯ stderr�梧園莉･荳咲畑謾ｹ
    read -p "隶ｾ鄂ｮ $proto_name 遶ｯ蜿｣ [逡咏ｩｺ髫乗惻]: " port
    
    if [ -z "$port" ]; then
        port=$(shuf -i 10000-65535 -n 1)
    fi
    
    # 譽譟･遶ｯ蜿｣譏ｯ蜷ｦ陲ｫ蜊�逕ｨ
    while ss -tunlp 2>/dev/null | grep -qw ":$port "; do
        echo -e "${Warning} 遶ｯ蜿｣ $port 蟾ｲ陲ｫ蜊�逕ｨ" >&2
        port=$(shuf -i 10000-65535 -n 1)
        echo -e "${Info} 閾ｪ蜉ｨ蛻��譁ｰ遶ｯ蜿? $port" >&2
    done
    
    echo -e "${Info} 菴ｿ逕ｨ遶ｯ蜿｣: ${Cyan}$port${Reset}" >&2
    echo "$port"
}

# ==================== 荳玖ｽｽ螳芽｣� ====================
# 闔ｷ蜿門ｽ灘燕螳芽｣�沿譛ｬ
get_version() {
    if [ -f "$SINGBOX_BIN" ]; then
        $SINGBOX_BIN version 2>/dev/null | head -n1 | awk '{print $3}'
    
    # 遑ｮ菫晉岼蠖募ｭ伜惠
    mkdir -p "$SINGBOX_DIR" "$CERT_DIR" "$CONFIG_DIR"
    
    # 逶ｴ謗･菴ｿ逕ｨ uname 譽豬狗ｳｻ扈溽ｱｻ蝙?(菫ｮ螟� Serv00/FreeBSD 譽豬?
    local os_type
    local arch_type
    
    case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
        freebsd) os_type="freebsd" ;;
        linux) os_type="linux" ;;
        darwin) os_type="darwin" ;;
        *) os_type="linux" ;;
    esac
    
    case "$(uname -m)" in
        x86_64|amd64) arch_type="amd64" ;;
        aarch64|arm64) arch_type="arm64" ;;
        armv7l) arch_type="armv7" ;;
        i386|i686) arch_type="386" ;;
        *) arch_type="amd64" ;;
    esac
    
    echo -e "${Info} 譽豬句芦邉ｻ扈�: ${os_type}-${arch_type}"
    
    local download_url="${SINGBOX_REPO}/releases/download/v${target_version}/sing-box-${target_version}-${os_type}-${arch_type}.tar.gz"
    
    cd "$SINGBOX_DIR" || { echo -e "${Error} 譌�豕戊ｿ帛�逶ｮ蠖�"; return 1; }
    
    # 螟�ｻｽ譌ｧ迚域�?
    [ -f "$SINGBOX_BIN" ] && mv "$SINGBOX_BIN" "${SINGBOX_BIN}.bak"
    
    # 荳玖ｽｽ蟷ｶ隗｣蜴?
    echo -e "${Info} 荳玖ｽｽ蝨ｰ蝮: $download_url"
    
    local download_success=false
    
    # 蟆晁ｯ穂ｽｿ逕ｨ wget 荳玖ｽｽ
    if command -v wget >/dev/null 2>&1; then
        if wget -q -O sing-box.tar.gz "$download_url"; then
            download_success=true
        else
             echo -e "${Warning} wget 荳玖ｽｽ螟ｱ雍･�悟ｰ晁ｯ?curl..."
        fi
    fi
    
    # 蟆晁ｯ穂ｽｿ逕ｨ curl 荳玖ｽｽ (螯よ棡 wget 螟ｱ雍･謌匁悴螳芽｣�)
    if [ "$download_success" = false ] && command -v curl >/dev/null 2>&1; then
        if curl -sL "$download_url" -o sing-box.tar.gz; then
            download_success=true
        else
            echo -e "${Error} curl 荳玖ｽｽ螟ｱ雍･"
        fi
    fi
    
    if [ "$download_success" = false ]; then
        echo -e "${Error} 譌�豕穂ｸ玖ｽｽ sing-box�瑚ｯｷ譽譟･鄂醍ｻ懆ｿ樊磁謌門ｮ芽｣� wget/curl"
        [ -f "${SINGBOX_BIN}.bak" ] && mv "${SINGBOX_BIN}.bak" "$SINGBOX_BIN"
        return 1
    fi
    
    # 譽譟･譁�ｻｶ螟ｧ蟆?(驕ｿ蜈堺ｸ玖ｽｽ蛻ｰ遨ｺ譁�ｻｶ)
    if [ ! -s sing-box.tar.gz ]; then
        echo -e "${Error} 荳玖ｽｽ逧�枚莉ｶ荳ｺ遨?
        rm -f sing-box.tar.gz
        [ -f "${SINGBOX_BIN}.bak" ] && mv "${SINGBOX_BIN}.bak" "$SINGBOX_BIN"
        return 1
    fi

    # 邂蜊墓｣譟･譁�ｻｶ螟ｴ譏ｯ蜷ｦ荳?gzip (1f 8b)
    # 菴ｿ逕ｨ hexdump 謌?od�悟ｦよ棡驛ｽ豐｡譛牙�蟆晁ｯ慕峩謗･隗｣蜴?
    local is_gzip=true
    if command -v head >/dev/null 2>&1 && command -v od >/dev/null 2>&1; then
        local magic=$(head -c 2 sing-box.tar.gz | od -An -t x1 | tr -d ' \n')
        if [ "$magic" != "1f8b" ]; then
            echo -e "${Error} 荳玖ｽｽ逧�枚莉ｶ荳肴弍譛画譜逧� gzip 譁�ｻｶ (Magic: $magic)"
            # 蜿ｯ閭ｽ譏?HTML 髞呵ｯｯ鬘ｵ髱｢�梧仞遉ｺ蜑榊�陦�
            echo -e "${Info} 譁�ｻｶ蜀�ｮｹ鬚�ｧ�:"
            head -n 5 sing-box.tar.gz
            is_gzip=false
        fi
    fi

    if [ "$is_gzip" = false ]; then
        rm -f sing-box.tar.gz
        [ -f "${SINGBOX_BIN}.bak" ] && mv "${SINGBOX_BIN}.bak" "$SINGBOX_BIN"
        return 1
    fi
    
    # 隗｣蜴� (FreeBSD 蜈ｼ螳ｹ)
    local extract_success=false
    if command -v gtar >/dev/null 2>&1; then
        gtar -xzf sing-box.tar.gz --strip-components=1 && extract_success=true
    else
        tar -xzf sing-box.tar.gz --strip-components=1 && extract_success=true
    fi
    
    if [ "$extract_success" = false ]; then
        echo -e "${Error} 隗｣蜴句､ｱ雍･"
        rm -f sing-box.tar.gz
        [ -f "${SINGBOX_BIN}.bak" ] && mv "${SINGBOX_BIN}.bak" "$SINGBOX_BIN"
        return 1
    fi
    
    rm -f sing-box.tar.gz
    chmod +x sing-box 2>/dev/null
    
    if [ -f "$SINGBOX_BIN" ] && [ -x "$SINGBOX_BIN" ]; then
        echo -e "${Info} sing-box 荳玖ｽｽ螳梧�"
        $SINGBOX_BIN version
    else
        echo -e "${Error} 螳芽｣�､ｱ雍･�瑚ｿ伜次譌ｧ迚域悽..."
        [ -f "${SINGBOX_BIN}.bak" ] && mv "${SINGBOX_BIN}.bak" "$SINGBOX_BIN"
        return 1
    fi
}

# ==================== Hysteria2 驟咲ｽｮ ====================
install_hysteria2() {
    echo -e ""
    echo -e "${Cyan}========== 螳芽｣� Hysteria2 闃らせ ==========${Reset}"
    
    # 遑ｮ菫� sing-box 蟾ｲ螳芽｣?
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 蛻晏ｧ句�?UUID 菴應ｸｺ蟇���
    init_uuid
    local password="$uuid"
    
    # 驟咲ｽｮ隸∽ｹｦ
    cert_menu
    
    # 驟咲ｽｮ遶ｯ蜿｣ (蟆晁ｯ戊ｯｻ蜿門ｷｲ菫晏ｭ倡噪遶ｯ蜿｣)
    local saved_port=$(load_port "hy2")
    if [ -n "$saved_port" ]; then
        echo -e "${Info} 譽豬句芦蟾ｲ菫晏ｭ倡噪遶ｯ蜿｣: $saved_port"
        read -p "菴ｿ逕ｨ豁､遶ｯ蜿? [Y/n]: " use_saved
        if [[ ! $use_saved =~ ^[Nn]$ ]]; then
            port="$saved_port"
        else
            port=$(config_port "Hysteria2")
        fi
    else
        port=$(config_port "Hysteria2")
    fi
    
    # 菫晏ｭ倡ｫｯ蜿｣
    save_port "hy2" "$port"
    echo -e "${Info} Hysteria2 遶ｯ蜿｣: ${Cyan}$port${Reset}"
    
    # 遶ｯ蜿｣霍ｳ霍�
    echo -e ""
    echo -e "${Info} 譏ｯ蜷ｦ蜷ｯ逕ｨ遶ｯ蜿｣霍ｳ霍�?"
    echo -e " ${Green}1.${Reset} 蜷ｦ�悟黒遶ｯ蜿?(鮟倩ｮ､)"
    echo -e " ${Green}2.${Reset} 譏ｯ�檎ｫｯ蜿｣霍ｳ霍�"
    read -p "隸ｷ騾画叫 [1-2]: " jump_choice
    
    local port_hopping=""
    if [ "$jump_choice" = "2" ]; then
        read -p "襍ｷ蟋狗ｫｯ蜿｣: " start_port
        read -p "扈捺據遶ｯ蜿｣: " end_port
        if [ -n "$start_port" ] && [ -n "$end_port" ]; then
            # 隶ｾ鄂ｮ iptables 隗��
            iptables -t nat -A PREROUTING -p udp --dport ${start_port}:${end_port} -j REDIRECT --to-ports $port 2>/dev/null
            ip6tables -t nat -A PREROUTING -p udp --dport ${start_port}:${end_port} -j REDIRECT --to-ports $port 2>/dev/null
            port_hopping="${start_port}-${end_port}"
            echo "$port_hopping" > "$DATA_DIR/hy2_hopping"
            echo -e "${Info} 遶ｯ蜿｣霍ｳ霍�ｷｲ驟咲ｽ? $port_hopping -> $port"
        fi
    fi
    
    # 隸｢髣ｮ譏ｯ蜷ｦ蜷ｯ逕ｨ WARP 蜃ｺ遶�
    ask_warp_outbound
    
    # 逕滓�驟咲ｽｮ
    local exp_config=$(get_experimental_config)
    local outbounds_config=$(get_outbounds_config "$WARP_ENABLED")
    
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
${exp_config}  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-sb",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "password": "$password"
        }
      ],
      "ignore_client_bandwidth": false,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$CERT_DIR/cert.pem",
        "key_path": "$CERT_DIR/private.key"
      }
    }
  ],
${outbounds_config}
}
EOF

    echo -e ""
    echo -e "${Green}========== Hysteria2 螳芽｣�ｮ梧� ==========${Reset}"
    
    # 譏ｾ遉ｺ闃らせ菫｡諱ｯ
    display_all_nodes
    
    # 隸｢髣ｮ譏ｯ蜷ｦ蜷ｯ蜉ｨ
    read -p "譏ｯ蜷ｦ遶句叉蜷ｯ蜉ｨ? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}


# ==================== AnyTLS 驟咲ｽｮ ====================
install_anytls() {
    echo -e ""
    echo -e "${Cyan}========== 螳芽｣� AnyTLS 闃らせ ==========${Reset}"
    
    # 1. 迚域悽譽譟･荳主合郤ｧ
    local min_ver="1.12.0"
    local current_ver=""
    
    if [ -f "$SINGBOX_BIN" ]; then
        current_ver=$($SINGBOX_BIN version 2>/dev/null | head -n1 | awk '{print $3}')
    fi
    
    if [ -z "$current_ver" ] || ! version_ge "$current_ver" "$min_ver"; then
        echo -e "${Warning} AnyTLS 髴隕?sing-box v${min_ver}+ (蠖灘燕: ${current_ver:-譛ｪ螳芽｣�)"
        echo -e "${Info} 豁｣蝨ｨ閾ｪ蜉ｨ蜊�ｺｧ蜀��ｸ..."
        download_singbox "$min_ver"
        if [ $? -ne 0 ]; then
             echo -e "${Error} 蜀��ｸ蜊�ｺｧ螟ｱ雍･�梧裏豕募ｮ芽｣?AnyTLS"
             return 1
        fi
    fi
    
    # 2. 蛻晏ｧ句�?UUID 菴應ｸｺ蟇���
    init_uuid
    local password="$uuid"
    
    # 3. 驟咲ｽｮ遶ｯ蜿｣ (蟆晁ｯ戊ｯｻ蜿門ｷｲ菫晏ｭ倡噪遶ｯ蜿｣)
    local saved_port=$(load_port "anytls")
    if [ -n "$saved_port" ]; then
        echo -e "${Info} 譽豬句芦蟾ｲ菫晏ｭ倡噪遶ｯ蜿｣: $saved_port"
        read -p "菴ｿ逕ｨ豁､遶ｯ蜿? [Y/n]: " use_saved
        if [[ ! $use_saved =~ ^[Nn]$ ]]; then
            port="$saved_port"
        else
            port=$(config_port "AnyTLS")
        fi
    else
        port=$(config_port "AnyTLS")
    fi
    
    # 菫晏ｭ倡ｫｯ蜿｣
    save_port "anytls" "$port"
    echo -e "${Info} AnyTLS 遶ｯ蜿｣: ${Cyan}$port${Reset}"
    
    # 4. 逕滓�閾ｪ遲ｾ隸∽ｹｦ�亥盾辣?argosbx 扈滉ｸ隸∽ｹｦ邂｡逅�ｼ?
    echo -e "${Info} 逕滓�閾ｪ遲ｾ隸∽ｹｦ..."
    if ! generate_self_signed_cert "bing.com"; then
        echo -e "${Error} 隸∽ｹｦ蜃�､�､ｱ雍･"
        return 1
    fi
    
    # 5. 隸｢髣ｮ譏ｯ蜷ｦ蜷ｯ逕ｨ WARP 蜃ｺ遶�
    ask_warp_outbound
    
    # 6. 逕滓�驟咲ｽｮ譁�ｻｶ
    local outbounds_config=$(get_outbounds_config "$WARP_ENABLED")
    
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-sb",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "password": "$password"
        }
      ],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "certificate_path": "$CERT_DIR/cert.pem",
        "key_path": "$CERT_DIR/private.key"
      }
    }
  ],
${outbounds_config}
}
EOF

    echo -e ""
    echo -e "${Green}========== AnyTLS 螳芽｣�ｮ梧� ==========${Reset}"
    
    # 譏ｾ遉ｺ闃らせ菫｡諱ｯ
    display_all_nodes
    
    # 隸｢髣ｮ譏ｯ蜷ｦ蜷ｯ蜉ｨ
    read -p "譏ｯ蜷ｦ遶句叉蜷ｯ蜉ｨ? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# ==================== Any-Reality 驟咲ｽｮ (AnyTLS + Reality) ====================
install_any_reality() {
    echo -e ""
    echo -e "${Cyan}========== 螳芽｣� Any-Reality 闃らせ ==========${Reset}"
    echo -e "${Info} Any-Reality 譏?AnyTLS 蜊剰ｮｮ荳?Reality 逧�ｻ��?
    
    # 1. 迚域悽譽譟･荳主合郤ｧ
    local min_ver="1.12.0"
    local current_ver=""
    
    if [ -f "$SINGBOX_BIN" ]; then
        current_ver=$($SINGBOX_BIN version 2>/dev/null | head -n1 | awk '{print $3}')
    fi
    
    if [ -z "$current_ver" ] || ! version_ge "$current_ver" "$min_ver"; then
        echo -e "${Warning} Any-Reality 髴隕?sing-box v${min_ver}+ (蠖灘燕: ${current_ver:-譛ｪ螳芽｣�)"
        echo -e "${Info} 豁｣蝨ｨ閾ｪ蜉ｨ蜊�ｺｧ蜀��ｸ..."
        download_singbox "$min_ver"
        if [ $? -ne 0 ]; then
             echo -e "${Error} 蜀��ｸ蜊�ｺｧ螟ｱ雍･�梧裏豕募ｮ芽｣?Any-Reality"
             return 1
        fi
    fi
    
    # 2. 蛻晏ｧ句�?UUID 菴應ｸｺ蟇���
    init_uuid
    local password="$uuid"
    
    # 3. 驟咲ｽｮ遶ｯ蜿｣ (蟆晁ｯ戊ｯｻ蜿門ｷｲ菫晏ｭ倡噪遶ｯ蜿｣)
    local saved_port=$(load_port "anyreality")
    if [ -n "$saved_port" ]; then
        echo -e "${Info} 譽豬句芦蟾ｲ菫晏ｭ倡噪遶ｯ蜿｣: $saved_port"
        read -p "菴ｿ逕ｨ豁､遶ｯ蜿? [Y/n]: " use_saved
        if [[ ! $use_saved =~ ^[Nn]$ ]]; then
            port="$saved_port"
        else
            port=$(config_port "Any-Reality")
        fi
    else
        port=$(config_port "Any-Reality")
    fi
    
    # 菫晏ｭ倡ｫｯ蜿｣
    save_port "anyreality" "$port"
    echo -e "${Info} Any-Reality 遶ｯ蜿｣: ${Cyan}$port${Reset}"
    
    # 4. Reality 驟咲ｽｮ
    echo -e ""
    read -p "逶ｮ譬�ｽ醍ｫ� (dest) [apple.com]: " dest
    dest=${dest:-apple.com}
    echo "$dest" > "$DATA_DIR/ym_vl_re"
    
    read -p "Server Name [${dest}]: " server_name
    server_name=${server_name:-$dest}
    
    # 5. 逕滓� Reality 蟇�徴蟇?(蜿ら�argosbx)
    echo -e "${Info} 逕滓� Reality 蟇�徴蟇?.."
    mkdir -p "$CERT_DIR/reality"
    
    if [ -e "$CERT_DIR/reality/private_key" ]; then
        # 蟾ｲ蟄伜惠�瑚ｯｻ蜿�
        private_key=$(cat "$CERT_DIR/reality/private_key")
        public_key=$(cat "$CERT_DIR/reality/public_key")
        short_id=$(cat "$CERT_DIR/reality/short_id")
        echo -e "${Info} 菴ｿ逕ｨ蟾ｲ蟄伜惠逧� Reality 蟇�徴"
    else
        # 逕滓�譁ｰ蟇�徴蟇ｹ
        local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
        private_key=$(echo "$keypair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
        public_key=$(echo "$keypair" | awk '/PublicKey/ {print $2}' | tr -d '"')
        short_id=$($SINGBOX_BIN generate rand --hex 4 2>/dev/null || head /dev/urandom | tr -dc a-f0-9 | head -c 8)
        
        # 菫晏ｭ�
        echo "$private_key" > "$CERT_DIR/reality/private_key"
        echo "$public_key" > "$CERT_DIR/reality/public_key"
        echo "$short_id" > "$CERT_DIR/reality/short_id"
        echo -e "${Info} Reality 蟇�徴逕滓�螳梧�"
    fi
    
    # 6. 隸｢髣ｮ譏ｯ蜷ｦ蜷ｯ逕ｨ WARP 蜃ｺ遶�
    ask_warp_outbound
    
    # 7. 逕滓�驟咲ｽｮ譁�ｻｶ
    local outbounds_config=$(get_outbounds_config "$WARP_ENABLED")
    
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anyreality-sb",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "password": "$password"
        }
      ],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "server_name": "$server_name",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$dest",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    }
  ],
${outbounds_config}
}
EOF

    echo -e ""
    echo -e "${Green}========== Any-Reality 螳芽｣�ｮ梧� ==========${Reset}"
    
    # 譏ｾ遉ｺ闃らせ菫｡諱ｯ
    display_all_nodes
    
    # 隸｢髣ｮ譏ｯ蜷ｦ蜷ｯ蜉ｨ
    read -p "譏ｯ蜷ｦ遶句叉蜷ｯ蜉ｨ? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# ==================== TUIC 驟咲ｽｮ ====================
install_tuic() {
    echo -e ""
    echo -e "${Cyan}========== 螳芽｣� TUIC 闃らせ ==========${Reset}"
    
    # 遑ｮ菫� sing-box 蟾ｲ螳芽｣?
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 蛻晏ｧ句�?UUID 
    init_uuid
    local tuic_uuid="$uuid"
    local password="$uuid"   # TUIC 逧?password 蜥?uuid 逶ｸ蜷� (蜿ら�argosbx)
    
    # 驟咲ｽｮ隸∽ｹｦ
    cert_menu
    
    # 驟咲ｽｮ遶ｯ蜿｣ (蟆晁ｯ戊ｯｻ蜿門ｷｲ菫晏ｭ倡噪遶ｯ蜿｣)
    local saved_port=$(load_port "tuic")
    if [ -n "$saved_port" ]; then
        echo -e "${Info} 譽豬句芦蟾ｲ菫晏ｭ倡噪遶ｯ蜿｣: $saved_port"
        read -p "菴ｿ逕ｨ豁､遶ｯ蜿? [Y/n]: " use_saved
        if [[ ! $use_saved =~ ^[Nn]$ ]]; then
            port="$saved_port"
        else
            port=$(config_port "TUIC")
        fi
    else
        port=$(config_port "TUIC")
    fi
    
    # 菫晏ｭ倡ｫｯ蜿｣
    save_port "tuic" "$port"
    echo -e "${Info} TUIC 遶ｯ蜿｣: ${Cyan}$port${Reset}"
    
    # 諡･蝪樊而蛻ｶ
    echo -e ""
    echo -e "${Info} 騾画叫諡･蝪樊而蛻ｶ邂玲ｳ�:"
    echo -e " ${Green}1.${Reset} bbr (鮟倩ｮ､)"
    echo -e " ${Green}2.${Reset} cubic"
    echo -e " ${Green}3.${Reset} new_reno"
    read -p "隸ｷ騾画叫 [1-3]: " cc_choice
    
    local congestion="bbr"
    case "$cc_choice" in
        2) congestion="cubic" ;;
        3) congestion="new_reno" ;;
    esac
    
    # 隸｢髣ｮ譏ｯ蜷ｦ蜷ｯ逕ｨ WARP 蜃ｺ遶�
    ask_warp_outbound
    
    # 逕滓�驟咲ｽｮ
    local exp_config=$(get_experimental_config)
    local outbounds_config=$(get_outbounds_config "$WARP_ENABLED")
    
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
${exp_config}  "inbounds": [
    {
      "type": "tuic",
      "tag": "tuic5-sb",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "uuid": "$tuic_uuid",
          "password": "$password"
        }
      ],
      "congestion_control": "$congestion",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$CERT_DIR/cert.pem",
        "key_path": "$CERT_DIR/private.key"
      }
    }
  ],
${outbounds_config}
}
EOF

    echo -e ""
    echo -e "${Green}========== TUIC 螳芽｣�ｮ梧� ==========${Reset}"
    
    # 譏ｾ遉ｺ闃らせ菫｡諱ｯ
    display_all_nodes
    
    # 隸｢髣ｮ譏ｯ蜷ｦ蜷ｯ蜉ｨ
    read -p "譏ｯ蜷ｦ遶句叉蜷ｯ蜉ｨ? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# ==================== VLESS Reality 驟咲ｽｮ ====================
install_vless_reality() {
    echo -e ""
    echo -e "${Cyan}========== 螳芽｣� VLESS Reality 闃らせ ==========${Reset}"
    
    # 遑ｮ菫� sing-box 蟾ｲ螳芽｣?
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 蛻晏ｧ句�?UUID
    init_uuid
    local vless_uuid="$uuid"
    
    # 驟咲ｽｮ遶ｯ蜿｣ (蟆晁ｯ戊ｯｻ蜿門ｷｲ菫晏ｭ倡噪遶ｯ蜿｣)
    local saved_port=$(load_port "vless")
    if [ -n "$saved_port" ]; then
        echo -e "${Info} 譽豬句芦蟾ｲ菫晏ｭ倡噪遶ｯ蜿｣: $saved_port"
        read -p "菴ｿ逕ｨ豁､遶ｯ蜿? [Y/n]: " use_saved
        if [[ ! $use_saved =~ ^[Nn]$ ]]; then
            port="$saved_port"
        else
            port=$(config_port "VLESS Reality")
        fi
    else
        port=$(config_port "VLESS Reality")
    fi
    
    # 菫晏ｭ倡ｫｯ蜿｣
    save_port "vless" "$port"
    echo -e "${Info} VLESS Reality 遶ｯ蜿｣: ${Cyan}$port${Reset}"
    
    # Reality 驟咲ｽｮ
    echo -e ""
    read -p "逶ｮ譬�ｽ醍ｫ� (dest) [apple.com]: " dest
    dest=${dest:-apple.com}
    echo "$dest" > "$DATA_DIR/ym_vl_re"
    
    read -p "Server Name [${dest}]: " server_name
    server_name=${server_name:-$dest}
    
    # 逕滓� Reality 蟇�徴蟇?(蜿ら�argosbx�悟､咲畑蟾ｲ譛牙ｯ��?
    echo -e "${Info} 逕滓� Reality 蟇�徴蟇?.."
    mkdir -p "$CERT_DIR/reality"
    
    if [ -e "$CERT_DIR/reality/private_key" ]; then
        private_key=$(cat "$CERT_DIR/reality/private_key")
        public_key=$(cat "$CERT_DIR/reality/public_key")
        short_id=$(cat "$CERT_DIR/reality/short_id")
        echo -e "${Info} 菴ｿ逕ｨ蟾ｲ蟄伜惠逧� Reality 蟇�徴"
    else
        local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
        private_key=$(echo "$keypair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
        public_key=$(echo "$keypair" | awk '/PublicKey/ {print $2}' | tr -d '"')
        short_id=$($SINGBOX_BIN generate rand --hex 4 2>/dev/null || head /dev/urandom | tr -dc a-f0-9 | head -c 8)
        
        echo "$private_key" > "$CERT_DIR/reality/private_key"
        echo "$public_key" > "$CERT_DIR/reality/public_key"
        echo "$short_id" > "$CERT_DIR/reality/short_id"
        echo -e "${Info} Reality 蟇�徴逕滓�螳梧�"
    fi
    
    # 隸｢髣ｮ譏ｯ蜷ｦ蜷ｯ逕ｨ WARP 蜃ｺ遶�
    ask_warp_outbound
    
    # 逕滓�驟咲ｽｮ
    local outbounds_config=$(get_outbounds_config "$WARP_ENABLED")
    
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "uuid": "$vless_uuid",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$server_name",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$dest",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    }
  ],
${outbounds_config}
}
EOF

    echo -e ""
    echo -e "${Green}========== VLESS Reality 螳芽｣�ｮ梧� ==========${Reset}"
    
    # 譏ｾ遉ｺ闃らせ菫｡諱ｯ
    display_all_nodes
    
    # 隸｢髣ｮ譏ｯ蜷ｦ蜷ｯ蜉ｨ
    read -p "譏ｯ蜷ｦ遶句叉蜷ｯ蜉ｨ? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# ==================== 譛榊苅邂｡逅� ====================
start_singbox() {
    if [ ! -f "$SINGBOX_BIN" ]; then
        echo -e "${Error} sing-box 譛ｪ螳芽｣?
        return 1
    fi
    
    if [ ! -f "$SINGBOX_CONF" ]; then
        echo -e "${Error} 驟咲ｽｮ譁�ｻｶ荳榊ｭ伜�?
        return 1
    fi
    
    echo -e "${Info} 蜷ｯ蜉ｨ sing-box..."
    
    # 菴ｿ逕ｨ systemd 謌?OpenRC 謌?nohup
    if [ "$HAS_SYSTEMD" = true ] && [ "$HAS_ROOT" = true ]; then
        # 蛻帛ｻｺ systemd 譛榊苅
        cat > /etc/systemd/system/sing-box.service << EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
Type=simple
ExecStart=$SINGBOX_BIN run -c $SINGBOX_CONF
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable sing-box
        systemctl start sing-box
        
        sleep 2
        if systemctl is-active sing-box &>/dev/null; then
            echo -e "${Info} sing-box 蜷ｯ蜉ｨ謌仙粥 (systemd)"
        else
            echo -e "${Error} 蜷ｯ蜉ｨ螟ｱ雍･"
            echo -e "${Info} 驟咲ｽｮ譽譟･扈捺棡��"
            echo -e "===================="
            "$SINGBOX_BIN" check -c "$SINGBOX_CONF" 2>&1 || true
            echo -e "===================="
            echo -e "${Info} systemd 迥ｶ諤�ｼ�"
            systemctl status sing-box --no-pager
        fi
    elif [ "$HAS_OPENRC" = true ] && [ "$HAS_ROOT" = true ]; then
        # 蛻帛ｻｺ OpenRC 譛榊苅 (Alpine Linux)
        cat > /etc/init.d/sing-box << 'OPENRC_EOF'
#!/sbin/openrc-run

name="sing-box"
description="sing-box service"
command="SINGBOX_BIN_PLACEHOLDER"
command_args="run -c SINGBOX_CONF_PLACEHOLDER"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"
output_log="/var/log/sing-box.log"
error_log="/var/log/sing-box.log"

depend() {
    need net
    after firewall
}
OPENRC_EOF
        # 譖ｿ謐｢蜊�菴咲ｬ?
        sed -i "s|SINGBOX_BIN_PLACEHOLDER|$SINGBOX_BIN|g" /etc/init.d/sing-box
        sed -i "s|SINGBOX_CONF_PLACEHOLDER|$SINGBOX_CONF|g" /etc/init.d/sing-box
        
        chmod +x /etc/init.d/sing-box
        rc-update add sing-box default 2>/dev/null
        rc-service sing-box start
        
        sleep 2
        if rc-service sing-box status &>/dev/null; then
            echo -e "${Info} sing-box 蜷ｯ蜉ｨ謌仙粥 (OpenRC)"
        else
            echo -e "${Error} 蜷ｯ蜉ｨ螟ｱ雍･"
            echo -e "${Info} 驟咲ｽｮ譽譟･扈捺棡��"
            "$SINGBOX_BIN" check -c "$SINGBOX_CONF" 2>&1 || true
        fi
    else
        # 菴ｿ逕ｨ nohup
        start_process "singbox" "$SINGBOX_BIN run -c $SINGBOX_CONF" "$SINGBOX_DIR"
    fi
}

stop_singbox() {
    if [ ! -f "$SINGBOX_BIN" ]; then
        echo -e "${Warning} sing-box 譛ｪ螳芽｣?
        return 1
    fi
    
    if ! pgrep -f "sing-box" &>/dev/null; then
        echo -e "${Warning} sing-box 譛ｪ蝨ｨ霑占｡�"
        return 0
    fi
    
    echo -e "${Info} 蛛懈ｭ｢ sing-box..."
    
    if [ "$HAS_SYSTEMD" = true ] && [ "$HAS_ROOT" = true ]; then
        systemctl stop sing-box 2>/dev/null
    elif [ "$HAS_OPENRC" = true ] && [ "$HAS_ROOT" = true ]; then
        rc-service sing-box stop 2>/dev/null
    else
        stop_process "singbox"
    fi
    
    pkill -f "sing-box" 2>/dev/null
    echo -e "${Info} sing-box 蟾ｲ蛛懈ｭ?
}

restart_singbox() {
    stop_singbox
    sleep 1
    start_singbox
}

status_singbox() {
    if [ ! -f "$SINGBOX_BIN" ]; then
        echo -e "${Warning} sing-box 譛ｪ螳芽｣?
        echo -e "${Tip} 隸ｷ蜈磯画叫 [1-3] 螳芽｣�鰍轤ｹ"
        return 1
    fi
    
    echo -e "${Info} sing-box 迥ｶ諤?"
    
    if pgrep -f "sing-box" &>/dev/null; then
        echo -e "  霑占｡檎憾諤? ${Green}霑占｡御ｸ?{Reset}"
        echo -e "  霑帷ｨ� PID: $(pgrep -f 'sing-box' | head -1)"
    else
        echo -e "  霑占｡檎憾諤? ${Red}蟾ｲ蛛懈ｭ?{Reset}"
    fi
    
    if [ -f "$SINGBOX_CONF" ]; then
        echo -e "  驟咲ｽｮ譁�ｻｶ: ${Cyan}$SINGBOX_CONF${Reset}"
    fi
}

# ==================== 扈滉ｸ闃らせ菫｡諱ｯ霎灘� (蜿ら�argosbx逧�ip蜃ｽ謨ｰ) ====================
display_all_nodes() {
    local server_ip=$(get_server_ip)
    local uuid=$(cat "$DATA_DIR/uuid" 2>/dev/null)
    local hostname=$(hostname 2>/dev/null || echo "vps")
    
    rm -f "$LINKS_FILE"
    
    echo -e ""
    echo -e "${Green}*********************************************************${Reset}"
    echo -e "${Green}*             VPS-play 闃らせ驟咲ｽｮ菫｡諱ｯ                     *${Reset}"
    echo -e "${Green}*********************************************************${Reset}"
    echo -e ""
    echo -e " 譛榊苅蝎ｨIP: ${Cyan}$server_ip${Reset}"
    echo -e " UUID/蟇���: ${Cyan}$uuid${Reset}"
    echo -e ""
    
    # 譽豬句ｹｶ譏ｾ遉ｺ Hysteria2 闃らせ
    if [ -f "$SINGBOX_CONF" ] && grep -q '"type": "hysteria2"' "$SINGBOX_CONF" 2>/dev/null; then
        local hy2_port=$(load_port "hy2")
        [ -z "$hy2_port" ] && hy2_port=$(grep -A5 '"hysteria2"' "$SINGBOX_CONF" | grep "listen_port" | grep -o '[0-9]*' | head -1)
        local hy2_password=$(grep -A10 '"hysteria2"' "$SINGBOX_CONF" | grep '"password"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$hy2_password" ] && hy2_password="$uuid"
        
        echo -e "�張縲?Hysteria2 縲題鰍轤ｹ菫｡諱ｯ螯ゆｸ具ｼ�"
        local hy2_link="hysteria2://${hy2_password}@${server_ip}:${hy2_port}?security=tls&alpn=h3&insecure=1&sni=www.bing.com#${hostname}-hy2"
        echo "$hy2_link" >> "$LINKS_FILE"
        echo -e "${Yellow}$hy2_link${Reset}"
        echo -e ""
    fi
    
    # 譽豬句ｹｶ譏ｾ遉ｺ TUIC 闃らせ
    if [ -f "$SINGBOX_CONF" ] && grep -q '"type": "tuic"' "$SINGBOX_CONF" 2>/dev/null; then
        local tuic_port=$(load_port "tuic")
        [ -z "$tuic_port" ] && tuic_port=$(grep -A5 '"tuic"' "$SINGBOX_CONF" | grep "listen_port" | grep -o '[0-9]*' | head -1)
        local tuic_uuid=$(grep -A10 '"tuic"' "$SINGBOX_CONF" | grep '"uuid"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$tuic_uuid" ] && tuic_uuid="$uuid"
        local tuic_password="$tuic_uuid"
        
        echo -e "�張縲?TUIC 縲題鰍轤ｹ菫｡諱ｯ螯ゆｸ具ｼ�"
        local tuic_link="tuic://${tuic_uuid}:${tuic_password}@${server_ip}:${tuic_port}?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1&allowInsecure=1#${hostname}-tuic"
        echo "$tuic_link" >> "$LINKS_FILE"
        echo -e "${Yellow}$tuic_link${Reset}"
        echo -e ""
    fi
    
    # 譽豬句ｹｶ譏ｾ遉ｺ AnyTLS 闃らせ (荳榊性 reality)
    if [ -f "$SINGBOX_CONF" ] && grep -q '"type": "anytls"' "$SINGBOX_CONF" 2>/dev/null && ! grep -q '"anyreality' "$SINGBOX_CONF" 2>/dev/null; then
        local an_port=$(load_port "anytls")
        [ -z "$an_port" ] && an_port=$(grep -A5 '"anytls"' "$SINGBOX_CONF" | grep "listen_port" | grep -o '[0-9]*' | head -1)
        local an_password=$(grep -A10 '"anytls"' "$SINGBOX_CONF" | grep '"password"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$an_password" ] && an_password="$uuid"
        
        echo -e "�張縲?AnyTLS 縲題鰍轤ｹ菫｡諱ｯ螯ゆｸ具ｼ�"
        local an_link="anytls://${an_password}@${server_ip}:${an_port}?insecure=1&allowInsecure=1#${hostname}-anytls"
        echo "$an_link" >> "$LINKS_FILE"
        echo -e "${Yellow}$an_link${Reset}"
        echo -e ""
    fi
    
    # 譽豬句ｹｶ譏ｾ遉ｺ Any-Reality 闃らせ
    if [ -f "$SINGBOX_CONF" ] && grep -q '"anyreality' "$SINGBOX_CONF" 2>/dev/null; then
        local ar_port=$(load_port "anyreality")
        [ -z "$ar_port" ] && ar_port=$(grep -A5 '"anyreality' "$SINGBOX_CONF" | grep "listen_port" | grep -o '[0-9]*' | head -1)
        local ar_password=$(grep -A10 '"anyreality' "$SINGBOX_CONF" | grep '"password"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$ar_password" ] && ar_password="$uuid"
        local public_key=$(cat "$CERT_DIR/reality/public_key" 2>/dev/null)
        local short_id=$(cat "$CERT_DIR/reality/short_id" 2>/dev/null)
        local sni=$(grep -A20 '"anyreality' "$SINGBOX_CONF" | grep '"server_name"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$sni" ] && sni="apple.com"
        
        echo -e "�張縲?Any-Reality 縲題鰍轤ｹ菫｡諱ｯ螯ゆｸ具ｼ�"
        local ar_link="anytls://${ar_password}@${server_ip}:${ar_port}?security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#${hostname}-any-reality"
        echo "$ar_link" >> "$LINKS_FILE"
        echo -e "${Yellow}$ar_link${Reset}"
        echo -e ""
    fi
    
    # 譽豬句ｹｶ譏ｾ遉ｺ VLESS Reality 闃らせ
    if [ -f "$SINGBOX_CONF" ] && grep -q '"type": "vless"' "$SINGBOX_CONF" 2>/dev/null; then
        local vl_port=$(load_port "vless")
        [ -z "$vl_port" ] && vl_port=$(grep -A5 '"vless"' "$SINGBOX_CONF" | grep "listen_port" | grep -o '[0-9]*' | head -1)
        local vl_uuid=$(grep -A10 '"vless"' "$SINGBOX_CONF" | grep '"uuid"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$vl_uuid" ] && vl_uuid="$uuid"
        local public_key=$(cat "$CERT_DIR/reality/public_key" 2>/dev/null)
        local short_id=$(cat "$CERT_DIR/reality/short_id" 2>/dev/null)
        local sni=$(grep -A20 '"vless"' "$SINGBOX_CONF" | grep '"server_name"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$sni" ] && sni="apple.com"
        
        echo -e "�張縲?VLESS-tcp-reality-vision 縲題鰍轤ｹ菫｡諱ｯ螯ゆｸ具ｼ�"
        local vl_link="vless://${vl_uuid}@${server_ip}:${vl_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#${hostname}-vless-reality"
        echo "$vl_link" >> "$LINKS_FILE"
        echo -e "${Yellow}$vl_link${Reset}"
        echo -e ""
    fi
    
    # 譽豬句ｹｶ譏ｾ遉ｺ Shadowsocks 闃らせ
    if [ -f "$SINGBOX_CONF" ] && grep -q '"type": "shadowsocks"' "$SINGBOX_CONF" 2>/dev/null; then
        local ss_port=$(load_port "ss")
        [ -z "$ss_port" ] && ss_port=$(grep -A5 '"shadowsocks"' "$SINGBOX_CONF" | grep "listen_port" | grep -o '[0-9]*' | head -1)
        local ss_password=$(grep -A10 '"shadowsocks"' "$SINGBOX_CONF" | grep '"password"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        local ss_method=$(grep -A10 '"shadowsocks"' "$SINGBOX_CONF" | grep '"method"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [ -z "$ss_method" ] && ss_method="2022-blake3-aes-128-gcm"
        
        echo -e "�張縲?Shadowsocks-2022 縲題鰍轤ｹ菫｡諱ｯ螯ゆｸ具ｼ�"
        local ss_link="ss://$(echo -n "${ss_method}:${ss_password}@${server_ip}:${ss_port}" | base64 -w0)#${hostname}-ss"
        echo "$ss_link" >> "$LINKS_FILE"
        echo -e "${Yellow}$ss_link${Reset}"
        echo -e ""
    fi
    
    echo -e "---------------------------------------------------------"
    echo -e "閨壼粋闃らせ菫｡諱ｯ蟾ｲ菫晏ｭ伜芦: ${Cyan}$LINKS_FILE${Reset}"
    echo -e "蜿ｯ霑占｡?${Yellow}cat $LINKS_FILE${Reset} 譟･逵�"
    echo -e "========================================================="
}

# ==================== 闃らせ菫｡諱ｯ ====================
show_node_info() {
    while true; do
        clear
        
        # 菴ｿ逕ｨ扈滉ｸ逧�鰍轤ｹ菫｡諱ｯ霎灘�蜃ｽ謨?
        display_all_nodes
        
        # 謫堺ｽ懆除蜊�
        echo -e ""
        echo -e "${Info} 闃らせ邂｡逅�蛾｡ｹ:"
        echo -e " ${Green}1.${Reset} 豺ｻ蜉�譁ｰ闃ら�?(菫晉蕗邇ｰ譛芽鰍轤ｹ)"
        echo -e " ${Green}2.${Reset} 驥崎｣�鴫譛芽鰍轤ｹ (驥肴眠逕滓�驟咲ｽｮ)"
        echo -e " ${Green}3.${Reset} 菫ｮ謾ｹ闃らせ蜿よ焚"
        echo -e " ${Green}4.${Reset} 螟榊宛蛻�ｺｫ體ｾ謗･蛻ｰ蜑ｪ雍ｴ譚ｿ"
        echo -e " ${Green}0.${Reset} 霑泌屓"
        echo -e ""
        
        read -p " 隸ｷ騾画叫 [0-4]: " node_choice
        
        case "$node_choice" in
            1) add_node_to_existing ;;
            2) reinstall_existing_node ;;
            3) modify_node_params ;;
            4) copy_share_links ;;
            0) return 0 ;;
            *) echo -e "${Error} 譌�謨磯画叫" ;;
        esac
        
        read -p "謖牙屓霓ｦ扈ｧ扈?.."
    done
}

# 豺ｻ蜉�譁ｰ闃らせ蛻ｰ邇ｰ譛蛾�鄂ｮ
add_node_to_existing() {
    echo -e ""
    echo -e "${Cyan}========== 豺ｻ蜉�譁ｰ闃ら�?==========${Reset}"
    echo -e "${Tip} 蝨ｨ蠖灘燕霑占｡檎噪闃らせ蝓ｺ遑荳頑ｷｻ蜉�譁ｰ闃らせ"
    echo -e ""
    echo -e " ${Green}1.${Reset} Hysteria2"
    echo -e " ${Green}2.${Reset} TUIC v5"
    echo -e " ${Green}3.${Reset} VLESS Reality"
    echo -e " ${Green}4.${Reset} AnyTLS"
    echo -e " ${Green}5.${Reset} Any-Reality"
    echo -e " ${Green}0.${Reset} 蜿匁ｶ�"
    echo -e ""
    
    read -p " 隸ｷ騾画叫隕∵ｷｻ蜉�逧�刻隶ｮ [0-5]: " add_choice
    
    case "$add_choice" in
        1) add_protocol_hy2 ;;
        2) add_protocol_tuic ;;
        3) add_protocol_vless ;;
        4) add_protocol_anytls ;;
        5) add_protocol_any_reality ;;
        0) return 0 ;;
        *) echo -e "${Error} 譌�謨磯画叫" ;;
    esac
}

# 豺ｻ蜉� Hysteria2 蜊剰ｮｮ蛻ｰ邇ｰ譛蛾�鄂?
add_protocol_hy2() {
    echo -e "${Info} 豺ｻ蜉� Hysteria2 闃らせ..."
    
    # 譽譟･隸∽ｹ?
    if [ ! -f "$CERT_DIR/cert.pem" ]; then
        echo -e "${Info} 髴隕��鄂?TLS 隸∽ｹｦ"
        cert_menu
    fi
    
    local port=$(config_port "Hysteria2")
    read -p "隶ｾ鄂ｮ蟇��� [逡咏ｩｺ髫乗惻]: " password
    [ -z "$password" ] && password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    # 隸ｻ蜿也鴫譛蛾�鄂ｮ蟷ｶ豺ｻ蜉�譁ｰ inbound
    if [ -f "$SINGBOX_CONF" ]; then
        local server_ip=$(get_ip)
        local new_inbound="{\"type\":\"hysteria2\",\"tag\":\"hy2-add\",\"listen\":\"::\",\"listen_port\":${port},\"users\":[{\"password\":\"${password}\"}],\"tls\":{\"enabled\":true,\"alpn\":[\"h3\"],\"certificate_path\":\"${CERT_DIR}/cert.pem\",\"key_path\":\"${CERT_DIR}/private.key\"}}"
        
        # 菴ｿ逕ｨ jq 豺ｻ蜉� inbound
        if command -v jq &>/dev/null; then
            local tmp_conf="${SINGBOX_CONF}.tmp"
            jq ".inbounds += [$new_inbound]" "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
        else
            echo -e "${Warning} 髴隕?jq 譚･菫ｮ謾ｹ驟咲ｽ?
            echo -e "${Tip} 隸ｷ螳芽｣? apt install jq 謌?yum install jq 謌?apk add jq"
            return 1
        fi
        
        # 逕滓�體ｾ謗･
        local hy2_link="hysteria2://${password}@${server_ip}:${port}?sni=${CERT_DOMAIN:-www.bing.com}&insecure=1#Hy2-Add-${server_ip}"
        echo "$hy2_link" >> "$SINGBOX_DIR/combo_links.txt"
        
        # 譖ｴ譁ｰ闃らせ菫｡諱ｯ
        echo -e "\n[Hysteria2-Added]\n遶ｯ蜿｣: ${port}\n蟇���: ${password}" >> "$SINGBOX_DIR/node_info.txt"
        
        echo -e "${Info} Hysteria2 闃らせ蟾ｲ豺ｻ蜉?
        echo -e "${Yellow}${hy2_link}${Reset}"
        
        # 驥榊星譛榊苅
        restart_singbox
    else
        echo -e "${Error} 驟咲ｽｮ譁�ｻｶ荳榊ｭ伜�?
    fi
}

# 豺ｻ蜉� AnyTLS 蜊剰ｮｮ蛻ｰ邇ｰ譛蛾�鄂?
add_protocol_anytls() {
    echo -e "${Info} 豺ｻ蜉� AnyTLS 闃らせ..."
    
    # 迚域悽譽譟?
    if ! version_ge "$(get_version)" "1.12.0"; then
        echo -e "${Info} AnyTLS 髴隕∝合郤?sing-box 蛻?1.12.0+"
        download_singbox "1.12.0"
    fi
    
    local port=$(config_port "AnyTLS")
    read -p "隶ｾ鄂ｮ蟇��� [逡咏ｩｺ髫乗惻]: " password
    [ -z "$password" ] && password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    local cert_domain="bing.com"
    local internal_port=$(shuf -i 20000-60000 -n 1)
    
    # 逕滓�閾ｪ遲ｾ隸∽ｹｦ
    if [ ! -f "$CERT_DIR/anytls.key" ]; then
        openssl req -x509 -newkey ec:<(openssl ecparam -name prime256v1) \
            -keyout "$CERT_DIR/anytls.key" -out "$CERT_DIR/anytls.crt" \
            -days 36500 -nodes -subj "/CN=$cert_domain" 2>/dev/null
    fi
    
    if [ -f "$SINGBOX_CONF" ]; then
        local server_ip=$(get_ip)
        local hostname=$(hostname)
        
        # 菴ｿ逕ｨ jq 豺ｻ蜉� inbound
        local anytls_inbound="{\"type\":\"anytls\",\"tag\":\"anytls-add\",\"listen\":\"::\",\"listen_port\":${port},\"users\":[{\"password\":\"${password}\"}],\"tls\":{\"enabled\":true,\"certificate_path\":\"${CERT_DIR}/anytls.crt\",\"key_path\":\"${CERT_DIR}/anytls.key\"},\"detour\":\"mixed-add\"}"
        local mixed_inbound="{\"type\":\"mixed\",\"tag\":\"mixed-add\",\"listen\":\"127.0.0.1\",\"listen_port\":${internal_port}}"
        
        if command -v jq &>/dev/null; then
            local tmp_conf="${SINGBOX_CONF}.tmp"
            jq ".inbounds += [$anytls_inbound, $mixed_inbound]" "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
        else
            echo -e "${Warning} 髴隕?jq 譚･菫ｮ謾ｹ驟咲ｽ?
            echo -e "${Tip} 隸ｷ螳芽｣? apt install jq 謌?yum install jq 謌?apk add jq"
            return 1
        fi
        
        # 逕滓�體ｾ謗･
        local anytls_link="anytls://${password}@${server_ip}:${port}?insecure=1&sni=${server_ip}&fp=chrome&alpn=h2,http/1.1&udp=1#anytls-add-${hostname}"
        echo "$anytls_link" >> "$SINGBOX_DIR/combo_links.txt"
        
        # 譖ｴ譁ｰ闃らせ菫｡諱ｯ
        echo -e "\n[AnyTLS-Added]\n遶ｯ蜿｣: ${port}\n蟇���: ${password}\nSNI: ${server_ip}" >> "$SINGBOX_DIR/node_info.txt"
        
        echo -e "${Info} AnyTLS 闃らせ蟾ｲ豺ｻ蜉?
        echo -e "${Yellow}${anytls_link}${Reset}"
        
        restart_singbox
    else
        echo -e "${Error} 驟咲ｽｮ譁�ｻｶ荳榊ｭ伜�?
    fi
}

# 豺ｻ蜉�蜈ｶ莉門刻隶ｮ逧�頃菴榊�謨?
add_protocol_tuic() {
    echo -e "${Info} 豺ｻ蜉� TUIC 闃らせ..."
    
    # 譽譟･隸∽ｹ?
    if [ ! -f "$CERT_DIR/cert.pem" ]; then
        echo -e "${Info} 髴隕��鄂?TLS 隸∽ｹｦ"
        cert_menu
    fi
    
    local port=$(config_port "TUIC")
    read -p "隶ｾ鄂ｮ蟇��� [逡咏ｩｺ髫乗惻]: " password
    [ -z "$password" ] && password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null)
    
    if [ -f "$SINGBOX_CONF" ]; then
        local server_ip=$(get_ip)
        local new_inbound="{\"type\":\"tuic\",\"tag\":\"tuic-add\",\"listen\":\"::\",\"listen_port\":${port},\"users\":[{\"uuid\":\"${uuid}\",\"password\":\"${password}\"}],\"congestion_control\":\"bbr\",\"tls\":{\"enabled\":true,\"alpn\":[\"h3\"],\"certificate_path\":\"${CERT_DIR}/cert.pem\",\"key_path\":\"${CERT_DIR}/private.key\"}}"
        
        if command -v jq &>/dev/null; then
            local tmp_conf="${SINGBOX_CONF}.tmp"
            jq ".inbounds += [$new_inbound]" "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
        else
            echo -e "${Warning} 髴隕?jq 譚･菫ｮ謾ｹ驟咲ｽ?
            echo -e "${Tip} 隸ｷ螳芽｣? apt install jq 謌?yum install jq 謌?apk add jq"
            return 1
        fi
        
        # 逕滓�體ｾ謗･
        local tuic_link="tuic://${uuid}:${password}@${server_ip}:${port}?sni=${CERT_DOMAIN:-www.bing.com}&congestion_control=bbr&alpn=h3&allow_insecure=1#TUIC-Add-${server_ip}"
        echo "$tuic_link" >> "$SINGBOX_DIR/combo_links.txt"
        
        echo -e "\n[TUIC-Added]\n遶ｯ蜿｣: ${port}\nUUID: ${uuid}\n蟇���: ${password}" >> "$SINGBOX_DIR/node_info.txt"
        
        echo -e "${Info} TUIC 闃らせ蟾ｲ豺ｻ蜉?
        echo -e "${Yellow}${tuic_link}${Reset}"
        
        restart_singbox
    else
        echo -e "${Error} 驟咲ｽｮ譁�ｻｶ荳榊ｭ伜�?
    fi
}

add_protocol_vless() {
    echo -e "${Info} 豺ｻ蜉� VLESS Reality 闃らせ..."
    
    local port=$(config_port "VLESS Reality")
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null)
    
    # 逕滓� Reality 蟇�徴蟇?
    local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
    local private_key=$(echo "$keypair" | grep -i "privatekey" | awk '{print $2}')
    local public_key=$(echo "$keypair" | grep -i "publickey" | awk '{print $2}')
    local short_id=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)
    local dest="www.apple.com"
    
    if [ -f "$SINGBOX_CONF" ]; then
        local server_ip=$(get_ip)
        local new_inbound="{\"type\":\"vless\",\"tag\":\"vless-add\",\"listen\":\"::\",\"listen_port\":${port},\"users\":[{\"uuid\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\"}],\"tls\":{\"enabled\":true,\"server_name\":\"${dest}\",\"reality\":{\"enabled\":true,\"handshake\":{\"server\":\"${dest}\",\"server_port\":443},\"private_key\":\"${private_key}\",\"short_id\":[\"${short_id}\"]}}}"
        
        if command -v jq &>/dev/null; then
            local tmp_conf="${SINGBOX_CONF}.tmp"
            jq ".inbounds += [$new_inbound]" "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
        else
            echo -e "${Warning} 髴隕?jq 譚･菫ｮ謾ｹ驟咲ｽ?
            return 1
        fi
        
        # 逕滓�體ｾ謗･
        local vless_link="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${dest}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#VLESS-Reality-Add-${server_ip}"
        echo "$vless_link" >> "$SINGBOX_DIR/combo_links.txt"
        
        echo -e "\n[VLESS-Reality-Added]\n遶ｯ蜿｣: ${port}\nUUID: ${uuid}\n蜈ｬ髓･: ${public_key}\n遏ｭID: ${short_id}" >> "$SINGBOX_DIR/node_info.txt"
        
        echo -e "${Info} VLESS Reality 闃らせ蟾ｲ豺ｻ蜉?
        echo -e "${Yellow}${vless_link}${Reset}"
        
        restart_singbox
    else
        echo -e "${Error} 驟咲ｽｮ譁�ｻｶ荳榊ｭ伜�?
    fi
}

add_protocol_any_reality() {
    echo -e "${Info} 豺ｻ蜉� Any-Reality 闃らせ..."
    
    # 迚域悽譽譟?
    if ! version_ge "$(get_version)" "1.12.0"; then
        echo -e "${Info} Any-Reality 髴隕∝合郤?sing-box 蛻?1.12.0+"
        download_singbox "1.12.0"
    fi
    
    local port=$(config_port "Any-Reality")
    read -p "隶ｾ鄂ｮ蟇��� [逡咏ｩｺ髫乗惻]: " password
    [ -z "$password" ] && password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    # 逕滓� Reality 蟇�徴蟇?
    local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
    local private_key=$(echo "$keypair" | grep -i "privatekey" | awk '{print $2}')
    local public_key=$(echo "$keypair" | grep -i "publickey" | awk '{print $2}')
    local short_id=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)
    local server_name="www.apple.com"
    local internal_port=$(shuf -i 20000-60000 -n 1)
    
    if [ -f "$SINGBOX_CONF" ]; then
        local server_ip=$(get_ip)
        local hostname=$(hostname)
        
        local ar_inbound="{\"type\":\"anytls\",\"tag\":\"any-reality-add\",\"listen\":\"::\",\"listen_port\":${port},\"users\":[{\"password\":\"${password}\"}],\"tls\":{\"enabled\":true,\"server_name\":\"${server_name}\",\"reality\":{\"enabled\":true,\"handshake\":{\"server\":\"${server_name}\",\"server_port\":443},\"private_key\":\"${private_key}\",\"short_id\":[\"${short_id}\"]}},\"detour\":\"mixed-ar-add\"}"
        local mixed_inbound="{\"type\":\"mixed\",\"tag\":\"mixed-ar-add\",\"listen\":\"127.0.0.1\",\"listen_port\":${internal_port}}"
        
        if command -v jq &>/dev/null; then
            local tmp_conf="${SINGBOX_CONF}.tmp"
            jq ".inbounds += [$ar_inbound, $mixed_inbound]" "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
        else
            echo -e "${Warning} 髴隕?jq 譚･菫ｮ謾ｹ驟咲ｽ?
            return 1
        fi
        
        # 逕滓�體ｾ謗･
        local ar_link="anytls://${password}@${server_ip}:${port}?security=reality&sni=${server_name}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#Any-Reality-Add-${hostname}"
        echo "$ar_link" >> "$SINGBOX_DIR/combo_links.txt"
        
        echo -e "\n[Any-Reality-Added]\n遶ｯ蜿｣: ${port}\n蟇���: ${password}\nSNI: ${server_name}\n蜈ｬ髓･: ${public_key}\n遏ｭID: ${short_id}" >> "$SINGBOX_DIR/node_info.txt"
        
        echo -e "${Info} Any-Reality 闃らせ蟾ｲ豺ｻ蜉?
        echo -e "${Yellow}${ar_link}${Reset}"
        
        restart_singbox
    else
        echo -e "${Error} 驟咲ｽｮ譁�ｻｶ荳榊ｭ伜�?
    fi
}

# 驥崎｣�鴫譛芽鰍轤ｹ
reinstall_existing_node() {
    echo -e ""
    
    if [ ! -f "$SINGBOX_CONF" ]; then
        echo -e "${Warning} 蠖灘燕豐｡譛蛾�鄂ｮ�瑚ｯｷ蜈亥ｮ芽｣�鰍轤?
        return 1
    fi
    
    # 隸ｻ蜿門ｽ灘燕驟咲ｽｮ�梧｣豬句刻隶ｮ邀ｻ蝙?
    local protocols=$(grep -o '"type": *"[^"]*"' "$SINGBOX_CONF" | grep -v direct | grep -v mixed | cut -d'"' -f4 | sort -u)
    local proto_count=$(echo "$protocols" | wc -w)
    
    echo -e "${Cyan}========== 驥崎｣�鰍轤ｹ ==========${Reset}"
    echo -e "${Info} 譽豬句芦莉･荳句刻隶ｮ (蜈?$proto_count 荳?:"
    echo -e ""
    
    local i=1
    local proto_array=()
    for proto in $protocols; do
        proto_array+=("$proto")
        echo -e " ${Green}$i.${Reset} $proto"
        ((i++))
    done
    
    echo -e ""
    echo -e "${Yellow}==================== 驥崎｣�蛾｡ｹ ====================${Reset}"
    echo -e " ${Green}A.${Reset} 驥崎｣��驛ｨ闃らせ (蛻�髯､謇譛蛾�鄂ｮ驥肴眠螳芽｣?"
    echo -e " ${Green}S.${Reset} 驥崎｣�黒荳ｪ闃らせ (蜿ｪ驥崎｣�画叫逧�刻隶ｮ�御ｿ晉蕗蜈ｶ莉�)"
    echo -e " ${Green}C.${Reset} 閾ｪ螳壻ｹ臥ｻ�粋驥崎｣?(騾画叫螟壻ｸｪ蜊剰ｮｮ驥崎｣�)"
    echo -e " ${Green}N.${Reset} 螳芽｣��譁ｰ逧�刻隶ｮ扈��?
    echo -e " ${Green}0.${Reset} 蜿匁ｶ�"
    echo -e "${Yellow}=================================================${Reset}"
    
    read -p " 隸ｷ騾画叫 [A/S/C/N/0]: " reinstall_mode
    
    case "${reinstall_mode^^}" in
        A|ALL)
            reinstall_all_nodes "$protocols"
            ;;
        S|SINGLE)
            reinstall_single_node "${proto_array[@]}"
            ;;
        C|CUSTOM)
            reinstall_custom_nodes "${proto_array[@]}"
            ;;
        N|NEW)
            echo -e "${Warning} 霑吝ｰ�唖髯､謇譛臥鴫譛蛾�鄂ｮ�梧弍蜷ｦ扈ｧ扈ｭ? [y/N]"
            read -p "" confirm
            if [[ $confirm =~ ^[Yy]$ ]]; then
                stop_singbox
                rm -f "$SINGBOX_CONF" "$SINGBOX_DIR/node_info.txt" "$SINGBOX_DIR"/*_link.txt "$SINGBOX_DIR"/combo_links.txt
                install_combo
            fi
            ;;
        0) return 0 ;;
        *) echo -e "${Error} 譌�謨磯画叫" ;;
    esac
}

# 驥崎｣��驛ｨ闃らせ
reinstall_all_nodes() {
    local protocols=$1
    
    echo -e ""
    echo -e "${Warning} 驥崎｣��驛ｨ蟆�唖髯､謇譛蛾�鄂ｮ蟷ｶ驥肴眠螳芽｣�ｼ梧弍蜷ｦ扈ｧ扈? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    stop_singbox
    rm -f "$SINGBOX_CONF" "$SINGBOX_DIR/node_info.txt" "$SINGBOX_DIR"/*_link.txt "$SINGBOX_DIR"/combo_links.txt
    
    echo -e "${Info} 豁｣蝨ｨ驥崎｣�園譛牙刻隶?.."
    
    for proto in $protocols; do
        echo -e "${Info} 豁｣蝨ｨ螳芽｣� $proto..."
        case "$proto" in
            hysteria2) install_hysteria2 ;;
            tuic) install_tuic ;;
            vless) install_vless_reality ;;
            anytls) install_anytls ;;
        esac
    done
    
    echo -e "${Info} 蜈ｨ驛ｨ闃らせ驥崎｣�ｮ梧�"
}

# 驥崎｣�黒荳ｪ闃らせ
reinstall_single_node() {
    local proto_array=("$@")
    local proto_count=${#proto_array[@]}
    
    echo -e ""
    echo -e "${Info} 騾画叫隕�㍾陬�噪蜊穂ｸｪ闃らせ:"
    
    local i=1
    for proto in "${proto_array[@]}"; do
        echo -e " ${Green}$i.${Reset} $proto"
        ((i++))
    done
    echo -e " ${Green}0.${Reset} 蜿匁ｶ�"
    
    read -p " 隸ｷ騾画叫 [1-$proto_count]: " single_choice
    
    if [[ "$single_choice" =~ ^[0-9]+$ ]] && [ "$single_choice" -ge 1 ] && [ "$single_choice" -le "$proto_count" ]; then
        local selected_proto="${proto_array[$((single_choice-1))]}"
        
        echo -e ""
        echo -e "${Info} 蟆�㍾陬? ${Cyan}$selected_proto${Reset}"
        echo -e "${Tip} 蜈ｶ莉冶鰍轤ｹ蟆�ｿ晉蕗荳榊�?
        echo -e "${Warning} 譏ｯ蜷ｦ扈ｧ扈ｭ? [y/N]"
        read -p "" confirm
        [[ ! $confirm =~ ^[Yy]$ ]] && return 0
        
        # 菴ｿ逕ｨ jq 謌?sed 蛻�髯､謖�ｮ壼刻隶ｮ逧?inbound
        if command -v jq &>/dev/null; then
            # 菴ｿ逕ｨ jq 蛻�髯､謖�ｮ夂ｱｻ蝙狗�?inbound
            local tmp_conf="${SINGBOX_CONF}.tmp"
            jq --arg type "$selected_proto" '.inbounds = [.inbounds[] | select(.type != $type)]' "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
            echo -e "${Info} 蟾ｲ蛻�髯?$selected_proto 驟咲ｽｮ (jq)"
        else
            # 豐｡譛� jq�御ｽｿ逕ｨ螟�畑譁ｹ譯茨ｼ夐㍾蟒ｺ謨ｴ荳ｪ驟咲ｽｮ
            echo -e "${Warning} 譛ｪ譽豬句芦 jq�悟ｰ�ｽｿ逕ｨ螟�畑譁ｹ譯�"
            echo -e "${Tip} 蟒ｺ隶ｮ螳芽｣� jq: apt install jq 謌?yum install jq 謌?apk add jq"
            
            # 螟�畑譁ｹ譯茨ｼ壼●豁｢譛榊苅�御ｿ晏ｭ伜�莉門刻隶ｮ逧��鄂ｮ�碁㍾蟒ｺ
            stop_singbox
            
            # 謠仙叙蠖灘燕驟咲ｽｮ荳ｭ逧��莉門刻隶ｮ
            local other_protos=""
            for proto in "${proto_array[@]}"; do
                if [ "$proto" != "$selected_proto" ]; then
                    [ -n "$other_protos" ] && other_protos="${other_protos},"
                    other_protos="${other_protos}$proto"
                fi
            done
            
            echo -e "${Info} 蟆�ｿ晉蕗逧�刻隶ｮ: $other_protos"
            echo -e "${Warning} 螟�畑譁ｹ譯磯怙隕�㍾譁ｰ驟咲ｽｮ謇譛芽鰍轤ｹ�梧弍蜷ｦ扈ｧ扈ｭ? [y/N]"
            read -p "" confirm2
            if [[ ! $confirm2 =~ ^[Yy]$ ]]; then
                start_singbox
                return 0
            fi
            
            # 蛻�髯､驟咲ｽｮ蟷ｶ驥崎｣?
            rm -f "$SINGBOX_CONF" "$SINGBOX_DIR/node_info.txt" "$SINGBOX_DIR"/*_link.txt "$SINGBOX_DIR"/combo_links.txt
            install_combo
            return 0
        fi
        
        # 驥肴眠豺ｻ蜉�隸･蜊剰ｮ?
        echo -e "${Info} 豁｣蝨ｨ驥肴眠驟咲ｽｮ $selected_proto..."
        case "$selected_proto" in
            hysteria2) add_protocol_hy2 ;;
            tuic) add_protocol_tuic ;;
            vless) add_protocol_vless ;;
            anytls) add_protocol_anytls ;;
        esac
        
        echo -e "${Info} $selected_proto 驥崎｣�ｮ梧�"
    elif [ "$single_choice" = "0" ]; then
        return 0
    else
        echo -e "${Error} 譌�謨磯画叫"
    fi
}

# 閾ｪ螳壻ｹ臥ｻ�粋驥崎｣?
reinstall_custom_nodes() {
    local proto_array=("$@")
    local proto_count=${#proto_array[@]}
    
    echo -e ""
    echo -e "${Info} 騾画叫隕�㍾陬�噪蜊剰ｮｮ (霎灘�郛門捷�檎畑騾怜捷蛻�囈�悟ｦ�: 1,3):"
    
    local i=1
    for proto in "${proto_array[@]}"; do
        echo -e " ${Green}$i.${Reset} $proto"
        ((i++))
    done
    
    read -p " 隸ｷ霎灘�? " custom_choice
    
    if [ -z "$custom_choice" ]; then
        echo -e "${Error} 譛ｪ騾画叫莉ｻ菴募刻隶ｮ"
        return 1
    fi
    
    # 隗｣譫宣画叫
    IFS=',' read -ra selections <<< "$custom_choice"
    local selected_protos=()
    
    for sel in "${selections[@]}"; do
        sel=$(echo "$sel" | tr -d ' ')
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "$proto_count" ]; then
            selected_protos+=("${proto_array[$((sel-1))]}")
        fi
    done
    
    if [ ${#selected_protos[@]} -eq 0 ]; then
        echo -e "${Error} 譌�譛画譜騾画叫"
        return 1
    fi
    
    echo -e ""
    echo -e "${Info} 蟆�㍾陬�ｻ･荳句刻隶?"
    for proto in "${selected_protos[@]}"; do
        echo -e "  - ${Cyan}$proto${Reset}"
    done
    echo -e "${Tip} 蜈ｶ莉冶鰍轤ｹ蟆�ｿ晉蕗荳榊�?
    echo -e "${Warning} 譏ｯ蜷ｦ扈ｧ扈ｭ? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    # 蛻�髯､騾我ｸｭ逧�刻隶?
    if command -v jq &>/dev/null; then
        for proto in "${selected_protos[@]}"; do
            local tmp_conf="${SINGBOX_CONF}.tmp"
            jq --arg type "$proto" '.inbounds = [.inbounds[] | select(.type != $type)]' "$SINGBOX_CONF" > "$tmp_conf" && mv "$tmp_conf" "$SINGBOX_CONF"
        done
        echo -e "${Info} 蟾ｲ蛻�髯､騾我ｸｭ蜊剰ｮｮ逧��鄂?
    else
        echo -e "${Warning} 譛ｪ譽豬句芦 jq�梧裏豕戊ｿ幄｡碁Κ蛻�㍾陬?
        echo -e "${Tip} 蟒ｺ隶ｮ螳芽｣� jq: apt install jq 謌?yum install jq 謌?apk add jq"
        echo -e "${Info} 蟆�ｽｿ逕ｨ蜈ｨ驥城㍾陬�婿譯?.."
        stop_singbox
        rm -f "$SINGBOX_CONF" "$SINGBOX_DIR/node_info.txt" "$SINGBOX_DIR"/*_link.txt "$SINGBOX_DIR"/combo_links.txt
        install_combo
        return 0
    fi
    
    # 驥肴眠豺ｻ蜉�騾我ｸｭ逧�刻隶?
    for proto in "${selected_protos[@]}"; do
        echo -e "${Info} 豁｣蝨ｨ驥肴眠驟咲ｽｮ $proto..."
        case "$proto" in
            hysteria2) add_protocol_hy2 ;;
            tuic) add_protocol_tuic ;;
            vless) add_protocol_vless ;;
            anytls) add_protocol_anytls ;;
        esac
    done
    
    echo -e "${Info} 閾ｪ螳壻ｹ臥ｻ�粋驥崎｣�ｮ梧�?
}

# 菫ｮ謾ｹ闃らせ蜿よ焚
modify_node_params() {
    echo -e ""
    echo -e "${Cyan}========== 菫ｮ謾ｹ闃らせ蜿よ焚 ==========${Reset}"
    
    if [ ! -f "$SINGBOX_CONF" ]; then
        echo -e "${Warning} 驟咲ｽｮ譁�ｻｶ荳榊ｭ伜�?
        return 1
    fi
    
    echo -e " ${Green}1.${Reset} 菫ｮ謾ｹ遶ｯ蜿｣"
    echo -e " ${Green}2.${Reset} 菫ｮ謾ｹ蟇���"
    echo -e " ${Green}3.${Reset} 菫ｮ謾ｹ SNI"
    echo -e " ${Green}0.${Reset} 蜿匁ｶ�"
    
    read -p " 隸ｷ騾画叫: " modify_choice
    
    case "$modify_choice" in
        1)
            read -p "譁ｰ遶ｯ蜿? " new_port
            if [ -n "$new_port" ]; then
                # 菴ｿ逕ｨ sed 譖ｿ謐｢遶ｯ蜿｣ (邂蛹也沿)
                sed -i "s/\"listen_port\": *[0-9]*/\"listen_port\": $new_port/" "$SINGBOX_CONF"
                echo -e "${Info} 遶ｯ蜿｣蟾ｲ菫ｮ謾ｹ荳ｺ $new_port"
                restart_singbox
            fi
            ;;
        2)
            read -p "譁ｰ蟇��? " new_password
            if [ -n "$new_password" ]; then
                sed -i "s/\"password\": *\"[^\"]*\"/\"password\": \"$new_password\"/" "$SINGBOX_CONF"
                echo -e "${Info} 蟇��∝ｷｲ菫ｮ謾?
                restart_singbox
            fi
            ;;
        3)
            read -p "譁?SNI: " new_sni
            if [ -n "$new_sni" ]; then
                sed -i "s/\"server_name\": *\"[^\"]*\"/\"server_name\": \"$new_sni\"/" "$SINGBOX_CONF"
                echo -e "${Info} SNI 蟾ｲ菫ｮ謾ｹ荳ｺ $new_sni"
                restart_singbox
            fi
            ;;
        0) return 0 ;;
    esac
    
    echo -e "${Warning} 菫ｮ謾ｹ蜷手ｯｷ驥肴眠逕滓�蛻�ｺｫ體ｾ謗･"
}

# 螟榊宛蛻�ｺｫ體ｾ謗･
copy_share_links() {
    echo -e ""
    echo -e "${Cyan}========== 謇譛牙�莠ｫ體ｾ謗?==========${Reset}"
    
    for link_file in "$SINGBOX_DIR"/*_link.txt "$SINGBOX_DIR"/combo_links.txt; do
        if [ -f "$link_file" ]; then
            echo -e ""
            echo -e "${Yellow}$(cat "$link_file")${Reset}"
        fi
    done
    
    echo -e ""
    echo -e "${Tip} 隸ｷ謇句勘螟榊宛莉･荳企得謗?
}

view_config() {
    if [ -f "$SINGBOX_CONF" ]; then
        echo -e "${Green}==================== 驟咲ｽｮ譁�ｻｶ ====================${Reset}"
        cat "$SINGBOX_CONF"
        echo -e "${Green}=================================================${Reset}"
    else
        echo -e "${Warning} 驟咲ｽｮ譁�ｻｶ荳榊ｭ伜�?
    fi
}

# ==================== 蜊ｸ霓ｽ ====================
uninstall_singbox() {
    echo -e "${Warning} 遑ｮ螳夊ｦ∝査霓?sing-box? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    stop_singbox
    
    # 蛻�髯､ systemd 譛榊苅
    if [ -f /etc/systemd/system/sing-box.service ]; then
        systemctl disable sing-box
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload
    fi
    
    rm -rf "$SINGBOX_DIR"
    echo -e "${Info} sing-box 蟾ｲ蜊ｸ霓?
}

# ==================== 螟壼刻隶ｮ扈�粋螳芽｣?====================
install_combo() {
    echo -e ""
    echo -e "${Cyan}========== 閾ｪ螳壻ｹ牙､壼刻隶ｮ扈�粋 ==========${Reset}"
    echo -e "${Tip} 騾画叫隕∝ｮ芽｣�噪蜊剰ｮｮ扈�粋�梧髪謖∝酔譌ｶ霑占｡悟､壻ｸｪ蜊剰ｮ?
    echo -e ""
    
    # 遑ｮ菫� sing-box 蟾ｲ螳芽｣?
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 蜊剰ｮｮ騾画叫
    echo -e "${Info} 隸ｷ騾画叫隕∝星逕ｨ逧�刻隶ｮ (螟夐会ｼ檎畑騾怜捷蛻�囈):"
    echo -e " ${Green}1.${Reset} Hysteria2"
    echo -e " ${Green}2.${Reset} TUIC v5"
    echo -e " ${Green}3.${Reset} VLESS Reality"
    echo -e " ${Green}4.${Reset} Shadowsocks"
    echo -e " ${Green}5.${Reset} Trojan"
    echo -e " ${Green}6.${Reset} AnyTLS"
    echo -e " ${Green}7.${Reset} Any-Reality"
    echo -e ""
    echo -e " ${Cyan}遉ｺ萓�: 1,3,7 陦ｨ遉ｺ螳芽｣� Hysteria2 + VLESS + Any-Reality${Reset}"
    echo -e ""
    
    read -p "隸ｷ騾画叫 [1-7]: " combo_choice
    
    if [ -z "$combo_choice" ]; then
        echo -e "${Error} 譛ｪ騾画叫莉ｻ菴募刻隶ｮ"
        return 1
    fi
    
    # 隗｣譫宣画叫
    IFS=',' read -ra protocols <<< "$combo_choice"
    
    local install_hy2=false
    local install_tuic=false
    local install_vless=false
    local install_ss=false
    local install_trojan=false
    local install_anytls=false
    local install_any_reality=false
    
    for p in "${protocols[@]}"; do
        case "$(echo $p | tr -d ' ')" in
            1) install_hy2=true ;;
            2) install_tuic=true ;;
            3) install_vless=true ;;
            4) install_ss=true ;;
            5) install_trojan=true ;;
            6) install_anytls=true ;;
            7) install_any_reality=true ;;
        esac
    done
    
    # AnyTLS/Any-Reality 迚域悽譽譟?
    if [ "$install_anytls" = true ] || [ "$install_any_reality" = true ]; then
        if ! version_ge "$(get_version)" "1.12.0"; then
            echo -e "${Info} AnyTLS/Any-Reality 髴隕∝合郤?sing-box 蛻?1.12.0+�梧ｭ｣蝨ｨ閾ｪ蜉ｨ蜊�ｺ?.."
            download_singbox "1.12.0"
        fi
    fi
    
    # 驟咲ｽｮ隸∽ｹｦ (Hysteria2, TUIC, Trojan 髴隕?
    if [ "$install_hy2" = true ] || [ "$install_tuic" = true ] || [ "$install_trojan" = true ]; then
        echo -e ""
        echo -e "${Info} 譽豬句芦髴隕?TLS 隸∽ｹｦ逧�刻隶?
        cert_menu
    fi
    
    # 逕滓�扈滉ｸ逧?UUID 蜥悟ｯ��?(FreeBSD 蜈ｼ螳ｹ)
    init_uuid
    local password="$uuid"  # 蜥?argosbx 荳譬ｷ�御ｽｿ逕ｨ UUID 菴應ｸｺ蟇���
    
    echo -e ""
    echo -e "${Info} 扈滉ｸ隶､隸∽ｿ｡諱ｯ:"
    echo -e " UUID/蟇���: ${Cyan}${uuid}${Reset}"
    echo -e ""
    
    # 遶ｯ蜿｣驟咲ｽｮ譁ｹ蠑�
    echo -e "${Info} 遶ｯ蜿｣驟咲ｽｮ譁ｹ蠑�:"
    echo -e " ${Green}1.${Reset} 閾ｪ蜉ｨ蛻��髫乗惻遶ｯ蜿｣ (謗ｨ闕�)"
    echo -e " ${Green}2.${Reset} 謇句勘謖�ｮ夂ｫｯ蜿｣"
    read -p "隸ｷ騾画叫 [1-2]: " port_mode
    
    local hy2_port=""
    local tuic_port=""
    local vless_port=""
    local ss_port=""
    local trojan_port=""
    local anytls_port=""
    local ar_port=""
    
    if [ "$port_mode" = "2" ]; then
        # 謇句勘謖�ｮ夂ｫｯ蜿｣
        echo -e ""
        echo -e "${Info} 隸ｷ荳ｺ豈丈ｸｪ蜊剰ｮｮ謖�ｮ夂ｫｯ蜿｣ (逡咏ｩｺ霍ｳ霑�):"
        
        if [ "$install_hy2" = true ]; then
            read -p "Hysteria2 遶ｯ蜿｣: " hy2_port
            [ -z "$hy2_port" ] && hy2_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_tuic" = true ]; then
            read -p "TUIC 遶ｯ蜿｣: " tuic_port
            [ -z "$tuic_port" ] && tuic_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_vless" = true ]; then
            read -p "VLESS Reality 遶ｯ蜿｣: " vless_port
            [ -z "$vless_port" ] && vless_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_ss" = true ]; then
            read -p "Shadowsocks 遶ｯ蜿｣: " ss_port
            [ -z "$ss_port" ] && ss_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_trojan" = true ]; then
            read -p "Trojan 遶ｯ蜿｣: " trojan_port
            [ -z "$trojan_port" ] && trojan_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_anytls" = true ]; then
            read -p "AnyTLS 遶ｯ蜿｣: " anytls_port
            [ -z "$anytls_port" ] && anytls_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_any_reality" = true ]; then
            read -p "Any-Reality 遶ｯ蜿｣: " ar_port
            [ -z "$ar_port" ] && ar_port=$(shuf -i 10000-65535 -n 1)
        fi
    else
        # 閾ｪ蜉ｨ蛻��
        local base_port=$(shuf -i 10000-50000 -n 1)
        [ "$install_hy2" = true ] && hy2_port=$((base_port))
        [ "$install_tuic" = true ] && tuic_port=$((base_port + 1))
        [ "$install_vless" = true ] && vless_port=$((base_port + 2))
        [ "$install_ss" = true ] && ss_port=$((base_port + 3))
        [ "$install_trojan" = true ] && trojan_port=$((base_port + 4))
        [ "$install_anytls" = true ] && anytls_port=$((base_port + 5))
        [ "$install_any_reality" = true ] && ar_port=$((base_port + 6))
    fi
    
    echo -e ""
    echo -e "${Info} 遶ｯ蜿｣蛻��:"
    [ -n "$hy2_port" ] && echo -e " Hysteria2: ${Cyan}${hy2_port}${Reset}"
    [ -n "$ss_port" ] && echo -e " Shadowsocks: ${Cyan}${ss_port}${Reset}"
    [ -n "$trojan_port" ] && echo -e " Trojan: ${Cyan}${trojan_port}${Reset}"
    [ -n "$anytls_port" ] && echo -e " AnyTLS: ${Cyan}${anytls_port}${Reset}"
    [ -n "$ar_port" ] && echo -e " Any-Reality: ${Cyan}${ar_port}${Reset}"
    [ -n "$vless_port" ] && echo -e " VLESS: ${Cyan}${vless_port}${Reset}"
    [ -n "$ss_port" ] && echo -e " SS: ${Cyan}${ss_port}${Reset}"
    [ -n "$trojan_port" ] && echo -e " Trojan: ${Cyan}${trojan_port}${Reset}"
    [ -n "$anytls_port" ] && echo -e " AnyTLS: ${Cyan}${anytls_port}${Reset}"
    
    # 譫�ｻｺ驟咲ｽｮ
    local inbounds=""
    local server_ip=$(get_ip)
    local node_info=""
    local links=""
    
    # Hysteria2 驟咲ｽｮ (蜿ら�螳俶婿譁�｡｣)
    if [ "$install_hy2" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"hysteria2\",
      \"tag\": \"hy2-in\",
      \"listen\": \"::\",
      \"listen_port\": ${hy2_port},
      \"users\": [
        {
          \"name\": \"user\",
          \"password\": \"${password}\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"alpn\": [\"h3\"],
        \"certificate_path\": \"${CERT_DIR}/cert.pem\",
        \"key_path\": \"${CERT_DIR}/private.key\"
      }
    }"
        
        node_info="${node_info}
[Hysteria2]
遶ｯ蜿｣: ${hy2_port}
蟇���: ${password}
SNI: ${CERT_DOMAIN:-www.bing.com}"
        
        links="${links}
hysteria2://${password}@${server_ip}:${hy2_port}?sni=${CERT_DOMAIN:-www.bing.com}&insecure=1#Hy2-${server_ip}"
    fi
    
    # TUIC 驟咲ｽｮ
    if [ "$install_tuic" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"tuic\",
      \"tag\": \"tuic-in\",
      \"listen\": \"::\",
      \"listen_port\": ${tuic_port},
      \"users\": [
        {
          \"name\": \"user\",
          \"uuid\": \"${uuid}\",
          \"password\": \"${password}\"
        }
      ],
      \"congestion_control\": \"bbr\",
      \"tls\": {
        \"enabled\": true,
        \"alpn\": [\"h3\"],
        \"certificate_path\": \"${CERT_DIR}/cert.pem\",
        \"key_path\": \"${CERT_DIR}/private.key\"
      }
    }"
        
        node_info="${node_info}

[TUIC v5]
遶ｯ蜿｣: ${tuic_port}
UUID: ${uuid}
蟇���: ${password}
SNI: ${CERT_DOMAIN:-www.bing.com}"
        
        links="${links}
tuic://${uuid}:${password}@${server_ip}:${tuic_port}?sni=${CERT_DOMAIN:-www.bing.com}&congestion_control=bbr&alpn=h3&udp_relay_mode=native&allow_insecure=1#TUIC-${server_ip}"
    fi
    
    # VLESS Reality 驟咲ｽｮ
    if [ "$install_vless" = true ]; then
        echo -e "${Info} 逕滓� Reality 蟇�徴..."
        mkdir -p "$CERT_DIR/reality"
        
        # 螟咲畑蟾ｲ譛牙ｯ�徴謌也函謌先眠逧?(蜿ら� argosbx)
        # 譽譟･蟾ｲ譛牙ｯ�徴譏ｯ蜷ｦ譛画�?(髱樒ｩｺ)
        if [ -s "$CERT_DIR/reality/private_key" ] && [ -s "$CERT_DIR/reality/public_key" ]; then
            private_key=$(cat "$CERT_DIR/reality/private_key")
            public_key=$(cat "$CERT_DIR/reality/public_key")
            short_id=$(cat "$CERT_DIR/reality/short_id" 2>/dev/null)
            echo -e "${Info} 菴ｿ逕ｨ蟾ｲ譛� Reality 蟇�徴"
        fi
        
        # 螯よ棡蟇�徴荳ｺ遨ｺ�碁㍾譁ｰ逕滓�?
        if [ -z "$private_key" ] || [ -z "$public_key" ]; then
            echo -e "${Info} 逕滓�譁ｰ逧� Reality 蟇�徴蟇?.."
            local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
            private_key=$(echo "$keypair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
            public_key=$(echo "$keypair" | awk '/PublicKey/ {print $2}' | tr -d '"')
            
            # 鬪瑚ｯ∝ｯ�徴譏ｯ蜷ｦ逕滓�謌仙粥
            if [ -z "$private_key" ] || [ -z "$public_key" ]; then
                echo -e "${Error} Reality 蟇�徴逕滓�螟ｱ雍･�瑚ｯｷ遑ｮ菫� sing-box 迚域悽謾ｯ謖� reality-keypair"
                echo -e "${Info} 蟆晁ｯ墓焔蜉ｨ謇ｧ陦�: $SINGBOX_BIN generate reality-keypair"
                return 1
            fi
            
            # FreeBSD 蜈ｼ螳ｹ逧?short_id 逕滓�
            short_id=$($SINGBOX_BIN generate rand --hex 4 2>/dev/null)
            [ -z "$short_id" ] && short_id=$(od -An -tx1 -N 4 /dev/urandom 2>/dev/null | tr -d ' \n')
            [ -z "$short_id" ] && short_id=$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 8)
            [ -z "$short_id" ] && short_id="12345678"  # 譛蜷惹ｿ晏ｺ?
            
            # 菫晏ｭ伜ｯ�徴
            echo "$private_key" > "$CERT_DIR/reality/private_key"
            echo "$public_key" > "$CERT_DIR/reality/public_key"
            echo "$short_id" > "$CERT_DIR/reality/short_id"
            echo -e "${Info} Reality 蟇�徴蟾ｲ菫晏ｭ?
        fi
        local dest="apple.com"
        
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"vless\",
      \"tag\": \"vless-in\",
      \"listen\": \"::\",
      \"listen_port\": ${vless_port},
      \"users\": [
        {
          \"name\": \"user\",
          \"uuid\": \"${uuid}\",
          \"flow\": \"xtls-rprx-vision\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"server_name\": \"${dest}\",
        \"reality\": {
          \"enabled\": true,
          \"handshake\": {
            \"server\": \"${dest}\",
            \"server_port\": 443
          },
          \"private_key\": \"${private_key}\",
          \"short_id\": [\"${short_id}\"]
        }
      }
    }"
        
        node_info="${node_info}

[VLESS Reality]
遶ｯ蜿｣: ${vless_port}
UUID: ${uuid}
SNI: ${dest}
蜈ｬ髓･: ${public_key}
Short ID: ${short_id}"
        
        links="${links}
vless://${uuid}@${server_ip}:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${dest}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#VLESS-Reality-${server_ip}"
    fi
    
    # Shadowsocks 驟咲ｽｮ
    if [ "$install_ss" = true ]; then
        local ss_method="2022-blake3-aes-256-gcm"
        local ss_password=$(openssl rand -base64 32 2>/dev/null || head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 | base64)
        
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"shadowsocks\",
      \"tag\": \"ss-in\",
      \"listen\": \"::\",
      \"listen_port\": ${ss_port},
      \"method\": \"${ss_method}\",
      \"password\": \"${ss_password}\"
    }"
        
        node_info="${node_info}

[Shadowsocks]
遶ｯ蜿｣: ${ss_port}
蜉�蟇�婿蠑�: ${ss_method}
蟇���: ${ss_password}"
        
        local ss_userinfo=$(echo -n "${ss_method}:${ss_password}" | base64 -w0)
        links="${links}
ss://${ss_userinfo}@${server_ip}:${ss_port}#SS-${server_ip}"
    fi
    
    # Trojan 驟咲ｽｮ
    if [ "$install_trojan" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"trojan\",
      \"tag\": \"trojan-in\",
      \"listen\": \"::\",
      \"listen_port\": ${trojan_port},
      \"users\": [
        {
          \"password\": \"${password}\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"certificate_path\": \"${CERT_DIR}/cert.pem\",
        \"key_path\": \"${CERT_DIR}/private.key\"
      }
    }"
        
        node_info="${node_info}

[Trojan]
遶ｯ蜿｣: ${trojan_port}
蟇���: ${password}
SNI: ${CERT_DOMAIN:-www.bing.com}"
        
        links="${links}
trojan://${password}@${server_ip}:${trojan_port}?sni=${CERT_DOMAIN:-www.bing.com}&allowInsecure=1#Trojan-${server_ip}"
    fi
    # AnyTLS 驟咲ｽｮ
    if [ "$install_anytls" = true ]; then
        # 逕滓�閾ｪ遲ｾ隸∽ｹｦ
        local cert_domain="bing.com"
        openssl req -x509 -newkey ec:<(openssl ecparam -name prime256v1) \
            -keyout "$CERT_DIR/anytls.key" \
            -out "$CERT_DIR/anytls.crt" \
            -days 36500 -nodes \
            -subj "/CN=$cert_domain" 2>/dev/null || \
        openssl req -x509 -newkey rsa:2048 \
            -keyout "$CERT_DIR/anytls.key" \
            -out "$CERT_DIR/anytls.crt" \
            -days 36500 -nodes \
            -subj "/CN=$cert_domain" 2>/dev/null
        
        local anytls_mixed_port=$(shuf -i 20000-60000 -n 1)
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        # 蜿ら� argosbx 逧�ｮ蜊暮�鄂ｮ�御ｸ埼怙隕?detour
        inbounds="${inbounds}
    {
      \"type\": \"anytls\",
      \"tag\": \"anytls-in\",
      \"listen\": \"::\",
      \"listen_port\": ${anytls_port},
      \"users\": [{\"password\": \"${password}\"}],
      \"padding_scheme\": [],
      \"tls\": {
        \"enabled\": true,
        \"certificate_path\": \"$CERT_DIR/anytls.crt\",
        \"key_path\": \"$CERT_DIR/anytls.key\"
      }
    }"
    
    node_info="${node_info}
[AnyTLS]
遶ｯ蜿｣: ${anytls_port}
蟇���: ${password}
SNI: ${server_ip}
隸∽ｹｦ: 閾ｪ遲ｾ隸∽ｹｦ
隸ｴ譏�: 髴 sing-box 1.12.0+ 謌?Clash Meta�悟ｮ｢謌ｷ遶ｯ髴蜷ｯ逕ｨ skip-cert-verify"

    # 逕滓�蛻�ｺｫ體ｾ謗･蜥繰SON
    local anytls_link="anytls://${password}@${server_ip}:${anytls_port}?insecure=1&sni=${server_ip}&fp=chrome&alpn=h2,http/1.1&udp=1#AnyTLS-${server_ip}"
    local out_json="{\"type\":\"anytls\",\"tag\":\"anytls-out\",\"server\":\"$server_ip\",\"server_port\":$anytls_port,\"password\":\"$password\",\"tls\":{\"enabled\":true,\"server_name\":\"$server_ip\",\"insecure\":true}}"
    links="${links}
${anytls_link}"
    fi

    # Any-Reality 驟咲ｽｮ
    if [ "$install_any_reality" = true ]; then
        # 螟咲畑蟾ｲ譛牙ｯ�徴謌紋ｽｿ逕?VLESS 逕滓�逧�ｯ��?(蜿ら� argosbx)
        mkdir -p "$CERT_DIR/reality"
        
        # 譽譟･蟾ｲ譛牙ｯ�徴譏ｯ蜷ｦ譛画�?(髱樒ｩｺ)
        if [ -s "$CERT_DIR/reality/private_key" ] && [ -s "$CERT_DIR/reality/public_key" ]; then
            private_key=$(cat "$CERT_DIR/reality/private_key")
            public_key=$(cat "$CERT_DIR/reality/public_key")
            short_id=$(cat "$CERT_DIR/reality/short_id" 2>/dev/null)
            echo -e "${Info} 菴ｿ逕ｨ蟾ｲ譛� Reality 蟇�徴"
        fi
        
        # 螯よ棡蟇�徴荳ｺ遨ｺ�碁㍾譁ｰ逕滓�?
        if [ -z "$private_key" ] || [ -z "$public_key" ]; then
            echo -e "${Info} 逕滓�譁ｰ逧� Reality 蟇�徴蟇?.."
            local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
            private_key=$(echo "$keypair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
            public_key=$(echo "$keypair" | awk '/PublicKey/ {print $2}' | tr -d '"')
            
            # 鬪瑚ｯ∝ｯ�徴譏ｯ蜷ｦ逕滓�謌仙粥
            if [ -z "$private_key" ] || [ -z "$public_key" ]; then
                echo -e "${Error} Reality 蟇�徴逕滓�螟ｱ雍･�瑚ｯｷ遑ｮ菫� sing-box 迚域悽謾ｯ謖� reality-keypair"
                echo -e "${Info} 蟆晁ｯ墓焔蜉ｨ謇ｧ陦�: $SINGBOX_BIN generate reality-keypair"
                return 1
            fi
            
            # FreeBSD 蜈ｼ螳ｹ逧?short_id 逕滓�
            short_id=$($SINGBOX_BIN generate rand --hex 4 2>/dev/null)
            [ -z "$short_id" ] && short_id=$(od -An -tx1 -N 4 /dev/urandom 2>/dev/null | tr -d ' \n')
            [ -z "$short_id" ] && short_id=$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 8)
            [ -z "$short_id" ] && short_id="12345678"  # 譛蜷惹ｿ晏ｺ?
            
            echo "$private_key" > "$CERT_DIR/reality/private_key"
            echo "$public_key" > "$CERT_DIR/reality/public_key"
            echo "$short_id" > "$CERT_DIR/reality/short_id"
            echo -e "${Info} Reality 蟇�徴蟾ｲ菫晏ｭ?
        fi
        
        local ar_dest="apple.com"
        local ar_server_name="apple.com"
        
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        # 蜿ら� argosbx 逧�ｮ蜊暮�鄂ｮ�御ｸ埼怙隕?detour
        inbounds="${inbounds}
    {
      \"type\": \"anytls\",
      \"tag\": \"anyreality-in\",
      \"listen\": \"::\",
      \"listen_port\": ${ar_port},
      \"users\": [{\"password\": \"${password}\"}],
      \"padding_scheme\": [],
      \"tls\": {
        \"enabled\": true,
        \"server_name\": \"${ar_server_name}\",
        \"reality\": {
          \"enabled\": true,
          \"handshake\": {
            \"server\": \"${ar_dest}\",
            \"server_port\": 443
          },
          \"private_key\": \"${private_key}\",
          \"short_id\": [\"${short_id}\"]
        }
      }
    }"

        node_info="${node_info}
[Any-Reality]
遶ｯ蜿｣: ${ar_port}
蟇���: ${password}
SNI: ${ar_server_name}
Short ID: ${short_id}
Public Key: ${public_key}
隸ｴ譏�: 謖�ｺｹ(fp)蟒ｺ隶ｮ菴ｿ逕ｨ chrome"

        local ar_link="anytls://${password}@${server_ip}:${ar_port}?security=reality&sni=${ar_server_name}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#Any-Reality-${server_ip}"
        links="${links}
${ar_link}"
    fi
    
    # 隸｢髣ｮ譏ｯ蜷ｦ蜷ｯ逕ｨ WARP 蜃ｺ遶�
    ask_warp_outbound
    
    # 逕滓�螳梧紛驟咲ｽｮ
    local exp_config=$(get_experimental_config)
    local outbounds_config=$(get_outbounds_config "$WARP_ENABLED")
    
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
${exp_config}  "inbounds": [${inbounds}
  ],
${outbounds_config}
}
EOF
    
    # 菫晏ｭ倩鰍轤ｹ菫｡諱ｯ
    local active_protocols=""
    [ "$install_hy2" = true ] && active_protocols="${active_protocols}Hysteria2 "
    [ "$install_tuic" = true ] && active_protocols="${active_protocols}TUIC "
    [ "$install_vless" = true ] && active_protocols="${active_protocols}VLESS "
    [ "$install_ss" = true ] && active_protocols="${active_protocols}SS "
    [ "$install_trojan" = true ] && active_protocols="${active_protocols}Trojan "
    
    cat > "$SINGBOX_DIR/node_info.txt" << EOF
============= 螟壼刻隶ｮ扈�粋闃ら�?=============
譛榊苅蝎? ${server_ip}
蜷ｯ逕ｨ蜊剰ｮｮ: ${active_protocols}
${node_info}
==========================================
EOF
    
    echo "$links" > "$SINGBOX_DIR/combo_links.txt"
    
    echo -e ""
    echo -e "${Green}========== 螟壼刻隶ｮ扈�粋螳芽｣�ｮ梧�?==========${Reset}"
    echo -e ""
    echo -e " 譛榊苅蝎? ${Cyan}${server_ip}${Reset}"
    echo -e " 蜷ｯ逕ｨ蜊剰ｮｮ: ${Green}${active_protocols}${Reset}"
    echo -e ""
    
    [ "$install_hy2" = true ] && echo -e " Hysteria2 遶ｯ蜿｣: ${Cyan}${hy2_port}${Reset}"
    [ "$install_tuic" = true ] && echo -e " TUIC 遶ｯ蜿｣: ${Cyan}${tuic_port}${Reset}"
    [ "$install_vless" = true ] && echo -e " VLESS 遶ｯ蜿｣: ${Cyan}${vless_port}${Reset}"
    [ "$install_ss" = true ] && echo -e " SS 遶ｯ蜿｣: ${Cyan}${ss_port}${Reset}"
    [ "$install_trojan" = true ] && echo -e " Trojan 遶ｯ蜿｣: ${Cyan}${trojan_port}${Reset}"
    
    echo -e ""
    echo -e "${Green}=========================================${Reset}"
    echo -e ""
    echo -e "${Info} 蛻�ｺｫ體ｾ謗･蟾ｲ菫晏ｭ伜芦: ${Cyan}$SINGBOX_DIR/combo_links.txt${Reset}"
    echo -e ""
    
    # 譏ｾ遉ｺ體ｾ謗･
    echo -e "${Yellow}蛻�ｺｫ體ｾ謗･:${Reset}"
    echo -e "${links}"
    echo -e ""
    
    # 蜷ｯ蜉ｨ譛榊苅
    read -p "譏ｯ蜷ｦ遶句叉蜷ｯ蜉ｨ? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# 鬚�ｮｾ扈�粋
install_preset_combo() {
    echo -e ""
    echo -e "${Cyan}========== 鬚�ｮｾ蜊剰ｮｮ扈�粋 ==========${Reset}"
    echo -e ""
    echo -e " ${Green}1.${Reset} 譬�㊥扈�粋 (Hysteria2 + TUIC)"
    echo -e "    ${Cyan}騾ょ粋: 譌･蟶ｸ菴ｿ逕ｨ�袈DP 貂ｸ謌�${Reset}"
    echo -e ""
    echo -e " ${Green}2.${Reset} 蜈ｨ閭ｽ扈�粋 (Hysteria2 + TUIC + VLESS Reality)"
    echo -e "    ${Cyan}騾ょ粋: 蜈ｨ蝨ｺ譎ｯ隕��?{Reset}"
    echo -e ""
    echo -e " ${Green}3.${Reset} 蜈崎ｴｹ遶ｯ蜿｣扈�粋 (VLESS Reality + Shadowsocks)"
    echo -e "    ${Cyan}騾ょ粋: Serv00/譌?UDP 邇ｯ蠅�${Reset}"
    echo -e ""
    echo -e " ${Green}4.${Reset} 螳梧紛扈�粋 (蜈ｨ驛ｨ 5 遘榊刻隶?"
    echo -e "    ${Cyan}騾ょ粋: 豬玖ｯ募柱迚ｹ谿企怙豎?{Reset}"
    echo -e ""
    
    read -p "隸ｷ騾画叫鬚�ｮｾ [1-4]: " preset_choice
    
    case "$preset_choice" in
        1)
            echo "1,2" | { read combo_choice; install_combo_internal "1,2"; }
            ;;
        2)
            install_combo_internal "1,2,3"
            ;;
        3)
            install_combo_internal "3,4"
            ;;
        4)
            install_combo_internal "1,2,3,4,5"
            ;;
        *)
            echo -e "${Error} 譌�謨磯画叫"
            return 1
            ;;
    esac
}

# 蜀�Κ扈�粋螳芽｣��謨ｰ
install_combo_internal() {
    local combo_choice=$1
    
    # 遑ｮ菫� sing-box 蟾ｲ螳芽｣?
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 隗｣譫宣画叫
    IFS=',' read -ra protocols <<< "$combo_choice"
    
    local install_hy2=false
    local install_tuic=false
    local install_vless=false
    local install_ss=false
    local install_trojan=false
    
    for p in "${protocols[@]}"; do
        case "$(echo $p | tr -d ' ')" in
            1) install_hy2=true ;;
            2) install_tuic=true ;;
            3) install_vless=true ;;
            4) install_ss=true ;;
            5) install_trojan=true ;;
        esac
    done
    
    # 驟咲ｽｮ隸∽ｹｦ
    # 驟咲ｽｮ隸∽ｹｦ
    if [ "$install_hy2" = true ] || [ "$install_tuic" = true ] || [ "$install_trojan" = true ]; then
        if ! cert_menu; then
            return 1
        fi
    fi
    
    # 逕滓�隶､隸∽ｿ｡諱ｯ
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null)
    local password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    # 蛻��遶ｯ蜿｣
    local base_port=$(shuf -i 10000-50000 -n 1)
    local hy2_port=$((base_port))
    local tuic_port=$((base_port + 1))
    local vless_port=$((base_port + 2))
    local ss_port=$((base_port + 3))
    local trojan_port=$((base_port + 4))
    
    local server_ip=$(get_ip)
    local inbounds=""
    local links=""
    
    # 譫�ｻｺ驟咲ｽｮ (邂蛹也沿�悟､咲畑荳企擇逧�ｻ霎�)
    if [ "$install_hy2" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"hysteria2\",\"tag\":\"hy2\",\"listen\":\"::\",\"listen_port\":${hy2_port},\"users\":[{\"password\":\"${password}\"}],\"tls\":{\"enabled\":true,\"alpn\":[\"h3\"],\"certificate_path\":\"${CERT_DIR}/cert.pem\",\"key_path\":\"${CERT_DIR}/private.key\"}}"
        links="${links}\nhysteria2://${password}@${server_ip}:${hy2_port}?sni=${CERT_DOMAIN:-www.bing.com}&insecure=1#Hy2"
    fi
    
    if [ "$install_tuic" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"tuic\",\"tag\":\"tuic\",\"listen\":\"::\",\"listen_port\":${tuic_port},\"users\":[{\"uuid\":\"${uuid}\",\"password\":\"${password}\"}],\"congestion_control\":\"bbr\",\"tls\":{\"enabled\":true,\"alpn\":[\"h3\"],\"certificate_path\":\"${CERT_DIR}/cert.pem\",\"key_path\":\"${CERT_DIR}/private.key\"}}"
        links="${links}\ntuic://${uuid}:${password}@${server_ip}:${tuic_port}?sni=${CERT_DOMAIN:-www.bing.com}&congestion_control=bbr&alpn=h3&allow_insecure=1#TUIC"
    fi
    
    if [ "$install_vless" = true ]; then
        local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
        local private_key=$(echo "$keypair" | grep -i "privatekey" | awk '{print $2}')
        local public_key=$(echo "$keypair" | grep -i "publickey" | awk '{print $2}')
        local short_id=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)
        
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"vless\",\"tag\":\"vless\",\"listen\":\"::\",\"listen_port\":${vless_port},\"users\":[{\"uuid\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\"}],\"tls\":{\"enabled\":true,\"server_name\":\"www.apple.com\",\"reality\":{\"enabled\":true,\"handshake\":{\"server\":\"www.apple.com\",\"server_port\":443},\"private_key\":\"${private_key}\",\"short_id\":[\"${short_id}\"]}}}"
        links="${links}\nvless://${uuid}@${server_ip}:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.apple.com&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#VLESS-Reality"
    fi
    
    if [ "$install_ss" = true ]; then
        local ss_pass=$(openssl rand -base64 32 2>/dev/null)
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"shadowsocks\",\"tag\":\"ss\",\"listen\":\"::\",\"listen_port\":${ss_port},\"method\":\"2022-blake3-aes-256-gcm\",\"password\":\"${ss_pass}\"}"
        local ss_ui=$(echo -n "2022-blake3-aes-256-gcm:${ss_pass}" | base64 -w0)
        links="${links}\nss://${ss_ui}@${server_ip}:${ss_port}#SS"
    fi
    
    if [ "$install_trojan" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"trojan\",\"tag\":\"trojan\",\"listen\":\"::\",\"listen_port\":${trojan_port},\"users\":[{\"password\":\"${password}\"}],\"tls\":{\"enabled\":true,\"certificate_path\":\"${CERT_DIR}/cert.pem\",\"key_path\":\"${CERT_DIR}/private.key\"}}"
        links="${links}\ntrojan://${password}@${server_ip}:${trojan_port}?sni=${CERT_DOMAIN:-www.bing.com}&allowInsecure=1#Trojan"
    fi
    
    # 隸｢髣ｮ譏ｯ蜷ｦ蜷ｯ逕ｨ WARP 蜃ｺ遶�
    ask_warp_outbound
    
    # 逕滓�驟咲ｽｮ
    local outbounds_json=""
    if [ "$WARP_ENABLED" = true ] && [ -n "$WARP_PRIVATE_KEY" ]; then
        local warp_endpoint=$(get_warp_endpoint)
        local ep_ip=""
        local ep_port="2408"
        
        if echo "$warp_endpoint" | grep -q "]:"; then
            ep_ip=$(echo "$warp_endpoint" | sed 's/\]:.*/]/' | sed 's/^\[//' | sed 's/\]$//')
            ep_port=$(echo "$warp_endpoint" | sed 's/.*\]://')
        elif echo "$warp_endpoint" | grep -q ":"; then
            ep_ip=$(echo "$warp_endpoint" | cut -d: -f1)
            ep_port=$(echo "$warp_endpoint" | cut -d: -f2)
        else
            ep_ip="$warp_endpoint"
        fi
        
        local warp_ipv6="${WARP_IPV6:-2606:4700:110:8f1a:c53:a4c5:2249:1546}"
        local warp_reserved="${WARP_RESERVED:-[0,0,0]}"
        # 菴ｿ逕ｨ argosbx 逧�ｭ｣遑ｮ譬ｼ蠑擾ｼ啼ndpoint tag 荳?warp-out�罫oute.final 逶ｴ謗･謖�髄螳?
        outbounds_json="{\"type\":\"direct\",\"tag\":\"direct\"}],\"endpoints\":[{\"type\":\"wireguard\",\"tag\":\"warp-out\",\"address\":[\"172.16.0.2/32\",\"${warp_ipv6}/128\"],\"private_key\":\"${WARP_PRIVATE_KEY}\",\"peers\":[{\"address\":\"${ep_ip}\",\"port\":${ep_port},\"public_key\":\"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=\",\"allowed_ips\":[\"0.0.0.0/0\",\"::/0\"],\"reserved\":${warp_reserved}}]}],\"route\":{\"rules\":[{\"action\":\"sniff\"},{\"action\":\"resolve\",\"strategy\":\"prefer_ipv4\"}],\"final\":\"warp-out\"}"
    else
        outbounds_json="{\"type\":\"direct\",\"tag\":\"direct\"}]"
    fi
    
    echo "{\"log\":{\"level\":\"info\"},\"inbounds\":[${inbounds}],\"outbounds\":[${outbounds_json}}" | python3 -m json.tool 2>/dev/null > "$SINGBOX_CONF" || echo "{\"log\":{\"level\":\"info\"},\"inbounds\":[${inbounds}],\"outbounds\":[${outbounds_json}}" > "$SINGBOX_CONF"
    
    echo -e "$links" > "$SINGBOX_DIR/combo_links.txt"
    
    echo -e ""
    echo -e "${Green}========== 鬚�ｮｾ扈�粋螳芽｣�ｮ梧� ==========${Reset}"
    echo -e ""
    echo -e "${Info} 蛻�ｺｫ體ｾ謗･:"
    echo -e "${Yellow}$(echo -e "$links")${Reset}"
    echo -e ""
    
    read -p "譏ｯ蜷ｦ遶句叉蜷ｯ蜉ｨ? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# ==================== 霎�勧蜉溯� ====================
# 譟･逵区律蠢�
view_logs() {
    echo -e ""
    echo -e "${Cyan}========== sing-box 譌･蠢� ==========${Reset}"
    echo -e ""
    
    # 莨伜�菴ｿ逕ｨ journalctl
    if command -v journalctl &>/dev/null && systemctl is-active sing-box &>/dev/null 2>&1; then
        echo -e "${Info} 菴ｿ逕ｨ journalctl 譟･逵区律蠢� (譛霑?50 陦?:"
        echo -e ""
        journalctl -u sing-box -n 50 --no-pager
    elif [ -f "$SINGBOX_LOG" ]; then
        echo -e "${Info} 譌･蠢玲枚莉ｶ: $SINGBOX_LOG"
        echo -e ""
        tail -n 50 "$SINGBOX_LOG"
    else
        echo -e "${Warning} 譛ｪ謇ｾ蛻ｰ譌･蠢玲枚莉?
        echo -e ""
        echo -e "${Tip} 蟆晁ｯ墓衍逵� journalctl:"
        journalctl -u sing-box -n 30 --no-pager 2>/dev/null || echo -e "${Error} journalctl 荵滓ｲ｡譛画律蠢?
    fi
    
    echo -e ""
    echo -e "${Green}====================================${Reset}"
}

# 譟･逵矩�鄂ｮ譁�ｻｶ
view_config() {
    echo -e ""
    echo -e "${Cyan}========== sing-box 驟咲ｽｮ ==========${Reset}"
    echo -e ""
    
    if [ -f "$SINGBOX_CONF" ]; then
        echo -e "${Info} 驟咲ｽｮ譁�ｻｶ: $SINGBOX_CONF"
        echo -e ""
        
        # 蟆晁ｯ慕�?jq 譬ｼ蠑丞喧�悟凄蛻咏峩謗･ cat
        if command -v jq &>/dev/null; then
            jq '.' "$SINGBOX_CONF" 2>/dev/null || cat "$SINGBOX_CONF"
        else
            cat "$SINGBOX_CONF"
        fi
    else
        echo -e "${Error} 驟咲ｽｮ譁�ｻｶ荳榊ｭ伜�? $SINGBOX_CONF"
    fi
    
    echo -e ""
    echo -e "${Green}====================================${Reset}"
}

# 譟･逵玖鰍轤ｹ菫｡諱ｯ
show_node_info() {
    echo -e ""
    echo -e "${Cyan}========== 闃らせ菫｡諱ｯ ==========${Reset}"
    echo -e ""
    
    # 隸ｻ蜿紋ｿ晏ｭ倡噪體ｾ謗?
    if [ -f "$SINGBOX_DIR/combo_links.txt" ]; then
        echo -e "${Info} 蛻�ｺｫ體ｾ謗･:"
        echo -e ""
        cat "$SINGBOX_DIR/combo_links.txt"
    elif [ -f "$LINKS_FILE" ]; then
        echo -e "${Info} 蛻�ｺｫ體ｾ謗･:"
        echo -e ""
        cat "$LINKS_FILE"
    else
        echo -e "${Warning} 譛ｪ謇ｾ蛻ｰ闃らせ體ｾ謗･譁�ｻ?
        echo -e "${Tip} 隸ｷ驥肴眠螳芽｣�鰍轤ｹ莉･逕滓�體ｾ謗･"
    fi
    
    echo -e ""
    echo -e "${Green}===============================${Reset}"
}

# ==================== 荳ｻ闖懷�?====================
show_singbox_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    笊披武笊冷沸笊披風笊披部笊絶風   笊披風 笊披武笊冷武笊?笊?
    笊壺武笊冷舞笊鯛舞笊鯛舞 笊ｦ笏笏笏笊�笊ｩ笊冷舞 笊鯛部笊ｩ笊ｦ笊?
    笊壺武笊昶鮒笊昶伏笊昶伏笊絶幅   笊壺武笊昶伏笊絶幅笊?笊壺武
    螟壼刻隶ｮ莉｣逅�鰍轤?
EOF
        echo -e "${Reset}"
        
        # 譏ｾ遉ｺ迥ｶ諤?
        if [ -f "$SINGBOX_BIN" ]; then
            echo -e " 螳芽｣�憾諤? ${Green}蟾ｲ螳芽｣?{Reset}"
            if pgrep -f "sing-box" &>/dev/null; then
                echo -e " 霑占｡檎憾諤? ${Green}霑占｡御ｸ?{Reset}"
            else
                echo -e " 霑占｡檎憾諤? ${Red}蟾ｲ蛛懈ｭ?{Reset}"
            fi
        else
            echo -e " 螳芽｣�憾諤? ${Yellow}譛ｪ螳芽｣?{Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== sing-box 邂｡逅� ====================${Reset}"
        echo -e " ${Yellow}蜊募刻隶ｮ螳芽｣?{Reset}"
        echo -e " ${Green}1.${Reset}  Hysteria2 (謗ｨ闕�)"
        echo -e " ${Green}2.${Reset}  TUIC v5"
        echo -e " ${Green}3.${Reset}  VLESS Reality"
        echo -e " ${Green}4.${Reset}  AnyTLS (譁?"
        echo -e " ${Green}5.${Reset}  ${Cyan}Any-Reality${Reset} (AnyTLS + Reality)"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}螟壼刻隶ｮ扈��?{Reset}"
        echo -e " ${Green}6.${Reset}  ${Cyan}閾ｪ螳壻ｹ臥ｻ��?{Reset} (螟夐牙刻隶?"
        echo -e " ${Green}7.${Reset}  ${Cyan}鬚�ｮｾ扈�粋${Reset} (荳髞ｮ螳芽｣?"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}譛榊苅邂｡逅�${Reset}"
        echo -e " ${Green}8.${Reset}  蜷ｯ蜉ｨ"
        echo -e " ${Green}9.${Reset}  蛛懈ｭ｢"
        echo -e " ${Green}10.${Reset} 驥榊星"
        echo -e " ${Green}11.${Reset} 譟･逵狗憾諤?
        echo -e " ${Green}12.${Reset} ${Yellow}譟･逵区律蠢�${Reset}"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}13.${Reset} 譟･逵玖鰍轤ｹ菫｡諱ｯ"
        echo -e " ${Green}14.${Reset} 譟･逵矩�鄂ｮ譁�ｻｶ"
        echo -e " ${Green}15.${Reset} ${Cyan}驟咲ｽｮ WARP 蜃ｺ遶�${Reset}"
        echo -e " ${Green}16.${Reset} 蜊ｸ霓ｽ sing-box"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  霑泌屓荳ｻ闖懷�?
        echo -e "${Green}========================================================${Reset}"
        
        read -p " 隸ｷ騾画叫 [0-16]: " choice
        
        case "$choice" in
            1) install_hysteria2 ;;
            2) install_tuic ;;
            3) install_vless_reality ;;
            4) install_anytls ;;
            5) install_any_reality ;;
            6) install_combo ;;
            7) install_preset_combo ;;
            8) start_singbox ;;
            9) stop_singbox ;;
            10) restart_singbox ;;
            11) status_singbox ;;
            12) view_logs ;;
            13) show_node_info ;;
            14) view_config ;;
            15)
                # 隹�畑 WARP 讓｡蝮礼噪蜃ｽ謨?
                local warp_manager="$VPSPLAY_DIR/modules/warp/manager.sh"
                if [ -f "$warp_manager" ]; then
                    source "$warp_manager"
                    configure_existing_warp_outbound
                else
                    echo -e "${Error} WARP 讓｡蝮玲悴謇ｾ蛻?
                fi
                ;;
            16) uninstall_singbox ;;
            0) return 0 ;;
            *) echo -e "${Error} 譌�謨磯画叫" ;;
        esac
        
        echo -e ""
        read -p "謖牙屓霓ｦ扈ｧ扈?.."
    done
}

# ==================== 荳ｻ遞句ｺ?====================
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    [ -z "$ENV_TYPE" ] && detect_environment 2>/dev/null
    detect_system
    show_singbox_menu
fi
