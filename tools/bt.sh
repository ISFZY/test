#!/bin/bash

# 基础配置
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"
CONFIG_FILE="/usr/local/etc/xray/config.json"

# 检查权限与依赖
if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi
if ! command -v jq &> /dev/null; then echo -e "${RED}错误: 未检测到 jq，请先安装 (apt install jq / yum install jq)。${PLAIN}"; exit 1; fi

# 首次运行清屏
clear

# 核心函数
get_status() {
    # 1. 检测 BT 封禁状态 (检测 block 标签且包含 bittorrent 协议)
    if jq -e '.routing.rules[] | select(.outboundTag=="block" and (.protocol | index("bittorrent")))' "$CONFIG_FILE" >/dev/null 2>&1; then
        STATUS_BT="${GREEN}已开启封禁 (Safe)${PLAIN}"
        IS_BT_BLOCKED=true
    else
        STATUS_BT="${YELLOW}未开启封禁 (Risk)${PLAIN}"
        IS_BT_BLOCKED=false
    fi

    # 2. 检测私有 IP 封禁状态 (检测 block 标签且包含 geoip:private)
    if jq -e '.routing.rules[] | select(.outboundTag=="block" and (.ip | index("geoip:private")))' "$CONFIG_FILE" >/dev/null 2>&1; then
        STATUS_PRIVATE="${GREEN}已开启封禁 (Safe)${PLAIN}"
        IS_PRIVATE_BLOCKED=true
    else
        STATUS_PRIVATE="${YELLOW}未开启封禁 (Risk)${PLAIN}"
        IS_PRIVATE_BLOCKED=false
    fi
}

apply_changes() {
    echo -e "\n${BLUE}[INFO] 正在重启 Xray 服务以应用规则...${PLAIN}"
    if systemctl restart xray; then
        echo -e "${GREEN}规则已生效！${PLAIN}"
    else
        echo -e "${RED}重启失败，请检查 Xray 配置文件。${PLAIN}"
    fi
    sleep 2
}

toggle_bt() {
    echo -e "\n${BLUE}正在切换 BT/P2P 拦截策略...${PLAIN}"
    
    if [ "$IS_BT_BLOCKED" = true ]; then
        # 动作：解除封禁
        jq 'del(.routing.rules[] | select(.outboundTag=="block" and (.protocol | index("bittorrent"))))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        echo -e "操作: ${RED}已解除 BT 限制${PLAIN}"
    else
        # 动作：开启封禁 (插入到规则头部)
        local new_rule='{"type": "field", "protocol": ["bittorrent"], "outboundTag": "block"}'
        jq --argjson rule "$new_rule" '.routing.rules = [$rule] + .routing.rules' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        echo -e "操作: ${GREEN}已添加 BT 限制${PLAIN}"
    fi
    
    apply_changes
}

toggle_private() {
    echo -e "\n${BLUE}正在切换私有 IP (局域网) 拦截策略...${PLAIN}"
    
    if [ "$IS_PRIVATE_BLOCKED" = true ]; then
        # 动作：解除封禁
        jq 'del(.routing.rules[] | select(.outboundTag=="block" and (.ip | index("geoip:private"))))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        echo -e "操作: ${RED}已解除内网限制${PLAIN}"
    else
        # 动作：开启封禁
        local new_rule='{"type": "field", "ip": ["geoip:private"], "outboundTag": "block"}'
        jq --argjson rule "$new_rule" '.routing.rules = [$rule] + .routing.rules' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        echo -e "操作: ${GREEN}已添加内网限制${PLAIN}"
    fi
    
    apply_changes
}

# =========================================================
# 主交互逻辑
# =========================================================

while true; do
    get_status
    
    # 无闪烁重绘
    tput cup 0 0
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}          流量拦截管理 (Traffic Blocker)          ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  BT / P2P 下载   : ${STATUS_BT}\033[K"
    echo -e "  私有 IP (局域网): ${STATUS_PRIVATE}\033[K"
    echo -e "---------------------------------------------------"
    echo -e "  1. 切换 ${YELLOW}BT 下载封禁${PLAIN}  (Toggle BT Block)"
    echo -e "  2. 切换 ${YELLOW}私有 IP 封禁${PLAIN} (Toggle Private IP)"
    echo -e "---------------------------------------------------"
    echo -e "  0. 退出 (Exit)"
    echo -e ""
    
    # 清除下方残留日志
    tput ed

    # 输入监听 (原地纠错)
    while true; do
        echo -ne "\r\033[K请输入选项 [0-2]: "
        read -n 1 -s -r choice
        case "$choice" in
            1|2|0) break ;;
            *) echo -ne "\r\033[K${RED}输入无效...${PLAIN}"; sleep 0.5 ;;
        esac
    done

    # 业务执行
    case "$choice" in
        1) toggle_bt ;;
        2) toggle_private ;;
        0) echo -e "\nbye."; exit 0 ;;
    esac
done
