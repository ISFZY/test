#!/bin/bash

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"
GRAY="\033[90m"

CONFIG_FILE="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"

# 检查依赖
if ! command -v jq &> /dev/null; then echo -e "${RED}Error: 缺少 jq 组件。${PLAIN}"; exit 1; fi
if ! [ -x "$XRAY_BIN" ]; then echo -e "${RED}Error: 缺少 xray 核心。${PLAIN}"; exit 1; fi

# 核心逻辑
# 1. 列表展示 (Admin 显示为 #, 用户从 1 开始)
_print_list() {
    echo -e "${BLUE}>>> 当前用户列表 (User List)${PLAIN}"
    echo -e "${GRAY}------------------------------------------------------------------${PLAIN}"
    printf "${YELLOW}%-5s %-25s %-40s${PLAIN}\n" "ID" "备注" "UUID"
    echo -e "${GRAY}------------------------------------------------------------------${PLAIN}"
    
    # 使用 jq to_entries 获取真实索引 (key=0,1,2...)
    jq -r '.inbounds[0].settings.clients | to_entries[] | "\(.key) \(.value.email // "无备注") \(.value.id)"' "$CONFIG_FILE" | while read idx email uuid; do
        if [ "$idx" -eq 0 ]; then
            # 索引 0 (管理员) -> 显示为红色的 #
            printf "${RED}%-5s %-23s %-40s${PLAIN}\n" "#" "$email" "$uuid"
        else
            # 其他索引 -> 直接显示数字 (如 1, 2, 3...)
            printf "${GREEN}%-5s${PLAIN} %-23s %-40s\n" "$idx" "$email" "$uuid"
        fi
    done
    echo -e "${GRAY}------------------------------------------------------------------${PLAIN}"
}

# 2. 生成链接并显示 (复用 info.sh 逻辑)
_show_connection_info() {
    local target_uuid=$1
    local target_email=$2

    echo -e "\n${BLUE}>>> 正在获取连接信息...${PLAIN}"

    # --- 1. 提取基础配置 (与 info.sh 保持一致) ---
    # 提取密钥与 SNI (通常在第一个 inbound)
    local PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE")
    local SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE")
    local SNI_HOST=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")
    
    # 按 tag 提取端口和路径 (确保精准)
    local PORT_VISION=$(jq -r '.inbounds[] | select(.tag=="vision_node") | .port' "$CONFIG_FILE")
    local PORT_XHTTP=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .port' "$CONFIG_FILE")
    local XHTTP_PATH=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .streamSettings.xhttpSettings.path' "$CONFIG_FILE")

    # 计算公钥
    local PUBLIC_KEY=""
    if [ -n "$PRIVATE_KEY" ]; then
        local RAW_OUTPUT=$($XRAY_BIN x25519 -i "$PRIVATE_KEY")
        # 兼容不同版本的 grep 输出
        PUBLIC_KEY=$(echo "$RAW_OUTPUT" | grep -iE "Public|Password" | head -n 1 | awk -F':' '{print $2}' | tr -d ' \r\n')
    fi
    
    if [ -z "$PUBLIC_KEY" ]; then 
        echo -e "${RED}严重错误：无法计算公钥，请检查 config.json。${PLAIN}"
        return
    fi

    # --- 2. IP 检测 ---
    local IPV4=$(curl -s4m 1 https://api.ipify.org || echo "N/A")
    local IPV6=$(curl -s6m 1 https://api64.ipify.org || echo "N/A")

    # --- 3. 生成并输出链接 ---
    echo -e "\n${YELLOW}=== 用户 [${target_email}] 连接配置 ===${PLAIN}"

    # >> IPv4 Links
    if [[ "$IPV4" != "N/A" ]]; then
        echo -e "${GREEN}>> IPv4 节点 (通用):${PLAIN}"
        
        # Vision Link
        if [ -n "$PORT_VISION" ]; then
            local link="vless://${target_uuid}@${IPV4}:${PORT_VISION}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI_HOST}&sid=${SHORT_ID}#${target_email}_Vision"
            echo -e "${YELLOW}Vision:${PLAIN} ${GRAY}${link}${PLAIN}"
        fi
        
        # XHTTP Link
        if [ -n "$PORT_XHTTP" ]; then
            local link="vless://${target_uuid}@${IPV4}:${PORT_XHTTP}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=xhttp&path=${XHTTP_PATH}&sni=${SNI_HOST}&sid=${SHORT_ID}#${target_email}_XHTTP"
            echo -e "${YELLOW}XHTTP :${PLAIN} ${GRAY}${link}${PLAIN}"
        fi
        echo ""
    fi

    # >> IPv6 Links
    if [[ "$IPV6" != "N/A" ]]; then
        echo -e "${GREEN}>> IPv6 节点 (专用):${PLAIN}"
        
        # Vision Link
        if [ -n "$PORT_VISION" ]; then
            local link="vless://${target_uuid}@[${IPV6}]:${PORT_VISION}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI_HOST}&sid=${SHORT_ID}#${target_email}_Vision_v6"
            echo -e "${YELLOW}Vision:${PLAIN} ${GRAY}${link}${PLAIN}"
        fi
        
        # XHTTP Link
        if [ -n "$PORT_XHTTP" ]; then
            local link="vless://${target_uuid}@[${IPV6}]:${PORT_XHTTP}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=xhttp&path=${XHTTP_PATH}&sni=${SNI_HOST}&sid=${SHORT_ID}#${target_email}_XHTTP_v6"
            echo -e "${YELLOW}XHTTP :${PLAIN} ${GRAY}${link}${PLAIN}"
        fi
        echo ""
    fi
}

# 3. 查看用户详情
view_user_details() {
    _print_list
    echo -e "${YELLOW}提示: 输入序号 (ID) 查看详细连接信息${PLAIN} ${GREEN}[回车 或 0 返回]${PLAIN}"

    # 获取用户总数用于校验
    local len=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE")

    while true; do
        # 每次循环都在下方生成新的输入框
        read -p "序号 (ID): " idx

        # --- 1. 退出逻辑 (回车或0) ---
        if [[ -z "$idx" || "$idx" == "0" ]]; then
            return # 只有这里会跳出函数，返回主菜单
        fi

        # --- 2. 格式错误 (非数字) ---
        if ! [[ "$idx" =~ ^[0-9]+$ ]]; then
            # 上移一行并清除，原地替换为报错
            echo -e "\033[1A\033[K${RED}输入无效: \"$idx\" 不是数字，请重新输入${PLAIN}"
            continue
        fi

        # --- 3. 范围错误 (ID不存在) ---
        if [ "$idx" -lt 1 ] || [ "$idx" -ge "$len" ]; then
            # 上移一行并清除，原地替换为报错
            echo -e "\033[1A\033[K${RED}序号不存在: \"$idx\" (有效范围: 1-$((len-1)))${PLAIN}"
            continue
        fi

        # --- 4. 成功获取逻辑 ---
        # 上移一行并清除输入行，替换为绿色的标题
        echo -e "\033[1A\033[K${GREEN}>>> 用户 [${idx}] 详细连接信息:${PLAIN}"
        
        local array_idx=$idx
        local email=$(jq -r ".inbounds[0].settings.clients[$array_idx].email // \"无备注\"" "$CONFIG_FILE")
        local uuid=$(jq -r ".inbounds[0].settings.clients[$array_idx].id" "$CONFIG_FILE")

        # 显示具体信息
        _show_connection_info "$uuid" "$email"
        
        # 打印一条分隔线，区分多次查询记录
        echo -e "${BLUE}------------------------------------------------${PLAIN}"

        # 脚本会自动回到 loop 开头，在下方再次显示 "序号 (ID): " 供用户继续查询
    done
}

# 4. 重启服务与自动回滚
restart_service() {
    local success_msg=$1
    local backup_file="${CONFIG_FILE}.bak"

    chmod 644 "$CONFIG_FILE"
    echo -e "${BLUE}>>> 正在重启服务...${PLAIN}"
    systemctl restart xray
    sleep 2
    
    if systemctl is-active --quiet xray; then
        echo -e "${GREEN}${success_msg}${PLAIN}"
        rm -f "$backup_file"
    else
        echo -e "${RED}严重错误：Xray 服务启动失败！正在尝试回滚...${PLAIN}"
        journalctl -u xray --no-pager -n 10 | tail -n 5
        if [ -f "$backup_file" ]; then
            echo -e "${YELLOW}>>> 正在触发自动回滚机制...${PLAIN}"
            cp "$backup_file" "$CONFIG_FILE"
            chmod 644 "$CONFIG_FILE"
            systemctl restart xray
            if systemctl is-active --quiet xray; then
                echo -e "${GREEN}回滚成功！${PLAIN}"
                rm -f "$backup_file"
            else
                echo -e "${RED}灾难性错误：回滚后服务依然无法启动！${PLAIN}"
            fi
        else
            echo -e "${RED}未找到备份文件！${PLAIN}"
        fi
    fi
}

# 5. 添加用户
add_user() {
    echo -e "${BLUE}>>> 添加新用户${PLAIN}"
    echo -e "${YELLOW}提示: 请输入新用户的备注名 (Alias)${PLAIN} ${GREEN}[回车 或 0 返回]${PLAIN}"

    # --- 外层循环：连续添加 (Loop 1) ---
    while true; do
        local email=""
        
        # --- 内层循环：输入验证 (Loop 2) ---
        while true; do
            read -p "请输入用户备注 (例如: friend_bob): " email

            # 1. 退出逻辑 (回车 或 0)
            if [[ -z "$email" || "$email" == "0" ]]; then
                return # 只有这里会真正退出函数，返回主菜单
            fi

            # 2. 检查是否重复
            if grep -q "\"email\": \"$email\"" "$CONFIG_FILE"; then
                # 原地报错并重新输入
                echo -e "\033[1A\033[K${RED}错误: 备注 \"$email\" 已存在，请换一个名字${PLAIN}"
                continue
            fi

            # 3. 输入有效
            # 原地替换为绿色状态提示，跳出内层验证循环，去执行添加
            echo -e "\033[1A\033[K${GREEN}正在添加用户: ${email} ... (生成 UUID 中)${PLAIN}"
            break 
        done

        # --- 执行添加逻辑 ---
        local new_uuid=$(xray uuid)
        cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

        tmp=$(mktemp)
        jq --arg uuid "$new_uuid" --arg email "$email" '
            .inbounds |= map(
                if .settings.clients then
                    .settings.clients += [{
                        "id": $uuid,
                        "email": $email,
                        "flow": (.settings.clients[0].flow // "")
                    }]
                else
                    .
                end
            )' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"

        restart_service "添加成功！"

        # 显示新用户的连接信息
        _show_connection_info "$new_uuid" "$email"

        # 显示完信息后，不按键暂停，直接打印分隔线并进入下一次外层循环
        echo -e "${BLUE}------------------------------------------------${PLAIN}"
        
        # 脚本会自动回到 Loop 1 开头，再次显示 "请输入用户备注..."
    done
}

# 6. 删除用户
del_user() {
    # --- 首次进入函数时打印列表 ---
    _print_list
    
    while true; do
        # 1. 每次循环重新获取长度
        local len=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE")
        
        # 如果只剩 Admin (index 0)，提示并退出
        if [ "$len" -le 1 ]; then
             echo -e "\n${YELLOW}提示：当前已无普通用户可删除。${PLAIN}"
             read -n 1 -s -r -p "按任意键返回菜单..."
             return
        fi

        echo -e "${YELLOW}提示：请输入要删除的用户序号(ID)${PLAIN} ${GREEN}[回车 或 0 返回]${PLAIN}"
        
        local idx=""
        
        # --- 内层循环：ID 输入验证 ---
        while true; do
            read -p "序号(ID): " idx
            
            if [[ -z "$idx" || "$idx" == "0" ]]; then return; fi

            local error_msg=""
            if ! [[ "$idx" =~ ^[0-9]+$ ]]; then 
                error_msg="输入无效，请输入数字！"
            elif [ "$idx" -lt 1 ] || [ "$idx" -ge "$len" ]; then
                local max_id=$((len - 1))
                error_msg="序号不存在 (有效范围: 1-${max_id})！"
            fi

            if [ -n "$error_msg" ]; then
                echo -e "\033[1A\033[K${RED}${error_msg}${PLAIN}"
                continue 
            fi
            break 
        done

        # --- 获取用户信息 ---
        local array_idx=$idx
        local email=$(jq -r ".inbounds[0].settings.clients[$array_idx].email // \"无备注\"" "$CONFIG_FILE")

        # --- 确认删除 ---
        echo -e "\033[1A\033[K确认删除用户: ${RED}$email${PLAIN} ? [y/n]: "
        read -n 1 -r key
        echo ""

        case "$key" in
            [yY])
                echo -e "\033[1A\033[K${GREEN}>>> 正在删除用户: $email ...${PLAIN}"
                
                cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
                tmp=$(mktemp)
                jq "del(.inbounds[].settings.clients[$array_idx])" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                
                restart_service "用户 $email 已删除。"
                
                # 删除成功后刷新列表
                # 1. 等待一下看清提示
                sleep 1 
                # 2. 清屏
                clear
                # 3. 重新打印最新的列表
                _print_list
                # 4. 循环继续，脚本会再次显示 "请输入要删除的序号..."
                ;;
            [nN])
                echo -e "\033[1A\033[K${YELLOW}>>> 操作已取消。${PLAIN}"
                echo -e "${BLUE}------------------------------------------------${PLAIN}"
                ;;
            *)
                echo -e "\033[1A\033[K${RED}>>> 输入无效，取消操作。${PLAIN}"
                echo -e "${BLUE}------------------------------------------------${PLAIN}"
                ;;
        esac
    done
}

# 菜单
while true; do
    clear
    # --- 菜单显示部分 ---
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "${BLUE}             Xray 多用户管理 (User Manager)     ${PLAIN}"
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e " 1. 查看列表 & 连接信息"
    echo -e " 2. ${GREEN}添加新用户${PLAIN}"
    echo -e " 3. ${RED}删除旧用户${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e " 0. 退出"
    echo -e ""

    # --- 验证循环 ---
    while true; do
        # 移除 -n 1 和 echo ""，要求用户必须按回车确认，解决缓冲区残留问题
        read -p "请输入选项 [0-3]: " choice

        # 验证输入
        if [[ "$choice" =~ ^[0-3]$ ]]; then
            break # 输入正确，跳出循环
        else
            # 输入错误处理：光标上移一行并清除，不留残影
            echo -e "\033[1A\033[K${RED}输入无效: \"$choice\" 不是有效选项，请重新输入${PLAIN}"
        fi
    done

    # --- 执行逻辑 ---
    case "$choice" in
        1) view_user_details ;;
        2) add_user ;;
        3) del_user ;;
        0) exit 0 ;;
    esac
done
