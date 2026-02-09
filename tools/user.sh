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

# 检查依赖
if ! command -v jq &> /dev/null; then echo -e "${RED}错误: 缺少 jq 组件。${PLAIN}"; exit 1; fi
if ! command -v xray &> /dev/null; then echo -e "${RED}错误: 缺少 xray 核心。${PLAIN}"; exit 1; fi

# =========================================================
# 核心逻辑
# =========================================================

# 1. 纯列表展示
_print_list() {
    echo -e "${BLUE}>>> 当前用户列表 (User List)${PLAIN}"
    echo -e "${GRAY}-----------------------------------------------------------------------${PLAIN}"
    printf "${YELLOW}%-4s %-25s %-40s${PLAIN}\n" "ID" "备注 (Email)" "UUID"
    echo -e "${GRAY}-----------------------------------------------------------------------${PLAIN}"
    
    jq -r '.inbounds[0].settings.clients[] | "\(.email // "无备注") \(.id)"' "$CONFIG_FILE" | nl -w 2 -s " " | while read idx email uuid; do
        if [[ "$email" == "admin" || "$email" == "Admin" ]]; then
            printf "${RED}%-4s %-25s %-40s${PLAIN}\n" "$idx" "$email" "$uuid"
        else
            printf "${GREEN}%-4s${PLAIN} %-25s %-40s\n" "$idx" "$email" "$uuid"
        fi
    done
    echo -e "${GRAY}-----------------------------------------------------------------------${PLAIN}"
}

# 2. 生成链接并显示 (支持 v4/v6 双栈)
_show_connection_info() {
    local uuid=$1
    local email=$2

    echo -e "\n${BLUE}>>> 正在获取网络连接信息 (IPv4 & IPv6)...${PLAIN}"
    
    # === 1. 独立检测 IP ===
    local ipv4=$(curl -s4m 1 https://ip.gs)
    local ipv6=$(curl -s6m 1 https://ip.gs)
    
    # 如果都获取失败，给个占位符
    if [ -z "$ipv4" ] && [ -z "$ipv6" ]; then ipv4="YOUR_IP"; fi

    # === 2. 遍历所有节点 ===
    local count=$(jq '.inbounds | length' "$CONFIG_FILE")

    for ((i=0; i<count; i++)); do
        local protocol=$(jq -r ".inbounds[$i].protocol" "$CONFIG_FILE")
        # 只处理 VLESS 协议
        if [ "$protocol" != "vless" ]; then continue; fi

        # 提取参数
        local tag=$(jq -r ".inbounds[$i].tag // \"node_$i\"" "$CONFIG_FILE")
        local port=$(jq -r ".inbounds[$i].port" "$CONFIG_FILE")
        local type=$(jq -r ".inbounds[$i].streamSettings.network" "$CONFIG_FILE")
        local sni=$(jq -r ".inbounds[$i].streamSettings.realitySettings.serverNames[0]" "$CONFIG_FILE")
        local priv_key=$(jq -r ".inbounds[$i].streamSettings.realitySettings.privateKey" "$CONFIG_FILE")
        local pbk=$(xray x25519 -i "$priv_key" | grep "Public" | awk '{print $3}')
        local sid=$(jq -r ".inbounds[$i].streamSettings.realitySettings.shortIds[0]" "$CONFIG_FILE")
        
        # 获取 flow
        local flow=$(jq -r ".inbounds[$i].settings.clients[] | select(.id==\"$uuid\") | .flow // \"\"" "$CONFIG_FILE")
        
        # XHTTP path
        local path=""
        if [ "$type" == "xhttp" ]; then
            path=$(jq -r ".inbounds[$i].streamSettings.xhttpSettings.path // \"\"" "$CONFIG_FILE")
        fi

        echo -e "${YELLOW}--- [节点: $tag ($type)] ---${PLAIN}"

        # === 3. 生成 IPv4 链接 ===
        if [ -n "$ipv4" ]; then
            local link4="vless://${uuid}@${ipv4}:${port}?security=reality&encryption=none&pbk=${pbk}&headerType=none&fp=chrome&type=${type}&flow=${flow}&sni=${sni}&sid=${sid}&path=${path}#${email}_v4"
            echo -e "${GREEN}[IPv4]${PLAIN} ${ipv4}:${port}"
            echo -e "链接: ${GRAY}${link4}${PLAIN}"
        fi

        # === 4. 生成 IPv6 链接 (注意 IP 必须加 []) ===
        if [ -n "$ipv6" ]; then
            # 分隔线
            if [ -n "$ipv4" ]; then echo -e "${GRAY}- - - - - - - - - - - - - - - - - - - -${PLAIN}"; fi
            
            local link6="vless://${uuid}@[${ipv6}]:${port}?security=reality&encryption=none&pbk=${pbk}&headerType=none&fp=chrome&type=${type}&flow=${flow}&sni=${sni}&sid=${sid}&path=${path}#${email}_v6"
            echo -e "${BLUE}[IPv6]${PLAIN} ${ipv6}:${port}"
            echo -e "链接: ${GRAY}${link6}${PLAIN}"
        fi
        echo ""
    done
}

# 3. 查看用户详情
view_user_details() {
    _print_list
    echo -e "${YELLOW}提示：输入序号可查看详细连接信息 (输入 0 或回车返回)${PLAIN}"
    read -p "请输入序号: " idx
    
    if [[ -z "$idx" || "$idx" == "0" ]]; then return; fi
    if ! [[ "$idx" =~ ^[0-9]+$ ]]; then echo -e "${RED}输入无效${PLAIN}"; return; fi
    
    local len=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE")
    if [ "$idx" -lt 1 ] || [ "$idx" -gt "$len" ]; then echo -e "${RED}序号超出范围${PLAIN}"; return; fi

    local array_idx=$((idx - 1))
    local email=$(jq -r ".inbounds[0].settings.clients[$array_idx].email // \"无备注\"" "$CONFIG_FILE")
    local uuid=$(jq -r ".inbounds[0].settings.clients[$array_idx].id" "$CONFIG_FILE")
    
    echo -e "${GREEN}>>> 已选择用户: $email${PLAIN}"
    _show_connection_info "$uuid" "$email"
    
    read -n 1 -s -r -p "按任意键返回菜单..."
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
    read -p "请输入用户备注 (例如: friend_bob): " email
    if [ -z "$email" ]; then echo -e "${RED}备注不能为空${PLAIN}"; return; fi
    
    if grep -q "$email" "$CONFIG_FILE"; then echo -e "${RED}错误: 该备注已存在！${PLAIN}"; return; fi
    
    local new_uuid=$(xray uuid)
    echo -e "正在添加: ${GREEN}$email${PLAIN} (UUID: $new_uuid)"
    
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
    
    _show_connection_info "$new_uuid" "$email"
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# 6. 删除用户
del_user() {
    _print_list
    echo -e "${YELLOW}请输入要删除的用户 序号 (不是备注):${PLAIN}"
    read -p "序号: " idx
    
    if ! [[ "$idx" =~ ^[0-9]+$ ]]; then echo -e "${RED}输入无效${PLAIN}"; return; fi
    if [ "$idx" -eq 1 ]; then echo -e "${RED}错误：禁止删除管理员账户 (Admin)！${PLAIN}"; return; fi
    
    local len=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE")
    if [ "$idx" -lt 1 ] || [ "$idx" -gt "$len" ]; then echo -e "${RED}序号超出范围${PLAIN}"; return; fi
    if [ "$len" -le 1 ]; then echo -e "${RED}错误: 至少保留一个用户，无法清空！${PLAIN}"; return; fi

    local array_idx=$((idx - 1))
    local email=$(jq -r ".inbounds[0].settings.clients[$array_idx].email // \"无备注\"" "$CONFIG_FILE")

    echo -ne "确认删除用户: ${RED}$email${PLAIN} ? [y/n]: "
    while true; do
        read -n 1 -r key
        case "$key" in
            [yY]) echo -e "\n${GREEN}>>> 已确认，正在删除...${PLAIN}"; break ;;
            [nN]) echo -e "\n${YELLOW}>>> 操作已取消。${PLAIN}"; return ;;
            *) ;;
        esac
    done

    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    tmp=$(mktemp)
    jq "del(.inbounds[].settings.clients[$array_idx])" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    
    restart_service "用户已删除。"
}

# =========================================================
# 菜单
# =========================================================
while true; do
    clear
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${BLUE}           Xray 多用户管理 (User Manager)        ${PLAIN}"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "  1. 查看列表 & 连接信息"
    echo -e "  2. ${GREEN}添加新用户 ${PLAIN}"
    echo -e "  3. ${RED}删除旧用户 ${PLAIN}"
    echo -e "-------------------------------------------------"
    echo -e "  0. 退出"
    echo -e ""
    read -p "请输入选项 [0-3]: " choice

    case "$choice" in
        1) view_user_details ;; 
        2) add_user ;;
        3) del_user ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入无效${PLAIN}"; sleep 1 ;;
    esac
done
