pre_flight_check() {
    # 检测包管理器锁
    is_package_manager_running() {
        pgrep -x apt >/dev/null || pgrep -x apt-get >/dev/null || pgrep -x dpkg >/dev/null || pgrep -f "unattended-upgr" >/dev/null
    }

    local desc="环境检查 (Environment Check)"
    local max_ticks=300 # 300秒超时
    local ticks=0
    
    # 1. 如果占用，显示等待 Spinner
    if is_package_manager_running; then
        echo -e "${INFO} 检测到系统更新进程正在运行，正在等待释放锁..."
        # 隐藏光标
        tput civis 
        while is_package_manager_running; do
            if [ $ticks -ge $max_ticks ]; then
                tput cnorm
                echo -e "\n${WARN} 等待超时！用户可选择手动杀进程或继续等待。"
                read -p "是否强制终止占用进程? (y/n) [n]: " kill_choice
                if [[ "$kill_choice" == "y" ]]; then
                    killall apt apt-get 2>/dev/null
                    rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*
                    break
                else
                    echo -e "${ERR} 用户取消，安装终止。"; exit 1
                fi
            fi
            
            # 简单的转圈动画
            local frame=${UI_SPINNER_FRAMES[$((ticks % 4))]}
            printf "\r ${BLUE}[ %s ]${PLAIN} System busy... (${ticks}s)" "$frame"
            
            sleep 0.5
            ((ticks++))
        done
        tput cnorm
        echo -ne "\r\033[K" # 清除等待行
    fi

    # 2. 检查 dpkg 状态
    if ! dpkg --audit >/dev/null 2>&1; then
        echo -e "${ERR} 检测到 dpkg 数据库状态异常！"
        echo -e "${YELLOW}建议执行: 'dpkg --configure -a' 修复系统。${PLAIN}"
        exit 1
    fi
    
    echo -e "${OK}   ${desc}"
}

check_net_stack() {
    HAS_V4=false; HAS_V6=false; CURL_OPT=""
    if curl -s4m 2 https://1.1.1.1 >/dev/null 2>&1; then HAS_V4=true; fi
    if curl -s6m 2 https://2606:4700:4700::1111 >/dev/null 2>&1; then HAS_V6=true; fi

    if [ "$HAS_V4" = true ] && [ "$HAS_V6" = true ]; then
        NET_TYPE="Dual-Stack (双栈)"; CURL_OPT="-4"; DOMAIN_STRATEGY="IPIfNonMatch"
    elif [ "$HAS_V4" = true ]; then
        NET_TYPE="IPv4 Only"; CURL_OPT="-4"; DOMAIN_STRATEGY="UseIPv4"
    elif [ "$HAS_V6" = true ]; then
        NET_TYPE="IPv6 Only"; CURL_OPT="-6"; DOMAIN_STRATEGY="UseIPv6"
    else
        echo -e "${ERR} 无法连接互联网，请检查网络！"; exit 1
    fi
    
    echo -e "${OK}   网络检测: ${GREEN}${NET_TYPE}${PLAIN}"
}

# --- 静默时区同步 ---
setup_timezone() {
    echo -e "\n${BLUE}--- 1. 时间同步 (Time Sync) ---${PLAIN}"
    
    # 1. 强制开启 NTP
    timedatectl set-ntp true >/dev/null 2>&1
    
    # 2. 检测当前状态
    local current_tz=$(timedatectl show -p Timezone --value)
    if [ -z "$current_tz" ]; then
        # 如果检测不到，兜底设置为 UTC
        timedatectl set-timezone UTC
        current_tz="UTC (Default)"
    fi
    
    echo -e "${OK}   当前时区: ${YELLOW}${current_tz}${PLAIN}"
    echo -e "${OK}   NTP 同步: ${GREEN}已启用${PLAIN}"
    echo -e "${INFO} (如需修改时区，安装后请输入 'zone')"
}
