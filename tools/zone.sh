#!/bin/bash

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 核心函数
# 1. 获取当前时间状态
get_time_status() {
    local tz=$(timedatectl show -p Timezone --value)
    local ntp_active=$(timedatectl show -p NTP --value)
    local is_synced=$(timedatectl show -p NTPSynchronized --value)
    
    echo -e "-------------------------------------------------"
    echo -e "  当前时间 : ${YELLOW}$(date "+%Y-%m-%d %H:%M:%S")${PLAIN}"
    echo -e "  当前时区 : ${GREEN}${tz}${PLAIN}"
    
    if [ "$ntp_active" == "yes" ]; then
        echo -e "  自动同步 : ${GREEN}已开启 (Active)${PLAIN}"
    else
        echo -e "  自动同步 : ${RED}已关闭 (Inactive)${PLAIN}"
    fi
    
    if [ "$is_synced" == "yes" ]; then
        echo -e "  同步状态 : ${GREEN}已校准 (Synced)${PLAIN}"
    else
        echo -e "  同步状态 : ${RED}未校准 / 偏差中${PLAIN}"
    fi
    echo -e "-------------------------------------------------"
}

# 2. 设置时区
set_timezone() {
    local target_tz=$1
    local name=$2
    
    echo -e "\n${BLUE}>>> 正在设置时区为: $name ($target_tz)...${PLAIN}"
    
    if timedatectl set-timezone "$target_tz"; then
        echo -e "${GREEN}设置成功！${PLAIN}"
        echo -e "当前本地时间: $(date)"
    else
        echo -e "${RED}设置失败，请检查时区名称是否正确。${PLAIN}"
    fi
}

# 3. 自定义时区输入
set_custom_timezone() {
    echo -e "\n${YELLOW}请输入目标时区 (例如: America/New_York 或 Europe/London)${PLAIN}"
    read -p "时区名: " custom_tz
    
    if [ -z "$custom_tz" ]; then return; fi
    
    if [ -f "/usr/share/zoneinfo/$custom_tz" ]; then
        set_timezone "$custom_tz" "$custom_tz"
    else
        echo -e "${RED}错误：系统找不到时区 '$custom_tz'。${PLAIN}"
        echo -e "提示：您可以运行 'timedatectl list-timezones' 查看支持列表。"
    fi
}

# 4. 强制同步时间
sync_time() {
    echo -e "\n${BLUE}>>> 正在进行网络时间校正...${PLAIN}"
    
    timedatectl set-ntp true
    
    if systemctl is-active --quiet chrony; then
        systemctl restart chrony
        echo -e "   [OK] 重启 chrony 服务"
    elif systemctl is-active --quiet systemd-timesyncd; then
        systemctl restart systemd-timesyncd
        echo -e "   [OK] 重启 systemd-timesyncd 服务"
    else
        if command -v apt-get &>/dev/null; then
            echo -e "${YELLOW}未检测到时间服务，正在安装 chrony...${PLAIN}"
            apt-get update -qq && apt-get install -y chrony -qq
            systemctl enable --now chrony
        fi
    fi
    
    local timeout=15
    tput civis
    
    for ((i=timeout; i>0; i--)); do
        if [ "$(timedatectl show -p NTPSynchronized --value)" == "yes" ]; then
            local cost=$((timeout - i))
            echo -e "\r   状态: ${GREEN}同步成功！ (耗时 ${cost}s)${PLAIN}\033[K"
            hwclock -w
            tput cnorm 
            return
        fi
        
        echo -ne "\r   状态: ${YELLOW}正在与 NTP 服务器握手... 剩余 ${i} 秒${PLAIN}"
        sleep 1
    done
    
    tput cnorm
    echo -e "\r   状态: ${RED}同步响应超时 (后台仍在尝试，请手动刷新)${PLAIN}\033[K"
    hwclock -w
}

# 菜单逻辑
# 首次运行时先清屏一次
clear

while true; do
    # 1. 光标回到 (0,0) 原点，开始覆盖绘制，不闪烁
    tput cup 0 0
    
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${BLUE}           系统时区与时间管理 (Zone Manager)     ${PLAIN}"
    echo -e "${BLUE}=================================================${PLAIN}"
    
    get_time_status
    
    echo -e "  1. 设置为 ${GREEN}中国上海时间${PLAIN} (Asia/Shanghai)"
    echo -e "  2. 设置为 ${GREEN}UTC 标准时间${PLAIN} (UTC)"
    echo -e "  3. 设置为 ${YELLOW}自定义时区${PLAIN}"
    echo -e "-------------------------------------------------"
    echo -e "  4. ${BLUE}强制同步网络时间 (Sync NTP)${PLAIN}"
    echo -e "-------------------------------------------------"
    echo -e "  0. 退出 (Exit)          ${YELLOW}Enter/F. 刷新 (Refresh)${PLAIN}"
    echo -e ""
    
    # 2. 清除菜单下方可能残留的旧信息 (Erase Down)
    tput ed

    # --- 输入监听循环 ---
    while true; do
        read -p $'\r\033[K请输入选项 [0-4]: ' choice
        
        case "$choice" in
            1|2|3|4|0|f|F|"") 
                break 
                ;;
            *) 
                echo -ne "\r\033[K${RED}输入无效，请重新输入...${PLAIN}"
                sleep 0.5
                ;;
        esac
    done

    # --- 业务执行 ---
    case "$choice" in
        1) 
            echo "" 
            set_timezone "Asia/Shanghai" "中国上海"
            sleep 2 
            ;;
        2) 
            echo "" 
            set_timezone "UTC" "UTC 标准时"
            sleep 2 
            ;;
        3) 
            echo "" 
            set_custom_timezone
            sleep 2 
            ;;
        4) 
            echo "" 
            sync_time
            sleep 2 
            ;;
        0) 
            # 退出时，光标移到最下方，避免覆盖菜单
            echo ""
            echo -e "退出程序。"
            exit 0 
            ;;
        f|F|"") 
            # 刷新操作：直接 continue
            continue 
            ;;
    esac
done
