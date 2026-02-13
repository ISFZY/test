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
# 指定资源文件路径 (geoip.dat/geosite.dat)
ASSET_DIR="/usr/local/share/xray"

# 确保备份目录存在
mkdir -p "$BACKUP_DIR"

# 核心逻辑

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
    
    # 保留最近10份
    local count=$(ls -1 "$BACKUP_DIR"/config_*.json 2>/dev/null | wc -l)
    if [ "$count" -gt 9 ]; then
        echo -e "${YELLOW}清理旧备份 (保留最近9份)...${PLAIN}"
        cd "$BACKUP_DIR"
        ls -t config_*.json | tail -n +11 | xargs -I {} rm -- {} 2>/dev/null
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

    echo -e "-------------------------------------------------"
    local i=1
    for file in "${files[@]}"; do
        filename=$(basename "$file")
        filetime=$(date -r "$file" "+%Y-%m-%d %H:%M:%S")
        
        # 如果是第一个文件(最新)，添加绿色标签
        local tag=""
        if [ "$i" -eq 1 ]; then
            tag="${GREEN}最新${PLAIN}"
        fi
        
        echo -e "  ${GREEN}$i.${PLAIN} $filename  ${YELLOW}($filetime)${PLAIN} $tag"
        let i++
    done
    
    echo -e "-------------------------------------------------"
    echo -e "  0. 取消"
    echo -e ""
    
    local limit=${#files[@]}
    echo -ne "请输入选项 [0-$limit]: "
    
    while true; do
        # 读取单个字符，< /dev/tty 确保脚本被 cat 管道调用时也能读取键盘
        read -n 1 -s key < /dev/tty
        
        # 1. 判断是否是数字
        if [[ "$key" =~ ^[0-9]$ ]]; then
            
            # 情况A: 输入 0 -> 取消
            if [ "$key" -eq 0 ]; then
                echo "$key"  # 手动回显字符
                echo -e "\n操作已取消。"
                return
            fi
            
            # 情况B: 输入有效数字 (1 到 文件总数)
            if [ "$key" -le "$limit" ] && [ "$key" -gt 0 ]; then
                echo "$key"  # 手动回显字符
                choice=$key  # 赋值给 choice 变量
                break        # 跳出循环，继续执行还原
            else
                # 情况C: 输入了数字，但超出了当前文件数量
                # \r 回到行首 + \033[K 清除行内容
                echo -ne "\r\033[K${RED}错误：选项无效，请输入 0-$limit${PLAIN}"
                sleep 0.5
                # 恢复提示
                echo -ne "\r\033[K请输入选项 [0-$limit]: "
            fi
        else
            # 情况D: 输入了非数字字符
            echo -ne "\r\033[K${RED}错误：输入无效，请按数字键${PLAIN}"
            sleep 0.5
            echo -ne "\r\033[K请输入选项 [0-$limit]: "
        fi
    done
    
    local target_file="${files[$((choice-1))]}"
            
        echo -e "\n您选择了: ${YELLOW}$(basename "$target_file")${PLAIN}"
        
        # 1. 预检备份文件完整性
        echo -e "正在校验备份文件..."
        
        if ! XRAY_LOCATION_ASSET="$ASSET_DIR" "$XRAY_BIN" run -test -c "$target_file" >/dev/null 2>&1; then
            echo -e "${RED}错误：该备份文件校验失败，无法还原！${PLAIN}"
            echo -e "${YELLOW}>>> 错误详情 (Debug Info):${PLAIN}"

            XRAY_LOCATION_ASSET="$ASSET_DIR" "$XRAY_BIN" run -test -c "$target_file"
            return
        fi

        # 确认覆盖
        local confirm_msg="确定要覆盖当前配置吗？此操作不可逆！[y/n]: "
        echo -ne "$confirm_msg"
        
        while true; do
            # 静默读取1个字符，强制从终端读取
            read -n 1 -s key < /dev/tty
            
            case "$key" in
                [yY]) 
                    # 输入正确：回显字符并换行，然后跳出循环去执行还原
                    echo "$key"
                    break 
                    ;;
                [nN]) 
                    # 输入取消：回显字符并换行，提示取消并返回
                    echo "$key"
                    echo -e "\n操作已取消。"
                    return 
                    ;;
                *) 
                    # 输入错误：
                    # \r 回到行首
                    # \033[K 清除当前行内容
                    echo -ne "\r\033[K${RED}错误：输入无效，请输入 y 或 n${PLAIN}"
                    sleep 0.5
                    # 恢复原本的提示语
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
                    break 
                    ;;
                [nN]) 
                    echo -e "\n操作已取消。"
                    return 
                    ;;
                *) ;;
            esac
        done
    else
        echo -e "${RED}输入无效。${PLAIN}"
    fi
}

# 3. 导出备份
export_backup() {
    if [ ! -f "$CONFIG_FILE" ]; then echo -e "${RED}无配置可导出${PLAIN}"; return; fi
    
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${BLUE}           配置内容预览 (Copy & Paste)           ${PLAIN}"
    echo -e "${BLUE}=================================================${PLAIN}"
    cat "$CONFIG_FILE"
    echo -e "\n${BLUE}=================================================${PLAIN}"
    echo -e "${YELLOW}提示：你可以复制上方内容保存到本地 config.json${PLAIN}"
}

# 菜单
while true; do
    clear
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${BLUE}           Xray 配置备份与还原 (Backup)          ${PLAIN}"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "  1. ${GREEN}创建新备份 (Create)${PLAIN}"
    echo -e "  2. ${RED}还原旧配置 (Restore)${PLAIN}"
    echo -e "  3. 查看/导出当前配置"
    echo -e "-------------------------------------------------"
    echo -e "  0. 退出"
    echo -e ""

    echo -ne "请输入选项 [0-3]: "

    while true; do
        # 2. 读取单个字符，静默模式 (-s) 不回显，无需回车
        read -n 1 -s key
        
        case "$key" in
            [0-3])
                # 输入有效：手动回显该字符并换行
                echo "$key"
                echo ""
                
                # 执行对应功能
                case "$key" in
                    1) create_backup; read -n 1 -s -r -p "按任意键继续..." ;;
                    2) restore_backup; read -n 1 -s -r -p "按任意键继续..." ;;
                    3) export_backup; read -n 1 -s -r -p "按任意键继续..." ;;
                    0) exit 0 ;;
                esac
                break # 跳出输入循环，重新刷新菜单
                ;;
            *)
                # 输入无效：
                # \r 回到行首
                # \033[K 清除当前行内容
                echo -ne "\r\033[K${RED}输入无效，请按 0-3${PLAIN}"
                sleep 0.5
                # 恢复原提示符
                echo -ne "\r\033[K请输入选项 [0-3]: "
                ;;
        esac
    done
