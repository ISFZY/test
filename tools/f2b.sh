#!/bin/bash
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

JAIL_FILE="/etc/fail2ban/jail.local"

# 0. 启动即清屏
clear
if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi

# --- 核心辅助函数 ---

get_conf() {
    local key=$1
    # 提取 value
    grep "^${key}\s*=" "$JAIL_FILE" | awk -F'=' '{print $2}' | tr -d ' '
}

set_conf() {
    local key=$1; local val=$2
    if grep -q "^${key}\s*=" "$JAIL_FILE"; then
        sed -i "s/^${key}\s*=.*/${key} = ${val}/" "$JAIL_FILE"
    else
        sed -i "2i ${key} = ${val}" "$JAIL_FILE"
    fi
}

restart_f2b() {
    echo -e "${INFO} 正在重载配置..."
    systemctl restart fail2ban
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}配置已生效！${PLAIN}"
    else
        echo -e "${RED}Fail2ban 重启失败，请检查配置！${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

get_status() {
    if systemctl is-active fail2ban >/dev/null 2>&1; then
        local count=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | grep -o "[0-9]*")
        echo -e "${GREEN}运行中 (Active)${PLAIN} | 当前封禁: ${RED}${count:-0}${PLAIN} IP"
    else
        echo -e "${RED}已停止 (Stopped)${PLAIN}"
    fi
}

# --- 校验函数 ---
validate_time() {
    if [[ "$1" =~ ^[0-9]+[smhdw]?$ ]]; then return 0; else return 1; fi
}
validate_int() {
    if [[ "$1" =~ ^[0-9]+$ ]]; then return 0; else return 1; fi
}

# --- 功能模块 ---

change_param() {
    local name=$1; local key=$2; local type=$3
    local current=$(get_conf "$key")
    echo -e "\n${BLUE}正在修改: ${name}${PLAIN}"
    echo -e "当前值: ${GREEN}${current}${PLAIN}"
    
    while true; do
        read -p "请输入新值 (留空取消): " new_val
        if [ -z "$new_val" ]; then echo "取消修改。"; read -n 1 -s -r; return; fi
        if [ "$type" == "time" ]; then validate_time "$new_val" && break; fi
        if [ "$type" == "int" ]; then validate_int "$new_val" && break; fi
        echo -e "${RED}格式错误，请重试。${PLAIN}"
    done
    
    set_conf "$key" "$new_val"
    restart_f2b
}

toggle_service() {
    echo -e "\n${BLUE}--- 服务开关 ---${PLAIN}"
    if systemctl is-active fail2ban >/dev/null 2>&1; then
        read -p "是否停止并禁用 Fail2ban? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then systemctl stop fail2ban; systemctl disable fail2ban; echo -e "${RED}服务已停止。${PLAIN}"; fi
    else
        read -p "是否启用并启动 Fail2ban? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then systemctl enable fail2ban; systemctl start fail2ban; echo -e "${GREEN}服务已启动。${PLAIN}"; fi
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# 4. 手动解封 IP
unban_ip() {
    echo -e "\n${BLUE}--- 手动解封 IP (Unban Manager) ---${PLAIN}"
    
    # 1. 获取并处理列表
    local raw_list=$(fail2ban-client status sshd 2>/dev/null | grep "Banned IP list" | awk -F':' '{print $2}')
    IFS=' ' read -r -a ip_array <<< "$raw_list"
    
    # 2. 判空
    if [ ${#ip_array[@]} -eq 0 ]; then
        echo -e "${YELLOW}当前没有被封禁的 IP (列表为空)。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    # 3. 打印表头
    # %-8s  : ID 列占 8 个字符宽度，左对齐
    # %-20s : IP 列占 20 个字符宽度，左对齐
    echo -e "${GRAY}------------------------------${PLAIN}"
    printf "${YELLOW}%-8s %-20s${PLAIN}\n" "ID" "IP Address"
    echo -e "${GRAY}------------------------------${PLAIN}"

    # 4. 打印数据
    local i=1
    for ip in "${ip_array[@]}"; do
        # 必须使用和表头完全一致的宽度参数 (8 和 20)
        printf "${GREEN}%-8s${PLAIN} %-20s\n" "$i" "$ip"
        ((i++))
    done
    echo -e "${GRAY}------------------------------${PLAIN}"
    
    # 5. 交互
    echo -e "${YELLOW}提示：输入序号(ID) 快速解封，或直接输入 IP${PLAIN}"
    read -p "请输入 [ID/IP] (留空取消): " input
    
    if [ -z "$input" ]; then return; fi
    
    local target_ip=""
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        if [ "$input" -ge 1 ] && [ "$input" -le "${#ip_array[@]}" ]; then
            target_ip="${ip_array[$((input-1))]}"
        else
            echo -e "${RED}错误：ID $input 超出范围！${PLAIN}"
            read -n 1 -s -r -p "按任意键继续..."; return
        fi
    else
        target_ip="$input"
    fi
    
    echo -e "${INFO} 正在解封: ${GREEN}${target_ip}${PLAIN} ..."
    fail2ban-client set sshd unbanip "$target_ip"
    
    if [ $? -eq 0 ]; then echo -e "${OK} 解封成功！"; else echo -e "${ERR} 操作失败。"; fi
    
    read -n 1 -s -r -p "按任意键继续..."
}

# 5. 添加白名单
add_whitelist() {
    echo -e "\n${BLUE}--- 白名单管理 (Whitelist Manager) ---${PLAIN}"
    
    # 1. 获取列表
    local raw_list=$(grep "^ignoreip" "$JAIL_FILE" | awk -F'=' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
    IFS=' ' read -r -a ip_array <<< "$raw_list"
    
    # 2. 打印表头
    echo -e "${GRAY}-------------------------------------------${PLAIN}"
    printf "${YELLOW}%-6s %-25s %s${PLAIN}\n" "ID" "IP / Network" "Type"
    echo -e "${GRAY}-------------------------------------------${PLAIN}"
    
    if [ ${#ip_array[@]} -eq 0 ]; then
        echo -e "      (无数据 / None)"
    else
        local user_idx=1
        for ip in "${ip_array[@]}"; do
            # 智能识别系统回环地址
            # 匹配 127.x.x.x 或 ::1
            if [[ "$ip" =~ ^127\. ]] || [[ "$ip" == "::1" ]]; then
                # 系统内置 -> 显示红色的 #
                printf "${RED}%-6s${PLAIN} %-25s ${GRAY}[System]${PLAIN}\n" "#" "$ip"
            else
                # 用户添加 -> 显示绿色的数字
                printf "${GREEN}%-6s${PLAIN} %-25s ${BLUE}[User]${PLAIN}\n" "$user_idx" "$ip"
                ((user_idx++))
            fi
        done
    fi
    echo -e "${GRAY}-------------------------------------------${PLAIN}"
    
    # 3. 交互逻辑
    local current_ip=$(echo $SSH_CLIENT | awk '{print $1}')
    
    echo -e "${YELLOW}功能：添加新的 IP 到白名单${PLAIN}"
    read -p "请输入 IP (回车自动添加本机 ${current_ip}): " input_ip
    
    if [ -z "$input_ip" ]; then input_ip="$current_ip"; fi
    
    if [ -z "$input_ip" ]; then 
        echo -e "${RED}错误：无法获取有效 IP。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    
    # 查重
    for ip in "${ip_array[@]}"; do
        if [[ "$ip" == "$input_ip" ]]; then
            echo -e "${YELLOW}该 IP ($input_ip) 已存在。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
    done
    
    # 添加
    sed -i "/^ignoreip/ s/$/ ${input_ip}/" "$JAIL_FILE"
    restart_f2b
}

# 6. 查看日志
view_logs() {
    # 1. 定义临时文件路径
    local tmp_file="/tmp/f2b_view.tmp"
    local log_file="/var/log/fail2ban.log"
    
    if [ ! -f "$log_file" ]; then
        clear
        echo -e "${YELLOW}Log file not found ($log_file).${PLAIN}"
        read -n 1 -s -r -p "Press any key to return..."
        return
    fi

    echo -e "${BLUE}>>> 正在加载日志...${PLAIN}"

    # 2. 生成带提示的临时文件
    {
        # === 顶部表头 ===
        echo -e "${BLUE}=================================================================${PLAIN}"
        echo -e "${BLUE}           Fail2ban 封禁/解封日志 (Audit Log)                     ${PLAIN}"
        echo -e "${BLUE}=================================================================${PLAIN}"
        printf "${GRAY}%-20s %-12s %-16s %s${PLAIN}\n" "[Date / Time]" "[Jail]" "[IP Address]" "[Action]"
        echo -e "${GRAY}-----------------------------------------------------------------${PLAIN}"

        # === 中间日志内容 ===
        grep -E "(Ban|Unban)" "$log_file" 2>/dev/null | awk '{
            dt = $1 " " substr($2, 1, 8);
            jail = ""; action = ""; ip = "";
            for(i=3; i<=NF; i++) {
                if ($i ~ /^\[.*\]$/) jail = $i;
                if ($i == "Ban" || $i == "Unban") { 
                    action = $i; ip = $(i+1); break; 
                }
                if ($i == "Restore" && $(i+1) == "Ban") { 
                    action = "ResBan"; ip = $(i+2); break; 
                }
            }
            
            if (action == "Ban") act_str = "\033[31m" action "\033[0m";
            else if (action == "Unban") act_str = "\033[32m" action "\033[0m";
            else act_str = "\033[33m" action "\033[0m";

            if (jail != "" && ip != "") {
                printf "%-20s %-12s %-16s %s\n", dt, jail, ip, act_str
            }
        }'
        
        echo -e "${GRAY}-----------------------------------------------------------------${PLAIN}"
        echo -e "${YELLOW}>>> 日志结束 (按 'q' 退出, '/' 搜索, 'PgUp' 翻页) <<<${PLAIN}"
        
    } > "$tmp_file"

    # 3. 打开 (自动跳转到底部)
    less -R +G "$tmp_file"
    
    # 4. 清理
    rm -f "$tmp_file"
}

menu_exponential() {
    while true; do
        clear
        local inc=$(get_conf "bantime.increment")
        local fac=$(get_conf "bantime.factor")
        local max=$(get_conf "bantime.maxtime")
        [ "$inc" == "true" ] && S_INC="${GREEN}ON${PLAIN}" || S_INC="${RED}OFF${PLAIN}"

        echo -e "${BLUE}=== 指数封禁设置 ===${PLAIN}"
        echo -e "  1. 递增模式开关   [${S_INC}]"
        echo -e "  2. 修改增长系数   [${YELLOW}${fac}${PLAIN}]"
        echo -e "  3. 修改封禁上限   [${YELLOW}${max}${PLAIN}]"
        echo -e "---------------------------------"
        echo -e "  0. 返回"
        echo -e ""
        read -p "请选择: " sc
        case "$sc" in
            1) [ "$inc" == "true" ] && ns="false" || ns="true"; set_conf "bantime.increment" "$ns"; restart_f2b ;;
            2) change_param "增长系数" "bantime.factor" "int" ;;
            3) change_param "封禁上限" "bantime.maxtime" "time" ;;
            0) return ;;
        esac
    done
}

# --- 主循环 ---

while true; do
    clear
    VAL_MAX=$(get_conf "maxretry"); VAL_BAN=$(get_conf "bantime"); VAL_FIND=$(get_conf "findtime")
    
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}         Fail2ban 防火墙管理 (F2B Panel)          ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  状态: $(get_status)"
    echo -e "---------------------------------------------------"
    echo -e "  1. 修改 最大重试次数 [${YELLOW}${VAL_MAX}${PLAIN}]"
    echo -e "  2. 修改 初始封禁时长 [${YELLOW}${VAL_BAN}${PLAIN}]"
    echo -e "  3. 修改 监测时间窗口 [${YELLOW}${VAL_FIND}${PLAIN}]"
    echo -e "---------------------------------------------------"
    echo -e "  4. ${GREEN}手动解封 IP${PLAIN}  (Unban)"
    echo -e "  5. ${GREEN}添加白名单${PLAIN}   (Whitelist)"
    echo -e "  6. 查看封禁日志 (Logs)"
    echo -e "  7. ${YELLOW}指数封禁设置${PLAIN} (Advanced) ->"
    echo -e "---------------------------------------------------"
    echo -e "  8. 开启/停止 Fail2ban 服务 (On/Off)"
    echo -e "  0. 退出"
    echo -e ""
    read -p "请输入选项 [0-8]: " choice

    case "$choice" in
        1) change_param "最大重试次数" "maxretry" "int" ;;
        2) change_param "初始封禁时长" "bantime"  "time" ;;
        3) change_param "监测时间窗口" "findtime" "time" ;;
        4) unban_ip ;;
        5) add_whitelist ;;
        6) view_logs ;;
        7) menu_exponential ;;
        8) toggle_service ;;
        0) clear; exit 0 ;;
        *) ;;
    esac
done
