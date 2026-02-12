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
    # 必须以数字开头，结尾可以是空，或者是 s,m,h,d,w 中的一个
    if [[ "$1" =~ ^[0-9]+[smhdw]?$ ]]; then return 0; else return 1; fi
}

validate_float() {
    # 必须是纯数字或小数，不接受单位
    if [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then return 0; else return 1; fi
}

validate_int() {
    # 仅允许纯整数
    if [[ "$1" =~ ^[0-9]+$ ]]; then return 0; else return 1; fi
}

validate_ip_format() {
    local ip=$1
    # 1. IPv4 校验 (支持 CIDR，如 192.168.1.1/24)
    # 正则逻辑：(0-255).(0-255).(0-255).(0-255) 可选(/0-32)
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/([0-9]|[1-2][0-9]|3[0-2]))?$ ]]; then
        # 进一步检查每一段是否 <= 255
        IFS='./' read -r -a octets <<< "$ip"
        for octet in "${octets[@]:0:4}"; do
            if [[ "$octet" -gt 255 ]]; then return 1; fi
        done
        return 0
    fi

    # 2. IPv6 校验 (简单格式检查，包含 : 和 16进制字符)
    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}(/[0-9]{1,3})?$ ]]; then
        if [[ "$ip" =~ :: || "$ip" =~ : ]]; then return 0; fi
    fi

    # 都不匹配则失败
    return 1
}

# --- 功能模块 ---
change_param() {
    local name=$1; local key=$2; local type=$3; local hint=$4
    local current=$(get_conf "$key")
    
    # 1. 初始化显示
    clear
    echo -e "${BLUE}正在修改: ${name}${PLAIN}"
    echo -e "当前值: ${GREEN}${current}${PLAIN}"
    
    # 显示说明
    if [ ! -z "$hint" ]; then
        echo -e "${GRAY}说明: ${hint}${PLAIN}"
    fi
    echo -e "" 

    while true; do
        # 2. 获取输入
        read -p "请输入新值 (留空取消): " new_val
        
        # 3. 处理取消
        if [ -z "$new_val" ]; then 
            return 
        fi
        
        # 4. 类型校验与错误定义
        local check_pass=false
        local error_msg=""
        
        case "$type" in
            "time")
                if validate_time "$new_val"; then
                    check_pass=true
                else

                    error_msg="${RED}[错误] 格式无效 ('$new_val')。${PLAIN}\n${YELLOW}   - 必须是整数时间 (如 600)。\n   - 支持单位: s, m, h, d, w (秒,分,时,天,周)。${PLAIN}"
                fi
                ;;
            "float")
                if validate_float "$new_val"; then
                    check_pass=true
                else
                    error_msg="${RED}[错误] 格式无效 ('$new_val')。${PLAIN}\n${YELLOW}   - 必须是纯数字或小数 (如 1.5)。${PLAIN}"
                fi
                ;;
            "int")
                if validate_int "$new_val"; then
                    check_pass=true
                else
                    error_msg="${RED}[错误] 格式无效 ('$new_val')，仅支持纯整数。${PLAIN}"
                fi
                ;;
        esac
        
        # 5. 逻辑分支
        if [ "$check_pass" == "true" ]; then
            break 
        else
            # --- 核心交互 ---
            echo -ne "\033[1A\033[2K"
            
            # 3. 在被清除的位置打印报错信息
            echo -e "$error_msg"
            
            # 4. 循环继续，read 会在报错信息的下一行重新打印 "请输入新值..."
        fi
    done
    
    set_conf "$key" "$new_val"
    restart_f2b
}

toggle_service() {
    clear
    echo -e "\n${BLUE}--- 服务开关 (Service Switch) ---${PLAIN}"
    
    # 1. 判断当前状态
    local is_running=false
    if systemctl is-active fail2ban >/dev/null 2>&1; then
        is_running=true
        echo -e "当前状态: ${GREEN}运行中 (Active)${PLAIN}"
        echo -e "${YELLOW}警告: 停止服务将导致不再拦截恶意 IP。${PLAIN}"
    else
        echo -e "当前状态: ${RED}已停止 (Stopped)${PLAIN}"
    fi

    echo -e ""
    
    # 2. 动态提示文本
    local prompt_msg=""
    if [ "$is_running" == "true" ]; then
        prompt_msg="是否 **停止** 并禁用 Fail2ban? [y/n]: "
    else
        prompt_msg="是否 **启动** 并启用 Fail2ban? [y/n]: "
    fi

    # 3. 读取单字符输入
    read -n 1 -s -r -p "$prompt_msg" input
    
    # 4. 逻辑判断
    case "$input" in
        [yY])
            echo -e "${GREEN}YES${PLAIN}"
            echo -e "${INFO} 正在执行操作..."
            
            if [ "$is_running" == "true" ]; then
                # 执行停止
                systemctl stop fail2ban
                systemctl disable fail2ban
                echo -e "${RED}>>> 服务已停止。${PLAIN}"
            else
                # 执行启动
                systemctl enable fail2ban
                systemctl start fail2ban
                echo -e "${GREEN}>>> 服务已启动。${PLAIN}"
            fi
            ;;
            
        [nN])
            echo -e "${YELLOW}NO${PLAIN}"
            echo -e "${INFO} 操作已取消。"
            ;;
            
        *)
            # 捕获其他按键
            echo -e "" 
            echo -e "${RED}[错误] 输入无效，请输入 y 或 n。${PLAIN}"
            ;;
    esac

    read -n 1 -s -r -p "按任意键继续..."
}

# 4. IP 封禁/解封管理 (Ban/Unban Manager)
unban_ip() {
    local current_ip=$(echo $SSH_CLIENT | awk '{print $1}')

    # --- 外层循环：负责重绘界面 (Refresh Loop) ---
    while true; do
        clear
        echo -e "\n${BLUE}--- IP 封禁/解封管理 (Ban/Unban Manager) ---${PLAIN}"
        
        # 1. 获取列表
        local clean_list=$(fail2ban-client status sshd 2>/dev/null | grep "Banned IP list" | awk -F':' '{print $2}' | xargs)
        IFS=' ' read -r -a ip_array <<< "$clean_list"
        
        # 2. 打印表格
        echo -e "${GRAY}------------------------------------------${PLAIN}"
        printf "${YELLOW}%-4s %-20s${PLAIN}\n" "ID" "Banned IP Address"
        echo -e "${GRAY}------------------------------------------${PLAIN}"
        if [ ${#ip_array[@]} -eq 0 ]; then
            echo -e "      (当前无封禁 IP / None)"
        else
            local i=1
            for ip in "${ip_array[@]}"; do
                printf "${GREEN}%-4s${PLAIN} %-20s\n" "$i" "$ip"
                ((i++))
            done
        fi
        echo -e "${GRAY}------------------------------------------${PLAIN}"
        
        # 3. 提示区
        echo -e "${YELLOW}指令说明: ${PLAIN}"
        echo -e "  - ${RED}ban${PLAIN}   -> 封禁 IP"
        echo -e "  - ${GREEN}unban${PLAIN} -> 解封 IP"
        echo -e "  - ${GRAY}0${PLAIN}     -> 返回"
        echo -e "${GRAY}------------------------------------------${PLAIN}"
        
        # --- 内层循环：负责交互与原地纠错 (Interaction Loop) ---
        while true; do
            read -p "请输入指令: " raw_input
            local input=$(echo "$raw_input" | tr '[:upper:]' '[:lower:]' | xargs)

            # 处理空输入 (原地纠错)
            if [ -z "$input" ]; then
                echo -ne "\033[1A\033[2K" # 上移+清除
                continue
            fi

            case "$input" in
                0) return ;; # 退出函数
                
                "ban")
                    # --- 进入 BAN 子循环 ---
                    while true; do
                        echo -e ""
                        read -p "  > 请输入封禁IP (留空取消): " ban_target
                        
                        # 1. 取消操作
                        if [ -z "$ban_target" ]; then 
                            # 消除刚才的输入行和空行，回到主指令输入
                            echo -ne "\033[1A\033[2K\033[1A\033[2K" 
                            break 
                        fi

                        # 2. 格式校验 (原地报错)
                        if ! validate_ip_format "$ban_target"; then
                            echo -ne "\033[1A\033[2K\033[1A\033[2K"
                            echo -e "${RED}[错误] IP 格式无效: ${ban_target}${PLAIN}"
                            continue 
                        fi
                        
                        # 3. 自杀检测 (原地报错)
                        if [ "$ban_target" == "$current_ip" ]; then
                            echo -ne "\033[1A\033[2K\033[1A\033[2K"
                            echo -e "${RED}[警告] 禁止封禁本机 IP (${current_ip})！${PLAIN}"
                            continue
                        fi

                        # 4. 执行封禁
                        echo -e "${INFO} 正在封禁: ${RED}${ban_target}${PLAIN} ..."
                        local output=$(fail2ban-client set sshd banip "$ban_target")
                        
                        if [[ "$output" == "1" ]] || [[ "$output" == *"$ban_target"* ]]; then
                            echo -e "${GREEN}封禁成功！正在刷新列表...${PLAIN}"
                            sleep 0.5
                            break 2 # 跳出两层循环 -> 触发外层 clear 刷新列表
                        else
                            echo -e "${RED}失败: ${output}${PLAIN}"
                            sleep 1
                            break 2
                        fi
                    done
                    ;;

                "unban")
                    # --- 进入 UNBAN 子循环 ---
                    while true; do
                        echo -e ""
                        read -p "  > 请输入解封 IP 或 ID (留空取消): " unban_target
                        
                        if [ -z "$unban_target" ]; then 
                            echo -ne "\033[1A\033[2K\033[1A\033[2K"
                            break 
                        fi
                        
                        local target_ip=""
                        local is_valid=true
                        local err_msg=""

                        # ID/IP 识别
                        if [[ "$unban_target" =~ ^[0-9]+$ ]]; then
                            if [ "$unban_target" -ge 1 ] && [ "$unban_target" -le "${#ip_array[@]}" ]; then
                                target_ip="${ip_array[$((unban_target-1))]}"
                            else
                                is_valid=false
                                err_msg="序号 ${unban_target} 不存在"
                            fi
                        elif validate_ip_format "$unban_target"; then
                            target_ip="$unban_target"
                        else
                            is_valid=false
                            err_msg="格式无效"
                        fi

                        # 错误处理 (原地报错)
                        if [ "$is_valid" == "false" ]; then
                            echo -ne "\033[1A\033[2K\033[1A\033[2K"
                            echo -e "${RED}[错误] ${err_msg}。${PLAIN}"
                            continue
                        fi
                        
                        # 执行解封
                        echo -e "${INFO} 正在解封: ${GREEN}${target_ip}${PLAIN} ..."
                        local output=$(fail2ban-client set sshd unbanip "$target_ip")
                        
                        if [[ "$output" == *"$target_ip"* ]] || [[ "$output" == "1" ]]; then 
                            echo -e "${GREEN}解封成功！正在刷新列表...${PLAIN}"
                            sleep 0.5
                            break 2 # 刷新列表
                        else 
                            echo -e "${RED}Fail2ban 未找到该 IP。${PLAIN}"
                            sleep 1
                            break 2
                        fi
                    done
                    ;;
                
                *)
                    # --- 主指令错误 (原地纠错) ---
                    echo -ne "\033[1A\033[2K"
                    
                    # 3. 打印报错信息
                    echo -e "${RED}[错误] 无效指令: '${input}' (请输入 ban, unban 或 0)${PLAIN}"
                    
                    # 4. 循环继续，read 会在下一行重新打印 "请输入指令: "
                    ;;
            esac
        done
    done
}

# 5. 白名单管理 (Whitelist Manager)
add_whitelist() {
    local current_ip=$(echo $SSH_CLIENT | awk '{print $1}')

    # --- 外层循环：负责列表刷新 (Refresh Loop) ---
    while true; do
        clear
        echo -e "\n${BLUE}--- 白名单管理 (Whitelist Manager) ---${PLAIN}"
        
        # 1. 获取最新列表
        # 读取 ignoreip 配置，去除首尾空格
        local raw_list=$(grep "^ignoreip" "$JAIL_FILE" | awk -F'=' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        IFS=' ' read -r -a ip_array <<< "$raw_list"
        
        # 2. 打印表格
        echo -e "${GRAY}-------------------------------------------${PLAIN}"
        printf "${YELLOW}%-6s %-25s %s${PLAIN}\n" "ID" "IP / Network" "Type"
        echo -e "${GRAY}-------------------------------------------${PLAIN}"
        
        local user_ips=()
        if [ ${#ip_array[@]} -eq 0 ]; then
            echo -e "      (当前无白名单 / None)"
        else
            local display_idx=1
            for ip in "${ip_array[@]}"; do
                # 区分系统默认(127.0.0.1/::1) 和 用户添加
                if [[ "$ip" =~ ^127\. ]] || [[ "$ip" == "::1" ]]; then
                    printf "${RED}%-6s${PLAIN} %-25s ${GRAY}[System]${PLAIN}\n" "#" "$ip"
                else
                    printf "${GREEN}%-6s${PLAIN} %-25s ${BLUE}[User]${PLAIN}\n" "$display_idx" "$ip"
                    user_ips+=("$ip")
                    ((display_idx++))
                fi
            done
        fi
        echo -e "${GRAY}-------------------------------------------${PLAIN}"
        
        # 3. 提示区
        echo -e "${YELLOW}本机 IP: ${GREEN}${current_ip}${PLAIN}"
        echo -e "  - ${GREEN}添加${PLAIN}: 直接输入 IP (回车默认添加本机)"
        echo -e "  - ${RED}删除${PLAIN}: 输入 'd' + 序号 (如 ${RED}d1${PLAIN})"
        echo -e "  - ${GRAY}返回${PLAIN}: 输入 0"
        echo -e "${GRAY}-------------------------------------------${PLAIN}"
        
        # --- 内层循环：负责交互与原地纠错 (Interaction Loop) ---
        while true; do
            read -p "请输入指令: " input
            
            # A. 退出 (直接 return)
            if [ "$input" == "0" ]; then return; fi
            
            # B. 默认添加本机 (处理空输入)
            if [ -z "$input" ]; then 
                input="$current_ip"
                # 视觉上把空行替换为显式的 IP
                echo -ne "\033[1A\033[2K"
                echo -e "请输入指令: ${GREEN}${input} (自动填入)${PLAIN}"
            fi
            
            # C. 删除模式 (d + 数字)
            if [[ "$input" =~ ^[dD]([0-9]+)$ ]]; then
                local del_id=${BASH_REMATCH[1]}
                
                # 校验 ID 有效性
                if [ "$del_id" -lt 1 ] || [ "$del_id" -gt "${#user_ips[@]}" ]; then
                    # --- 原地报错 ---
                    echo -ne "\033[1A\033[2K"
                    echo -e "${RED}[错误] 序号 $del_id 不存在！${PLAIN}"
                    continue # 继续内层循环
                fi
                
                local target_ip="${user_ips[$((del_id-1))]}"
                echo -e "${INFO} 正在删除白名单: ${RED}${target_ip}${PLAIN}"
                
                # 重建列表逻辑
                local new_line="ignoreip ="
                for ip in "${ip_array[@]}"; do
                    if [ "$ip" != "$target_ip" ]; then
                        new_line="${new_line} ${ip}"
                    fi
                done
                
                # 写入文件
                sed -i "s|^ignoreip.*|${new_line}|" "$JAIL_FILE"
                
                restart_f2b
                break # 跳出内层循环 -> 触发外层刷新
            fi

            # D. 添加模式 (IP 格式校验)
            if ! validate_ip_format "$input"; then
                # --- 原地报错 ---
                echo -ne "\033[1A\033[2K"
                echo -e "${RED}[错误] IP 格式无效: '$input'${PLAIN}"
                continue # 继续内层循环
            fi

            # E. 查重逻辑
            local exists=false
            for ip in "${ip_array[@]}"; do
                if [[ "$ip" == "$input" ]]; then
                    # --- 原地提示 ---
                    echo -ne "\033[1A\033[2K"
                    echo -e "${YELLOW}[提示] IP ${input} 已存在。${PLAIN}"
                    exists=true; break
                fi
            done
            if [ "$exists" == "true" ]; then 
                continue # 继续内层循环
            fi
            
            # F. 执行添加
            echo -e "${INFO} 正在添加白名单: ${GREEN}${input}${PLAIN}"
            sed -i "/^ignoreip/ s/$/ ${input}/" "$JAIL_FILE"
            
            restart_f2b
            break # 跳出内层循环 -> 触发外层刷新
        done
    done
}

# 6. 查看日志
view_logs() {
    local log_file="/var/log/fail2ban.log"
    
    if [ ! -f "$log_file" ]; then
        clear
        echo -e "${YELLOW}Log file not found ($log_file).${PLAIN}"
        read -n 1 -s -r -p "Press any key to return..."
        return
    fi

    clear
    echo -e "${BLUE}=================================================================${PLAIN}"
    echo -e "${BLUE}           Fail2ban 管理日志 (最近 33 条)                          ${PLAIN}"
    echo -e "${BLUE}=================================================================${PLAIN}"
    
    printf "${GRAY}%-20s %-12s %-16s %s${PLAIN}\n" "[Date / Time]" "[Jail]" "[IP Address]" "[Action]"
    echo -e "${GRAY}-----------------------------------------------------------------${PLAIN}"

    # 1. grep --color=never: 防止 grep 自己加颜色
    # 2. sed: 强力去除日志文件里原本包含的 ANSI 颜色代码
    # 3. awk: 原始的稳定解析逻辑
    grep --color=never -E "(Ban|Unban)" "$log_file" 2>/dev/null | tail -n 33 | sed -r "s/\x1b\[[0-9;]*m//g" | awk '{
        # 提取日期时间 (前两个字段)
        dt = $1 " " substr($2, 1, 8);
        
        jail = ""; action = ""; ip = "";
        
        # 循环查找关键字段，适应不同日志格式
        for(i=3; i<=NF; i++) {
            # 找 Jail 名: [sshd]
            if ($i ~ /^\[.*\]$/) jail = $i;
            
            # 找动作: Ban 或 Unban
            if ($i == "Ban" || $i == "Unban") { 
                action = $i; ip = $(i+1); break; 
            }
            # 找特殊动作: Restore Ban
            if ($i == "Restore" && $(i+1) == "Ban") { 
                action = "ResBan"; ip = $(i+2); break; 
            }
        }
        
        # 颜色渲染
        if (action == "Ban") act_str = "\033[31m" action "\033[0m";
        else if (action == "Unban") act_str = "\033[32m" action "\033[0m";
        else act_str = "\033[33m" action "\033[0m";

        # 打印
        if (jail != "" && ip != "") {
            printf "%-20s %-12s %-16s %s\n", dt, jail, ip, act_str
        }
    }'
    
    echo -e "${GRAY}-----------------------------------------------------------------${PLAIN}"
    
    # 返回逻辑
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 7. 指数封禁 (Exponential Backoff)
menu_exponential() {
    while true; do
        # 1. 刷新配置数据显示
        #    每次循环重新获取，确保开关状态(ON/OFF)变更后立即刷新
        clear
        local inc=$(get_conf "bantime.increment")
        local fac=$(get_conf "bantime.factor")
        local max=$(get_conf "bantime.maxtime")
        
        local S_INC=""
        [ "$inc" == "true" ] && S_INC="${GREEN}ON${PLAIN}" || S_INC="${RED}OFF${PLAIN}"

        echo -e "${BLUE}=== 指数封禁设置 (Exponential Backoff) ===${PLAIN}"
        echo -e "  1. 递增模式开关   [${S_INC}]"
        echo -e "  2. 修改增长系数   [${YELLOW}${fac}${PLAIN}]"
        echo -e "  3. 修改封禁上限   [${YELLOW}${max}${PLAIN}]"
        echo -e "---------------------------------"
        echo -e "  0. 返回"
        echo -e ""
        
        # 2. 输入循环
        local choice=""
        while true; do

            read -n 1 -s -p "请选择 [0-3]: " choice
            
            # 正则校验：仅允许 0, 1, 2, 3
            if [[ "$choice" =~ ^[0-3]$ ]]; then
                echo "$choice" # 显式打印正确的输入，并换行
                break          # 跳出输入循环，去执行 case
            else
                # --- 错误处理逻辑 ---
                echo "$choice"
                
                echo -ne "\033[1A\033[2K"
                
                echo -e "${RED}[错误] 输入无效: '$choice'${PLAIN}"
                
            fi
        done
        
        # 3. 执行逻辑
        case "$choice" in
            1) 
                # 切换 true/false
                [ "$inc" == "true" ] && ns="false" || ns="true"
                set_conf "bantime.increment" "$ns"
                restart_f2b 
                ;;
            2) 
                change_param "增长系数 (Factor)" "bantime.factor" "float" \
                "封禁时间的增长倍率。\n      - 必须是纯数字，禁止加单位。\n      - 公式: 初始时长 * 系数^封禁次数"
                ;;
            3) 
                change_param "封禁上限 (MaxTime)" "bantime.maxtime" "time" \
                "封禁时长的最大值。\n      - 若不带单位，默认为秒 (s)。\n      - 支持单位: s, m, h, d, w。"
                ;;
            0) return ;; # 返回主菜单
        esac
    done
}

# --- 主循环 ---

while true; do
    # 1. 准备数据 & 绘制主菜单
    VAL_MAX=$(get_conf "maxretry"); VAL_BAN=$(get_conf "bantime"); VAL_FIND=$(get_conf "findtime")
    
    clear
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}         Fail2ban 防火墙管理 (F2B Panel)          ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  状态: $(get_status)"
    echo -e "---------------------------------------------------"
    echo -e "  1. 修改 最大重试次数 [${YELLOW}${VAL_MAX}${PLAIN}]"
    echo -e "  2. 修改 初始封禁时长 [${YELLOW}${VAL_BAN}${PLAIN}]"
    echo -e "  3. 修改 监测时间窗口 [${YELLOW}${VAL_FIND}${PLAIN}]"
    echo -e "---------------------------------------------------"
    echo -e "  4. ${GREEN}IP 封禁/解封管理${PLAIN}"
    echo -e "  5. ${GREEN}白名单管理${PLAIN}"
    echo -e "  6. 查看日志"
    echo -e "  7. ${YELLOW}指数封禁设置${PLAIN}"
    echo -e "---------------------------------------------------"
    echo -e "  8. ${GREEN}开启${PLAIN}/${GREEN}停止${PLAIN} Fail2ban 服务"
    echo -e "---------------------------------------------------"
    echo -e "  0. 退出"
    echo -e ""
    
    # 2. 智能输入循环
    while true; do
        # -n 1: 读取单个字符，无需回车
        # -s:   静默模式
        # -p:   提示文案
        read -n 1 -s -p "请输入选项 [0-8]: " choice
        
        # 校验是否为 0-8 的单数字
        if [[ "$choice" =~ ^[0-8]$ ]]; then
            # 输入正确 -> 显式打印出这个数字
            echo "$choice"
            break
        else
            # --- 核心逻辑：原地替换报错 ---
            
            # 1. 打印用户的错误输入
            echo "$choice"
            
            # 2. 光标上移一行 (\033[1A) 并 清除整行 (\033[2K)
            echo -ne "\033[1A\033[2K"
            
            # 3. 在被擦掉的这一行，打印红色的报错信息
            echo -e "${RED}[错误] 输入无效: '$choice'，请重新输入。${PLAIN}"
            
            # 4. 循环继续...
            #    read 命令会在下一行再次打印 "请输入选项 [0-8]: "
        fi
    done

    # 3. 功能执行
    case "$choice" in
        1) 
            change_param "最大重试次数 (MaxRetry)" "maxretry" "int" \
            "允许 IP 失败的最大次数。\n      - 超过此次数后 IP 将被封禁。\n      - 推荐值: 3 ~ 5 次。" 
            ;;
        2) 
            change_param "初始封禁时长 (BanTime)" "bantime"  "time" \
            "IP 被封禁的基础时长。\n      - 第一次被封禁持续的时间。\n      - 推荐: 10m (10分钟) 或 1h (1小时)。\n      - 若不带单位，默认为秒 (s)。" 
            ;;
        3) 
            change_param "监测时间窗口 (FindTime)" "findtime" "time" \
            "统计失败次数的时间范围。\n      - 在此时间内若累计失败次数达到上限，即触发封禁。\n      - 推荐: 10m (10分钟)。\n      - 若不带单位，默认为秒 (s)。" 
            ;;
        4) unban_ip ;;
        5) add_whitelist ;;
        6) view_logs ;;
        7) menu_exponential ;;
        8) toggle_service ;;
        0) clear; exit 0 ;;
    esac
done
