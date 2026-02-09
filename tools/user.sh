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

# 检查依赖
if ! command -v jq &> /dev/null; then echo -e "${RED}错误: 缺少 jq 组件。${PLAIN}"; exit 1; fi
if ! command -v xray &> /dev/null; then echo -e "${RED}错误: 缺少 xray 核心。${PLAIN}"; exit 1; fi

# =========================================================
# 核心逻辑
# =========================================================

# 1. 列出所有用户
list_users() {
    echo -e "${BLUE}>>> 当前用户列表 (User List)${PLAIN}"
    echo -e "----------------------------------------------------------------"
    printf "%-5s %-20s %-40s\n" "ID" "备注 (Email)" "UUID"
    echo -e "----------------------------------------------------------------"
    
    # 使用 jq 解析并格式化输出
    # 格式: 索引 | email | id
    jq -r '.inbounds[0].settings.clients[] | "\(.email) \(.id)"' "$CONFIG_FILE" | nl -w 2 -s " " | while read idx email uuid; do
        printf "%-5s %-20s %-40s\n" "$idx" "$email" "$uuid"
    done
    echo -e "----------------------------------------------------------------"
}

# 4. 重启服务与自动回滚 (辅助函数，放在前面以供调用)
restart_service() {
    local success_msg=$1
    # 定义临时备份文件的位置
    local backup_file="${CONFIG_FILE}.bak"

    # 尝试重启
    systemctl restart xray
    
    # 检查状态
    if systemctl is-active --quiet xray; then
        # === 成功情况 ===
        echo -e "${GREEN}${success_msg}${PLAIN}"
        # 确认服务正常后，删除临时备份
        rm -f "$backup_file"
    else
        # === 失败情况 (触发回滚) ===
        echo -e "${RED}严重错误：Xray 服务启动失败！配置文件可能存在语法错误。${PLAIN}"
        
        if [ -f "$backup_file" ]; then
            echo -e "${YELLOW}>>> 正在触发自动回滚机制 (Auto Rollback)...${PLAIN}"
            
            # 1. 还原配置
            cp "$backup_file" "$CONFIG_FILE"
            
            # 2. 再次尝试重启
            systemctl restart xray
            
            if systemctl is-active --quiet xray; then
                echo -e "${GREEN}回滚成功！系统已自动恢复到修改前的状态。${PLAIN}"
                echo -e "${GRAY}本次修改未生效，请检查输入内容。${PLAIN}"
                # 删除备份
                rm -f "$backup_file"
            else
                echo -e "${RED}灾难性错误：回滚后服务依然无法启动！${PLAIN}"
                echo -e "${RED}请手动检查配置文件: $CONFIG_FILE${PLAIN}"
            fi
        else
            echo -e "${RED}未找到备份文件，无法执行回滚！${PLAIN}"
        fi
    fi
}

# 2. 添加用户
add_user() {
    echo -e "${BLUE}>>> 添加新用户${PLAIN}"
    
    read -p "请输入用户备注 (例如: friend_bob): " email
    if [ -z "$email" ]; then echo -e "${RED}备注不能为空${PLAIN}"; return; fi
    
    # 检查备注是否重复
    if grep -q "$email" "$CONFIG_FILE"; then
        echo -e "${RED}错误: 该备注已存在！${PLAIN}"
        return
    fi
    
    # 生成新 UUID
    local new_uuid=$(xray uuid)
    # 获取 flow 设置 (Reality通常是 xtls-rprx-vision，跟随主配置)
    local flow=$(jq -r '.inbounds[0].settings.clients[0].flow // "xtls-rprx-vision"' "$CONFIG_FILE")
    
    echo -e "正在添加: ${GREEN}$email${PLAIN} (UUID: $new_uuid)"
    
    # [关键步骤] 在修改前创建临时备份
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

    # 使用 jq 将新对象追加到 clients 数组
    tmp=$(mktemp)
    jq --arg email "$email" --arg id "$new_uuid" --arg flow "$flow" \
       '.inbounds[0].settings.clients += [{"id": $id, "flow": $flow, "email": $email}]' \
       "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
       
    restart_service "添加成功！"
    
    # 显示该用户的分享链接
    echo -e "${YELLOW}新用户凭证:${PLAIN}"
    echo -e "UUID: $new_uuid"
    echo -e "Flow: $flow"
}

# 3. 删除用户
del_user() {
    list_users
    echo -e "${YELLOW}请输入要删除的用户 序号 (不是备注):${PLAIN}"
    read -p "序号: " idx
    
    if ! [[ "$idx" =~ ^[0-9]+$ ]]; then echo -e "${RED}输入无效${PLAIN}"; return; fi
    
    # 获取数组长度
    local len=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE")
    
    if [ "$idx" -lt 1 ] || [ "$idx" -gt "$len" ]; then
        echo -e "${RED}序号超出范围${PLAIN}"; return; fi
        
    # 防止删除最后一个用户 (导致配置为空)
    if [ "$len" -le 1 ]; then
        echo -e "${RED}错误: 至少保留一个用户，无法清空！${PLAIN}"; return; fi

    # 转换序号为数组下标 (jq 从 0 开始)
    local array_idx=$((idx - 1))
    local email=$(jq -r ".inbounds[0].settings.clients[$array_idx].email" "$CONFIG_FILE")

    echo -e "确认删除用户: ${RED}$email${PLAIN} ? [y/n]"
    read -p "" confirm
    if [[ "$confirm" != "y" ]]; then return; fi
    
    echo -e "${BLUE}>>> 正在删除...${PLAIN}"

    # [关键步骤] 在修改前创建临时备份
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

    tmp=$(mktemp)
    # 删除了之前的占位符
    jq "del(.inbounds[0].settings.clients[$array_idx])" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    
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
    echo -e "  1. 查看用户列表"
    echo -e "  2. ${GREEN}添加新用户 (Add)${PLAIN}"
    echo -e "  3. ${RED}删除旧用户 (Delete)${PLAIN}"
    echo -e "-------------------------------------------------"
    echo -e "  0. 退出"
    echo -e ""
    read -p "请输入选项 [0-3]: " choice

    case "$choice" in
        1) list_users; read -n 1 -s -r -p "按任意键继续..." ;;
        2) add_user; read -n 1 -s -r -p "按任意键继续..." ;;
        3) del_user; read -n 1 -s -r -p "按任意键继续..." ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入无效${PLAIN}"; sleep 1 ;;
    esac
done
