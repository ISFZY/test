#!/bin/bash

# =========================================================
# 定义颜色
# =========================================================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

BACKUP_DIR="/usr/local/etc/xray/backup"
CONFIG_FILE="/usr/local/etc/xray/config.json"

# 确保备份目录存在
mkdir -p "$BACKUP_DIR"

# =========================================================
# 核心逻辑
# =========================================================

# 1. 创建备份
create_backup() {
    echo -e "${BLUE}>>> 正在创建备份...${PLAIN}"
    
    # 生成时间戳文件名: config_20231027_120000.json
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    local backup_file="$BACKUP_DIR/config_$timestamp.json"
    
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$backup_file"
        echo -e "${GREEN}备份成功！${PLAIN}"
        echo -e "备份文件: ${YELLOW}$backup_file${PLAIN}"
        
        # 只保留最近 5 个备份，删除旧的
        cd "$BACKUP_DIR"
        ls -t config_*.json | tail -n +6 | xargs -I {} rm -- {} 2>/dev/null
    else
        echo -e "${RED}错误：找不到配置文件，无法备份。${PLAIN}"
    fi
}

# 2. 还原备份
restore_backup() {
    # 获取备份列表
    local files=($(ls -t "$BACKUP_DIR"/config_*.json 2>/dev/null))
    
    if [ ${#files[@]} -eq 0 ]; then
        echo -e "${RED}没有找到任何备份文件。${PLAIN}"
        return
    fi
    
    echo -e "${BLUE}>>> 请选择要还原的备份点：${PLAIN}"
    
    local i=1
    for file in "${files[@]}"; do
        # 提取文件名中的时间部分展示
        filename=$(basename "$file")
        echo -e "  $i. $filename"
        let i++
    done
    
    echo -e "-------------------------------------------------"
    echo -e "  0. 取消"
    echo -e ""
    read -p "请输入选项 [0-${#files[@]}]: " choice
    
    if [ "$choice" == "0" ]; then return; fi
    
    # 检查输入是否合法
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -le "${#files[@]}" ] && [ "$choice" -gt 0 ]; then
        local target_file="${files[$((choice-1))]}"
        
        echo -e "${YELLOW}警告：这将覆盖当前的 config.json，确定吗？[y/n]${PLAIN}"
        read -p "" confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            cp "$target_file" "$CONFIG_FILE"
            echo -e "${GREEN}配置已还原！正在重启服务...${PLAIN}"
            systemctl restart xray
            
            if systemctl is-active --quiet xray; then
                 echo -e "${GREEN}服务启动成功！${PLAIN}"
            else
                 echo -e "${RED}服务启动失败，请检查备份文件是否损坏。${PLAIN}"
            fi
        else
            echo -e "操作已取消。"
        fi
    else
        echo -e "${RED}输入无效。${PLAIN}"
    fi
}

# 3. 导出备份 (给用户下载)
export_backup() {
    if [ ! -f "$CONFIG_FILE" ]; then echo -e "${RED}无配置可导出${PLAIN}"; return; fi
    
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${BLUE}           配置内容预览 (Copy & Paste)           ${PLAIN}"
    echo -e "${BLUE}=================================================${PLAIN}"
    cat "$CONFIG_FILE"
    echo -e "\n${BLUE}=================================================${PLAIN}"
    echo -e "${YELLOW}提示：你可以复制上方内容保存到本地电脑。${PLAIN}"
}

# =========================================================
# 菜单
# =========================================================
while true; do
    clear
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${BLUE}           Xray 配置备份与还原 (Backup)          ${PLAIN}"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "  1. 创建新备份 (Create Backup)"
    echo -e "  2. 还原旧配置 (Restore Backup)"
    echo -e "  3. 查看/导出当前配置"
    echo -e "-------------------------------------------------"
    echo -e "  0. 退出"
    echo -e ""
    read -p "请输入选项 [0-3]: " choice

    case "$choice" in
        1) create_backup; read -n 1 -s -r -p "按任意键继续..." ;;
        2) restore_backup; read -n 1 -s -r -p "按任意键继续..." ;;
        3) export_backup; read -n 1 -s -r -p "按任意键继续..." ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入无效${PLAIN}"; sleep 1 ;;
    esac
done
