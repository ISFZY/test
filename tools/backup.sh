#!/bin/bash

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

BACKUP_DIR="/usr/local/etc/xray/backup"
CONFIG_FILE="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
ASSET_DIR="/usr/local/share/xray"

# 确保备份目录存在
mkdir -p "$BACKUP_DIR"

# 1. 创建备份
create_backup() {
    echo -e "${BLUE}>>> 正在创建备份...${PLAIN}"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误：找不到配置文件，无法备份。${PLAIN}"
        return
    fi

    local timestamp=$(date "+%Y%m%d_%H%M%S")
    local backup_file="$BACKUP_DIR/config_$timestamp.json"
    
    cp "$CONFIG_FILE" "$backup_file"
    echo -e "${GREEN}备份成功！${PLAIN}"
    echo -e "备份文件: ${YELLOW}$backup_file${PLAIN}"
    
    # 保留最近9份
    local count=$(ls -1 "$BACKUP_DIR"/config_*.json 2>/dev/null | wc -l)
    if [ "$count" -gt 9 ]; then
        echo -e "${YELLOW}清理旧备份 (保留最近9份)...${PLAIN}"
        cd "$BACKUP_DIR"
        ls -t config_*.json | tail -n +10 | xargs -I {} rm -- {} 2>/dev/null
    fi
}

# 2. 还原备份
restore_backup() {
    local files=($(ls -t "$BACKUP_DIR"/config_*.json 2>/dev/null))
    
    if [ ${#files[@]} -eq 0 ]; then
        echo -e "${RED}没有找到任何备份文件。${PLAIN}"
        return
    fi
    
    echo -e "${BLUE}>>> 请选择要还原的备份点：${PLAIN}"

    echo -e "-------------------------------------------------------"
    local i=1
    for file in "${files[@]}"; do
        filename=$(basename "$file")
        filetime=$(date -r "$file" "+%Y-%m-%d %H:%M:%S")
        
        local tag=""
        if [ "$i" -eq 1 ]; then
            tag="${GREEN}最新${PLAIN}"
        fi
        
        echo -e "  ${GREEN}$i.${PLAIN} $filename  ${YELLOW}($filetime)${PLAIN} $tag"
        let i++
    done
    
    echo -e "-------------------------------------------------------"
    echo -e "  0. 取消"
    echo -e ""
    
    local limit=${#files[@]}
    echo -ne "请输入选项 [0-$limit]: "
    
    while true; do
        read -n 1 -s key < /dev/tty
        
        if [[ "$key" =~ ^[0-9]$ ]]; then
            if [ "$key" -eq 0 ]; then
                echo "$key"
                echo -e "\n操作已取消。"
                return
            fi
            
            if [ "$key" -le "$limit" ] && [ "$key" -gt 0 ]; then
                echo "$key"
                choice=$key
                break
            else
                echo -ne "\r\033[K${RED}错误：选项无效，请输入 0-$limit${PLAIN}"
                sleep 0.5
                echo -ne "\r\033[K请输入选项 [0-$limit]: "
            fi
        else
            echo -ne "\r\033[K${RED}错误：输入无效，请按数字键${PLAIN}"
            sleep 0.5
            echo -ne "\r\033[K请输入选项 [0-$limit]: "
        fi
    done
    
    local target_file="${files[$((choice-1))]}"
            
    echo -e "\n您选择了: ${YELLOW}$(basename "$target_file")${PLAIN}"
    
    echo -e "正在校验备份文件..."
    
    if ! XRAY_LOCATION_ASSET="$ASSET_DIR" "$XRAY_BIN" run -test -c "$target_file" >/dev/null 2>&1; then
        echo -e "${RED}错误：该备份文件校验失败，无法还原！${PLAIN}"
        echo -e "${YELLOW}>>> 错误详情 (Debug Info):${PLAIN}"
        XRAY_LOCATION_ASSET="$ASSET_DIR" "$XRAY_BIN" run -test -c "$target_file"
        return
    fi

    local confirm_msg="确定要覆盖当前配置吗？此操作不可逆！[y/n]: "
    echo -ne "$confirm_msg"
    
    while true; do
        read -n 1 -s key < /dev/tty
        
        case "$key" in
            [yY]) 
                echo "$key"
                break 
                ;;
            [nN]) 
                echo "$key"
                echo -e "\n操作已取消。"
                return 
                ;;
            *) 
                echo -ne "\r\033[K${RED}错误：输入无效，请输入 y 或 n${PLAIN}"
                sleep 0.5
                echo -ne "\r\033[K$confirm_msg"
                ;;
        esac
    done
            
    echo -e "\n${BLUE}>>> 正在还原...${PLAIN}"
    cp "$target_file" "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"

    systemctl restart xray
    sleep 1
    
    if systemctl is-active --quiet xray; then
            echo -e "${GREEN}还原成功！服务已重启。${PLAIN}"
    else
            echo -e "${RED}警告：配置已还原，但服务启动失败。${PLAIN}"
            echo -e "请检查日志: journalctl -u xray -n 10"
    fi
}

# 3. 导出备份
export_backup() {
    if [ ! -f "$CONFIG_FILE" ]; then echo -e "${RED}无配置可导出${PLAIN}"; return; fi
    
    echo -e "${BLUE}=======================================================${PLAIN}"
    echo -e "${BLUE}           配置内容预览 (Copy & Paste)           ${PLAIN}"
    echo -e "${BLUE}=======================================================${PLAIN}"
    cat "$CONFIG_FILE"
    echo -e "\n${BLUE}=======================================================${PLAIN}"
    echo -e "${YELLOW}提示：你可以复制上方内容保存到本地 config.json${PLAIN}"
}

# 菜单显示函数
show_menu() {
    clear
    echo -e "${BLUE}=======================================================${PLAIN}"
    echo -e "${BLUE}           Xray 配置备份与还原 (Backup)          ${PLAIN}"
    echo -e "${BLUE}=======================================================${PLAIN}"
    echo -e "  1. ${GREEN}创建新备份 (Create)${PLAIN}"
    echo -e "  2. ${RED}还原旧配置 (Restore)${PLAIN}"
    echo -e "  3. 查看/导出当前配置"
    echo -e "-------------------------------------------------------"
    echo -e "  0. 退出"
    echo -e ""
}

# --- 主程序逻辑 ---

# 1. 首次显示菜单
show_menu

# 2. 标记是否需要打印提示符
need_prompt=true

while true; do
    # 只有当任务完成或刚开始时，才打印提示符
    if [ "$need_prompt" = true ]; then
        echo -ne "请输入选项 [0-3]: "
        need_prompt=false
    fi

    # 读取按键 (增加 -r 防止转义，< /dev/tty 强制读键盘)
    read -n 1 -s -r key < /dev/tty
    
    # 防空值死循环
    if [ -z "$key" ]; then continue; fi

    case "$key" in
        [0-3])
            # 输入有效：回显
            echo "$key"
            echo ""
            
            case "$key" in
                1) 
                    # === 选项1：备份 ===
                    # 1. 执行备份
                    create_backup
                    # 2. 打印空行美观
                    echo ""
                    # 3. 标记为 true，下次循环直接打印“请输入选项 [0-3]:”，不清屏，不等待
                    need_prompt=true
                    ;;
                    
                2) 
                    # === 选项2：还原 ===
                    restore_backup
                    # 还原操作可能输出很多内容，需要暂停让用户看
                    read -n 1 -s -r -p "按任意键返回菜单..." < /dev/tty
                    # 重新画菜单
                    show_menu
                    need_prompt=true
                    ;;
                    
                3) 
                    # === 选项3：导出 ===
                    export_backup
                    read -n 1 -s -r -p "按任意键返回菜单..." < /dev/tty
                    show_menu
                    need_prompt=true
                    ;;
                    
                0) 
                    exit 0 
                    ;;
            esac
            ;;
            
        *)
            # === 错误处理：原地报错 ===
            echo -ne "\r\033[K${RED}错误：输入无效，请按 0-3${PLAIN}"
            sleep 0.5
            echo -ne "\r\033[K请输入选项 [0-3]: "
            ;;
    esac
done
