#!/bin/bash
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; PLAIN="\033[0m"

CONFIG_FILE="/usr/local/etc/xray/config.json"
SSH_CONFIG="/etc/ssh/sshd_config"
XRAY_BIN="/usr/local/bin/xray"

if ! command -v jq &> /dev/null; then echo -e "${RED}Error: 缺少 jq 依赖。${PLAIN}"; exit 1; fi

# --- 1. 基础信息提取 ---
SSH_PORT=$(grep "^Port" "$SSH_CONFIG" | head -n 1 | awk '{print $2}')
[ -z "$SSH_PORT" ] && SSH_PORT=22
HOST_NAME=$(hostname)

# 提取 Config
UUID=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_FILE")
PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE")
SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE")
SNI_HOST=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")
PORT_VISION=$(jq -r '.inbounds[] | select(.tag=="vision_node") | .port' "$CONFIG_FILE")
PORT_XHTTP=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .port' "$CONFIG_FILE")
XHTTP_PATH=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .streamSettings.xhttpSettings.path' "$CONFIG_FILE")

# 计算公钥
if [ -n "$PRIVATE_KEY" ] && [ -x "$XRAY_BIN" ]; then
    RAW_OUTPUT=$($XRAY_BIN x25519 -i "$PRIVATE_KEY")
    PUBLIC_KEY=$(echo "$RAW_OUTPUT" | grep -iE "Public|Password" | head -n 1 | awk -F':' '{print $2}' | tr -d ' \r\n')
fi
if [ -z "$PUBLIC_KEY" ]; then echo -e "${RED}严重错误：无法计算公钥！${PLAIN}"; exit 1; fi

# --- 2. IP 检测与链接生成 ---

IPV4=$(curl -s4m 1 https://api.ipify.org || echo "N/A")
IPV6=$(curl -s6m 1 https://api64.ipify.org || echo "N/A")

# 生成 IPv4 链接
LINK_V4_VIS=""
LINK_V4_XHT=""
if [[ "$IPV4" != "N/A" ]]; then
    LINK_V4_VIS="vless://${UUID}@${IPV4}:${PORT_VISION}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI_HOST}&sid=${SHORT_ID}#${HOST_NAME}_Vision_v4"
    LINK_V4_XHT="vless://${UUID}@${IPV4}:${PORT_XHTTP}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=xhttp&path=${XHTTP_PATH}&sni=${SNI_HOST}&sid=${SHORT_ID}#${HOST_NAME}_xhttp_v4"
fi

# 生成 IPv6 链接
LINK_V6_VIS=""
LINK_V6_XHT=""
if [[ "$IPV6" != "N/A" ]]; then
    LINK_V6_VIS="vless://${UUID}@[${IPV6}]:${PORT_VISION}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI_HOST}&sid=${SHORT_ID}#${HOST_NAME}_Vision_v6"
    LINK_V6_XHT="vless://${UUID}@[${IPV6}]:${PORT_XHTTP}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=xhttp&path=${XHTTP_PATH}&sni=${SNI_HOST}&sid=${SHORT_ID}#${HOST_NAME}_xhttp_v6"
fi

# --- 3. 界面展示 ---
clear

SEP="${BLUE}=================================================================${PLAIN}"

echo -e "${SEP}"
echo -e "${BLUE} Xray Configuration (Dynamic Info) ${PLAIN}"
echo -e "${SEP}"

printf " %-13s : ${RED}%s${PLAIN}\n"      "SSH Port"    "${SSH_PORT}"
printf " %-13s : ${GREEN}%s${PLAIN}\n"    "IPv4 IP"     "${IPV4}"
printf " %-13s : ${GREEN}%s${PLAIN}\n"    "IPv6 IP"     "${IPV6}"
printf " %-13s : ${YELLOW}%s${PLAIN}\n"   "SNI Host"    "${SNI_HOST}"
printf " %-13s : ${BLUE}%s${PLAIN}\n"     "UUID"        "${UUID}"
printf " %-13s : ${BLUE}%s${PLAIN}\n"     "Short ID"    "${SHORT_ID}"
printf " %-13s : ${YELLOW}%s${PLAIN} (Client)\n" "Public Key"  "${PUBLIC_KEY}"
printf " %-13s : ${RED}%s${PLAIN} (Server)\n"    "Private Key" "${PRIVATE_KEY}"

echo -e "${SEP}"

printf " %-13s : Port: ${GREEN}%-6s${PLAIN} Flow: ${GREEN}%-16s${PLAIN}\n" \
  "Vision" "${PORT_VISION}" "xtls-rprx-vision"

printf " %-13s : Port: ${GREEN}%-6s${PLAIN} Type: ${GREEN}%-16s${PLAIN} Path: ${GREEN}%s${PLAIN}\n" \
  "xhttp" "${PORT_XHTTP}" "xhttp" "${XHTTP_PATH}"

echo -e "${SEP}"

# 节点
if [[ -n "$LINK_V4_VIS" ]]; then
    echo -e "${GREEN}>> IPv4 节点 (通用):${PLAIN}"
    echo -e "${YELLOW}Vision:${PLAIN} ${LINK_V4_VIS}"
    echo -e "${YELLOW}XHTTP :${PLAIN} ${LINK_V4_XHT}"
    echo ""
fi

if [[ -n "$LINK_V6_VIS" ]]; then
    echo -e "${GREEN}>> IPv6 节点 (专用):${PLAIN}"
    echo -e "${YELLOW}Vision:${PLAIN} ${LINK_V6_VIS}"
    echo -e "${YELLOW}XHTTP :${PLAIN} ${LINK_V6_XHT}"
    echo ""
fi

# 二维码
read -n 1 -p "是否生成二维码? (y/n): " CHOICE
echo ""
if [[ "$CHOICE" =~ ^[yY]$ ]]; then
    if [[ -n "$LINK_V4_VIS" ]]; then
        echo -e "\n${BLUE}--- IPv4 Vision ---${PLAIN}"
        qrencode -t ANSIUTF8 "${LINK_V4_VIS}"
        echo -e "\n${BLUE}--- IPv4 XHTTP ---${PLAIN}"
        qrencode -t ANSIUTF8 "${LINK_V4_XHT}"
    fi

    # 防止刷屏，IPv6 二维码依然需要二次确认
    if [[ -n "$LINK_V6_VIS" ]]; then
        echo ""
        read -n 1 -p "是否继续生成 IPv6 二维码? (y/n): " CHOICE_V6
        echo ""
        if [[ "$CHOICE_V6" =~ ^[yY]$ ]]; then
            echo -e "\n${BLUE}--- IPv6 Vision ---${PLAIN}"
            qrencode -t ANSIUTF8 "${LINK_V6_VIS}"
            echo -e "\n${BLUE}--- IPv6 XHTTP ---${PLAIN}"
            qrencode -t ANSIUTF8 "${LINK_V6_XHT}"
        fi
    fi
fi

echo -e "\n-----------------------------------------------------------------------------------------------------------------"
echo -e " ${BLUE}管理命令:${PLAIN}"
echo -e " ${YELLOW}info${PLAIN} (管理员信息) | ${YELLOW}net${PLAIN} (网络) | ${YELLOW}xw${PLAIN} (WARP分流) | ${YELLOW}swap${PLAIN}  (内存) | ${YELLOW}backup${PLAIN} (备份) | ${YELLOW}f2b${PLAIN} (防火墙) | ${YELLOW}sniff${PLAIN}  (流量嗅探)"
echo -e " ${YELLOW}user${PLAIN} (多用户管理) | ${YELLOW}sni${PLAIN} (域名) | ${YELLOW}bt${PLAIN} (BT封禁)   | ${YELLOW}ports${PLAIN} (端口) | ${YELLOW}zone${PLAIN}   (时区) | ${YELLOW}bbr${PLAIN} (内核)   | ${YELLOW}remove${PLAIN} (卸载)"
echo -e "-----------------------------------------------------------------------------------------------------------------"
echo ""
