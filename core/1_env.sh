#!/bin/bash
# --- 1. 环境准备与检测 (Environment) ---

# 系统与架构检测
check_sys_arch() {
    local desc="系统检查 (OS & Arch)"
    
    # 1. 检查是否为 Debian/Ubuntu 系
    if [ ! -f /etc/debian_version ]; then
        echo -e "${ERR} 本脚本仅支持 Debian/Ubuntu 系统！"
        echo -e "${YELLOW}请更换系统后重试。${PLAIN}"
        exit 1
    fi

    # 2. 检查架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) 
            echo -e "${ERR} 不支持的 CPU 架构: ${ARCH}"
            exit 1 
            ;;
    esac
    
    echo -e "${OK} ${desc}: Debian/Ubuntu (${ARCH})"
}

pre_flight_check() {
    # 检测包管理器锁
    is_package_manager_running() {
        pgrep -x apt >/dev/null || pgrep -x apt-get >/dev/null || pgrep -x dpkg >/dev/null || pgrep -f "unattended-upgr" >/dev/null
    }

    local desc="环境预检 (Pre-flight Check)"
    local max_ticks=300 # 300秒超时
    local ticks=0
    
    # 1. 锁占用检测
    if is_package_manager_running; then
        echo -e "${INFO} 检测到系统更新进程正在运行，正在等待释放锁..."
        # 隐藏光标
        tput civis 
        while is_package_manager_running; do
            if [ $ticks -ge $max_ticks ]; then
                tput cnorm
                echo -e "\n${WARN} 等待超时！"
                
                # --- 交互输入 ---
                local kill_choice=""
                while true; do
                    # 移除 echo -ne，直接使用 read -p，并去掉 -n 1 和 -s
                    read -p "是否强制终止占用进程? (y/n) [n]: " raw_input
                    
                    # 1. 处理直接回车 (默认为 n)
                    if [ -z "$raw_input" ]; then
                        # 删掉手动 echo "n"
                        kill_choice="n"
                        break
                    fi

                    # 2. 校验输入 (不区分大小写)
                    if [[ "$raw_input" =~ ^[yYnN]$ ]]; then
                        kill_choice="$raw_input"
                        break
                    else
                        # 3. 错误处理
                        # A. 打印出错误的字符(让用户知道按了啥)并换行
                        echo "$raw_input"
                        # B. 光标上移一行 + 清除整行 (抹掉 Prompt 行)
                        echo -ne "\033[1A\033[2K"
                        # C. 打印报错
                        echo -e "${RED}[错误] 输入无效 '$raw_input'，请按 y 或 n。${PLAIN}"
                        # D. 循环继续，read 会在下方重新打印提示符
                    fi
                done

                # 执行选择逻辑
                if [[ "$kill_choice" =~ ^[yY]$ ]]; then
                    echo -e "${INFO} 正在强制终止进程..."
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

    # 3. 提前安装基础工具 (防止 check_net_stack 崩溃)
    if ! command -v curl >/dev/null 2>&1 || ! command -v ca-certificates >/dev/null 2>&1; then
        echo -e "${INFO} 正在安装基础网络工具 (curl)..."
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq curl wget ca-certificates >/dev/null 2>&1
    fi
    
    echo -e "${OK} ${desc}"
}

check_net_stack() {
    HAS_V4=false; HAS_V6=false; CURL_OPT=""
    
    # 修复 1：增加 -k 参数，防止系统 CA 证书过期导致的网络误判
    if curl -s4mk 3 https://1.1.1.1 >/dev/null 2>&1; then HAS_V4=true; fi
    if curl -s6mk 3 https://2606:4700:4700::1111 >/dev/null 2>&1; then HAS_V6=true; fi

    if [ "$HAS_V4" = true ] && [ "$HAS_V6" = true ]; then
        NET_TYPE="Dual-Stack (双栈)"
        CURL_OPT="-4"
        DOMAIN_STRATEGY="IPIfNonMatch"
    elif [ "$HAS_V4" = true ]; then
        NET_TYPE="IPv4 Only"
        CURL_OPT="-4"
        DOMAIN_STRATEGY="UseIPv4"
    elif [ "$HAS_V6" = true ]; then
        NET_TYPE="IPv6 Only"
        CURL_OPT="-6"
        DOMAIN_STRATEGY="UseIPv6"
        
        # 修复 2：为安装过程中的后续 curl 下载强制保持 DNS64 状态
        echo -e "${INFO} 为纯 IPv6 环境配置 NAT64/DNS64 网关..."
        echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2fac::1" > /etc/resolv.conf
    else
        echo -e "${ERR} 无法连接互联网，请检查网络配置！"
        exit 1
    fi
    
    echo -e "${OK} 网络检测: ${GREEN}${NET_TYPE}${PLAIN}"
}

setup_timezone() {
    echo -e "\n${BLUE}--- 1. 基础环境配置 (Basic Env) ---${PLAIN}"
    
    # 1. 执行系统检查
    check_sys_arch
    
    # 2. 强制开启 NTP
    timedatectl set-ntp true >/dev/null 2>&1
    
    # 3. 检测并显示时区
    local current_tz=$(timedatectl show -p Timezone --value)
    if [ -z "$current_tz" ]; then
        timedatectl set-timezone UTC
        current_tz="UTC (Default)"
    fi
    
    echo -e "${OK} 当前时区: ${YELLOW}${current_tz}${PLAIN}"
    echo -e "${INFO} (如需修改时区，安装后请输入 'zone')"
}
