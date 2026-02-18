#!/bin/bash
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

CONFIG_FILE="/usr/local/etc/xray/config.json"

# 0. 权限与依赖检测
clear
if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi
if ! command -v jq &> /dev/null; then echo -e "${RED}错误: 缺少 jq 依赖。${PLAIN}"; exit 1; fi

# --- 核心函数 ---

get_current_sni() {
    if [ -f "$CONFIG_FILE" ]; then
        CURRENT_SNI=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // "获取失败"' "$CONFIG_FILE")
    else
        CURRENT_SNI="${RED}配置文件不存在${PLAIN}"
    fi
}

apply_sni() {
    local new_domain=$1
    echo -e "${BLUE}正在应用新域名: ${new_domain}...${PLAIN}"

    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

    # 批量修改 Vision 和 XHTTP 的 SNI 及 dest
    jq --arg d "$new_domain" '
        (.inbounds[].streamSettings.realitySettings | select(. != null)) |= 
        (.serverNames = [$d] | .dest = ($d + ":443"))
    ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

    echo -e "${INFO} 重启 Xray 服务..."
    if systemctl restart xray; then
        echo -e "${GREEN}修改成功！${PLAIN}"
        echo -e "新伪装域名: ${YELLOW}${new_domain}${PLAIN}"
        echo -e "注意：请务必同步修改客户端配置中的 SNI/ServerName，或执行'info'指令重新导入链接。"
    else
        echo -e "${RED}Xray 重启失败！正在还原配置...${PLAIN}"
        mv "${CONFIG_FILE}.bak" "$CONFIG_FILE"
        systemctl restart xray
        echo -e "${YELLOW}已还原旧配置。请检查新域名是否合法。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# --- manual_change 函数 ---
manual_change() {
    echo -e "\n${BLUE}--- 手动修改 SNI ---${PLAIN}"
    echo -e "请输入您想要使用的伪装域名 (例: www.example.com)"
    echo -e "输入 0 取消操作"
    echo -e "---------------------------------------------------"

    while true; do
        # 读取输入 (域名需要回车确认)
        read -p "域名: " input_domain

        # 0. 取消操作
        if [ "$input_domain" == "0" ]; then
            echo "操作已取消。"
            return
        fi

        # 1. 检查是否为空
        if [ -z "$input_domain" ]; then
            echo -e "\033[1A\033[K${RED}输入不能为空，请重新输入${PLAIN}"
            sleep 1
            echo -ne "\r\033[K"
            continue
        fi

        # 2. 正则验证域名格式 (允许字母数字、点、横杠，且必须包含至少一个点)
        # 简单正则：^[a-zA-Z0-9] 开头，中间包含点，结尾不能是横杠
        if [[ "$input_domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]; then
            # 格式正确，直接应用，不再 curl 验证
            echo -e "${OK} 格式验证通过。"
            apply_sni "$input_domain"
            break
        else
            # 错误处理：光标上移1行 -> 清除行 -> 显示红字 -> 暂停 -> 清除 -> 重绘输入框
            echo -e "\033[1A\033[K${RED}域名格式无效 (例: www.example.com)${PLAIN}"
            sleep 1
            # 回到行首并清除报错信息，循环开始时会重新打印 "域名: "
            echo -ne "\r\033[K"
        fi
    done
}

auto_select() {
    echo -e "\n${BLUE}--- 自动优选 SNI (寻找最低延迟) ---${PLAIN}"
    
    DOMAINS=("www.icloud.com" "www.apple.com" "itunes.apple.com" "learn.microsoft.com" "www.bing.com" "www.tesla.com" "www.nvidia.com" "www.intel.com" "www.amazon.com")
    
    TEMP_FILE=$(mktemp)
    echo -e "${INFO} 正在 Ping 检测..."

    tput civis
    for domain in "${DOMAINS[@]}"; do
        printf "\r   Ping: %-25s" "${domain}..."
        time_cost=$(curl -w "%{time_connect}" -o /dev/null -s --connect-timeout 2 "https://$domain")
        
        if [ -n "$time_cost" ] && [ "$time_cost" != "0.000" ]; then
            ms=$(awk -v t="$time_cost" 'BEGIN { printf "%.0f", t * 1000 }')
            echo "$ms $domain" >> "$TEMP_FILE"
        else
            echo "9999 $domain" >> "$TEMP_FILE"
        fi
    done
    tput cnorm
    echo -ne "\r\033[K"

    echo -e " 延迟排序清单:"
    echo -e "---------------------------------------------------"    
    SORTED_DOMAINS=()
    local idx=1
    
    while read ms domain; do
        if [ "$ms" == "9999" ]; then ms_show="超时"; else ms_show="${ms}ms"; fi
        
        SORTED_DOMAINS+=("$domain")
        
        if [ "$idx" -eq 1 ]; then
            printf "   ${GREEN}%d. %-25s %-6s [推荐]${PLAIN}\n" "$idx" "${domain}" "${ms_show}"
        else
            printf "   %d. %-25s %-6s\n" "$idx" "${domain}" "${ms_show}"
        fi
        ((idx++))
    done < <(sort -n "$TEMP_FILE")
    rm -f "$TEMP_FILE"

    echo -e "---------------------------------------------------"
    echo -e "   0. 取消 (Cancel)"
    echo -e ""
    
    local len=${#SORTED_DOMAINS[@]}
    
    while true; do
        read -n 1 -s -p "请输入序号选择 [0-${len}]: " sel_idx
        
        if [ "$sel_idx" == "0" ]; then
            echo "0" 
            echo "操作已取消。"
            return
        elif [[ "$sel_idx" =~ ^[1-9]$ ]] && [ "$sel_idx" -le "$len" ]; then
            echo "$sel_idx" 
            local target_domain="${SORTED_DOMAINS[$((sel_idx-1))]}"
            apply_sni "$target_domain"
            return
        else
            echo -ne "\r\033[K${RED}输入无效${PLAIN}"
            sleep 1
            echo -ne "\r\033[K"
        fi
    done
}

# --- 主菜单 ---
while true; do
    get_current_sni
    clear
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}          SNI 伪装域名管理 (Reality Config)       ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  当前伪装域名: ${YELLOW}${CURRENT_SNI}${PLAIN}"
    echo -e "---------------------------------------------------"
    echo -e "  1. 手动修改域名"
    echo -e "  2. 自动优选域名"
    echo -e "---------------------------------------------------"
    echo -e "  0. 退出"
    echo -e ""
    
    while true; do
        read -n 1 -s -p "请输入选项 [0-2]: " choice

        case "$choice" in
            1) manual_change; break ;; 
            2) auto_select; break ;;
            0) exit 0 ;;
            *) 
                echo -e "\r\033[K${RED}输入无效${PLAIN}"
                sleep 1
                echo -ne "\r\033[K"
                ;;
        esac
    done
done
