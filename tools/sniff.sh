#!/bin/bash

# =========================================================
# 定义颜色
# =========================================================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"
GRAY="\033[90m"

CONFIG_FILE="/usr/local/etc/xray/config.json"
LOG_FILE="/var/log/xray/access.log"

# 检查依赖
if ! command -v jq &> /dev/null; then echo -e "${RED}错误: 缺少 jq 组件。${PLAIN}"; exit 1; fi

# =========================================================
# 核心函数
# =========================================================

# 1. 获取嗅探状态
get_sniff_status() {
    if [ ! -f "$CONFIG_FILE" ]; then echo "Error"; return; fi
    
    # 读取 inbound[0] 的 sniffing.enabled 状态
    local status=$(jq -r '.inbounds[0].sniffing.enabled // false' "$CONFIG_FILE")
    
    if [ "$status" == "true" ]; then
        echo -e "${GREEN}已开启 (Enabled)${PLAIN}"
        IS_ENABLED=true
    else
        echo -e "${RED}已关闭 (Disabled)${PLAIN}"
        IS_ENABLED=false
    fi
}

# 2. 获取日志状态
get_log_status() {
    # 检查 log.loglevel 是否为 info 或 warning，且 access log 路径存在
    local log_level=$(jq -r '.log.loglevel // "none"' "$CONFIG_FILE")
    local access_path=$(jq -r '.log.access // ""' "$CONFIG_FILE")
    
    if [[ "$access_path" != "" ]]; then
        echo -e "${GREEN}已开启 (Level: $log_level)${PLAIN}"
        LOG_ENABLED=true
    else
        echo -e "${RED}未配置日志路径${PLAIN}"
        LOG_ENABLED=false
    fi
}

# 3. 切换嗅探开关
toggle_sniffing() {
    local target_state=$1 # true or false
    
    echo -e "${BLUE}>>> 正在修改配置...${PLAIN}"
    
    # 使用 jq 修改 sniffing 配置 (覆盖 http, tls, quic)
    tmp=$(mktemp)
    if [ "$target_state" == "true" ]; then
        jq '.inbounds[0].sniffing = {"enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true}' "$CONFIG_FILE" > "$tmp"
    else
        jq '.inbounds[0].sniffing.enabled = false' "$CONFIG_FILE" > "$tmp"
    fi
    
    mv "$tmp" "$CONFIG_FILE"
    
    echo -e "${BLUE}>>> 重启 Xray 服务...${PLAIN}"
    systemctl restart xray
    
    if systemctl is-active --quiet xray; then
        echo -e "${GREEN}设置成功！${PLAIN}"
    else
        echo -e "${RED}设置失败，Xray 重启异常！${PLAIN}"
    fi
}

# 4. 开启/关闭 访问日志
toggle_logging() {
    local action=$1 # on or off
    echo -e "${BLUE}>>> 正在配置日志...${PLAIN}"
    
    tmp=$(mktemp)
    if [ "$action" == "on" ]; then
        # 确保日志文件存在
        touch "$LOG_FILE"
        chown nobody:nogroup "$LOG_FILE" 2>/dev/null
        chmod 644 "$LOG_FILE"
        # 修改配置指向日志
        jq --arg path "$LOG_FILE" '.log.access = $path | .log.loglevel = "info"' "$CONFIG_FILE" > "$tmp"
    else
        # 移除日志配置
        jq 'del(.log.access) | .log.loglevel = "warning"' "$CONFIG_FILE" > "$tmp"
        # 可选：清空日志文件
        echo "" > "$LOG_FILE"
    fi
    mv "$tmp" "$CONFIG_FILE"
    systemctl restart xray
    echo -e "${GREEN}日志配置已更新！${PLAIN}"
}

# 5. 实时监视 (这才是真正的“嗅探”体验)
watch_traffic() {
    if [ "$LOG_ENABLED" != "true" ]; then
        echo -e "${YELLOW}提示：检测到未开启访问日志，正在自动开启...${PLAIN}"
        toggle_logging "on"
        sleep 1
    fi
    
    clear
    echo -e "${GREEN}=================================================${PLAIN}"
    echo -e "${GREEN}        实时流量审计 (Ctrl+C 退出)              ${PLAIN}"
    echo -e "${GREEN}=================================================${PLAIN}"
    echo -e "正在监听: ${YELLOW}$LOG_FILE${PLAIN}"
    echo -e "说明: 显示格式为 [时间] [来源IP] -> [目标域名/IP]"
    echo -e "-------------------------------------------------"
    
    # 使用 tail -f 实时输出，并用 grep/awk稍微美化一下（可选）
    # 这里直接输出原始日志，最原汁原味
    tail -f "$LOG_FILE"
}

# =========================================================
# 菜单逻辑
# =========================================================
while true; do
    clear
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${BLUE}           Xray 流量嗅探工具 (Traffic Sniff)     ${PLAIN}"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "  配置嗅探: $(get_sniff_status) ${GRAY}- 智能还原域名，优化路由${PLAIN}"
    echo -e "  日志记录: $(get_log_status)   ${GRAY}- 记录用户访问目标${PLAIN}"
    echo -e "-------------------------------------------------"
    echo -e "  1. 开启 流量嗅探 (Sniffing) ${GREEN}[推荐]${PLAIN}"
    echo -e "  2. 关闭 流量嗅探"
    echo -e "-------------------------------------------------"
    echo -e "  3. 开启 访问日志 (Access Log)"
    echo -e "  4. 关闭 访问日志"
    echo -e "-------------------------------------------------"
    echo -e "  5. ${YELLOW}>> 进入实时流量审计模式 (Watch Log)${PLAIN}"
    echo -e "-------------------------------------------------"
    echo -e "  0. 退出"
    echo -e ""
    read -p "请输入选项 [0-5]: " choice
    
    case "$choice" in
        1) toggle_sniffing "true" ;;
        2) toggle_sniffing "false" ;;
        3) toggle_logging "on" ;;
        4) toggle_logging "off" ;;
        5) watch_traffic ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入无效${PLAIN}"; sleep 1 ;;
    esac
done
