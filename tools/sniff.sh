#!/bin/bash

# =========================================================
# 定义颜色
# =========================================================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

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
    local status=$(jq -r '.inbounds[0].sniffing.enabled // false' "$CONFIG_FILE")
    if [ "$status" == "true" ]; then
        echo -e "${GREEN}已开启 (Enabled)${PLAIN}"
    else
        echo -e "${RED}已关闭 (Disabled)${PLAIN}"
    fi
}

# 2. 获取日志状态
get_log_status() {
    local access_path=$(jq -r '.log.access // ""' "$CONFIG_FILE")
    if [[ "$access_path" != "" ]]; then
        echo -e "${GREEN}已开启${PLAIN}"
    else
        echo -e "${RED}未配置${PLAIN}"
    fi
}

# 3. 切换嗅探开关
toggle_sniffing() {
    local target_state=$1 # true or false
    
    echo -e "${BLUE}>>> 正在修改配置...${PLAIN}"
    
    # 备份防挂
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    
    tmp=$(mktemp)
    
    # 构造 jq 命令
    if [ "$target_state" == "true" ]; then
        jq '
          .inbounds |= map(
            if .protocol == "vless" then
              .sniffing = {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "routeOnly": true
              }
            else
              .
            end
          )
        ' "$CONFIG_FILE" > "$tmp"
    else
        jq '
          .inbounds |= map(
            if .protocol == "vless" then
              .sniffing.enabled = false
            else
              .
            end
          )
        ' "$CONFIG_FILE" > "$tmp"
    fi
    
    if [ -s "$tmp" ]; then
        mv "$tmp" "$CONFIG_FILE"
        
        # 权限：mktemp 默认为 600，必须改为 644 让 nobody 用户能读取
        chmod 644 "$CONFIG_FILE"
        
        echo -e "${BLUE}>>> 重启 Xray 服务...${PLAIN}"
        systemctl restart xray
        
        # 增加延时，确保 systemd 状态已更新
        sleep 1
        
        if systemctl is-active --quiet xray; then
            echo -e "${GREEN}设置成功！所有节点已同步更新。${PLAIN}"
            rm -f "${CONFIG_FILE}.bak"
        else
            echo -e "${RED}严重错误：Xray 重启失败！正在自动回滚...${PLAIN}"
            echo -e "${YELLOW}可能原因：配置文件格式错误或权限问题。${PLAIN}"
            
            # 回滚并修复权限
            mv "${CONFIG_FILE}.bak" "$CONFIG_FILE"
            chmod 644 "$CONFIG_FILE" 
            
            systemctl restart xray
            
            if systemctl is-active --quiet xray; then
                echo -e "${GREEN}已成功回滚到修改前的状态，服务已恢复。${PLAIN}"
            else
                echo -e "${RED}灾难性错误：回滚后服务依然无法启动！请手动检查日志：${PLAIN}"
                echo -e "journalctl -u xray -n 20 --no-pager"
            fi
        fi
    else
        echo -e "${RED}JSON 处理失败，未做任何修改。${PLAIN}"
        rm -f "$tmp"
    fi
}

# 4. 开启/关闭 访问日志
toggle_logging() {
    local action=$1
    echo -e "${BLUE}>>> 正在配置日志...${PLAIN}"
    
    tmp=$(mktemp)
    if [ "$action" == "on" ]; then
        mkdir -p /var/log/xray
        touch "$LOG_FILE"
        # 确保日志文件权限归属正确
        chown nobody:nogroup "$LOG_FILE" 2>/dev/null || chown nobody:nobody "$LOG_FILE" 2>/dev/null
        chmod 644 "$LOG_FILE"
        
        jq --arg path "$LOG_FILE" '.log.access = $path | .log.loglevel = "info"' "$CONFIG_FILE" > "$tmp"
    else
        jq 'del(.log.access) | .log.loglevel = "warning"' "$CONFIG_FILE" > "$tmp"
        echo "" > "$LOG_FILE"
    fi
    
    if [ -s "$tmp" ]; then
        mv "$tmp" "$CONFIG_FILE"
        # config.json 权限
        chmod 644 "$CONFIG_FILE"
        
        systemctl restart xray
        echo -e "${GREEN}日志配置已更新！${PLAIN}"
    else
         echo -e "${RED}JSON 处理失败。${PLAIN}"
    fi
}

# 5. 实时监视
watch_traffic() {
    local access_path=$(jq -r '.log.access // ""' "$CONFIG_FILE")
    if [[ "$access_path" == "" ]]; then
        echo -e "${YELLOW}提示：检测到未开启访问日志，正在自动开启...${PLAIN}"
        toggle_logging "on"
        sleep 1
    fi
    
    clear
    echo -e "${GREEN}=================================================${PLAIN}"
    echo -e "${GREEN}        实时流量审计 (Ctrl+C 退出)              ${PLAIN}"
    echo -e "${GREEN}=================================================${PLAIN}"
    echo -e "正在监听: ${YELLOW}$LOG_FILE${PLAIN}"
    
    # 实时输出
tail -f "$LOG_FILE" | awk '
BEGIN {
    # 1. 定义数据行的颜色变量
    c_end="\033[0m"
    c_time="\033[36m"; c_src="\033[33m"; c_route="\033[35m"; c_dest="\033[32m"; c_user="\033[37m"

    # 2. 定义统一的格式字符串
    # 注意：这里我们给每一列固定的宽度
    fmt = "%-17s %-20s %-25s %-60s %s\n"

    # 3. 打印纯文本表头 
    printf(fmt, "[时间]", "[来源IP]", "[路由路径]", "[目标地址]", "[用户]")
}

# 逻辑判断
$5 == "accepted" {
    time = substr($2, 1, 13)
    route = $7 $8 $9

    # 4. 打印数据行
    printf(fmt, \
        c_time time c_end, \
        c_src $4 c_end, \
        c_route route c_end, \
        c_dest $6 c_end, \
        c_user $11 c_end)
}'

}

# =========================================================
# 菜单
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
    echo -e "  5. ${YELLOW}进入实时流量审计模式 (Watch Log)${PLAIN}"
    echo -e "-------------------------------------------------"
    echo -e "  0. 退出"
    echo -e ""
    read -p "请输入选项 [0-5]: " choice
    
    case "$choice" in
        1) toggle_sniffing "true"; read -n 1 -s -r -p "按任意键继续..." ;;
        2) toggle_sniffing "false"; read -n 1 -s -r -p "按任意键继续..." ;;
        3) toggle_logging "on"; read -n 1 -s -r -p "按任意键继续..." ;;
        4) toggle_logging "off"; read -n 1 -s -r -p "按任意键继续..." ;;
        5) watch_traffic ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入无效${PLAIN}"; sleep 1 ;;
    esac
done
