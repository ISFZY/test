#!/bin/bash
# --- 2. 安装流程 (Core Installation) ---

# ==========================================
# 辅助函数定义 (Helpers)
# ==========================================

# 1. 任务执行器 (UI 优化版：单行刷新)
execute_task() {
    local cmd="$1"
    local desc="$2"
    
    # 1. 打印提示，不换行 (-n)
    echo -ne "${INFO} ${YELLOW}正在处理 : ${desc}...${PLAIN}"
    
    # 2. 捕获错误输出以防排查
    local err_log=$(mktemp)
    
    if eval "$cmd" >/dev/null 2>$err_log; then
        rm -f "$err_log"
        # 3. 成功：\r 回到行首，\033[K 清除整行，然后打印绿色的成功信息
        echo -e "\r\033[K${OK} ${desc}"
        return 0
    else
        # 4. 失败：换行打印错误详情
        echo -e "\n${ERR} ${desc} 失败"
        echo -e "${RED}=== 错误详情 ===${PLAIN}"
        cat "$err_log"
        rm -f "$err_log"
        return 1
    fi
}

# 2. Xray 核心安装逻辑 (逻辑不变，UI跟随 execute_task 变清爽)
install_xray_robust() {
    local max_tries=3
    local count=0
    local bin_path="/usr/local/bin/xray"
    local VER_ARG=""
    
    if [ -n "$FIXED_VER" ]; then
        VER_ARG="--version $FIXED_VER"
        # echo -e "${INFO} 版本锁定: ${YELLOW}${FIXED_VER}${PLAIN}" # 可选：觉得乱可以注释掉
    fi
    
    mkdir -p /usr/local/share/xray/

    while [ $count -lt $max_tries ]; do
        # 简化描述，去掉 "第x次尝试" 这种吓人的提示，除非真的重试了
        local desc="安装 Xray Core"
        if [ $count -gt 0 ]; then desc="安装 Xray Core (重试: $((count+1)))"; fi
        
        local install_cmd="bash -c \"\$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)\" @ install --without-geodata $VER_ARG"
        
        if execute_task "$install_cmd" "$desc"; then
            if [ -f "$bin_path" ] && "$bin_path" version &>/dev/null; then
                # 获取版本号并显示在同一行，或者作为补充信息
                local ver=$("$bin_path" version | head -n 1 | awk '{print $2}')
                # 这里补充打印一行版本信息，比较重要
                echo -e "    └─ 版本: ${GREEN}${ver}${PLAIN}"
                return 0
            fi
        fi
        
        rm -rf "$bin_path" "/usr/local/share/xray/"
        ((count++))
        sleep 2
    done
    
    echo -e "${ERR} [FATAL] Xray Core 安装失败，请检查网络。"
    exit 1
}

# 3. GeoData 数据库安装逻辑
install_geodata_robust() {
    local share_dir="/usr/local/share/xray"
    local bin_dir="/usr/local/bin"
    mkdir -p "$share_dir"
    
    declare -A files
    files["geoip.dat"]="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
    files["geosite.dat"]="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

    # echo -e "${INFO} 下载规则数据库..." # 这一行也可以省掉，直接看下面的下载进度

    for name in "${!files[@]}"; do
        local url="${files[$name]}"
        local file_path="$share_dir/$name"
        local link_path="$bin_dir/$name"

        execute_task "curl -L -o $file_path $url" "下载资源 $name"

        # 校验逻辑保持不变
        local fsize=$(du -k "$file_path" 2>/dev/null | awk '{print $1}')
        if [ ! -f "$file_path" ] || [ -z "$fsize" ] || [ "$fsize" -lt 50 ]; then
            execute_task "curl -L -o $file_path $url" "校验失败，重试下载 $name"
        fi

        ln -sf "$file_path" "$link_path"
    done

    # 简化的自动更新设置提示
    local update_cmd="curl -L -o $share_dir/geoip.dat ${files[geoip.dat]} && curl -L -o $share_dir/geosite.dat ${files[geosite.dat]} && /usr/bin/systemctl restart xray"
    local cron_job="0 4 * * 0 $update_cmd >/dev/null 2>&1"
    
    if ! command -v crontab &>/dev/null; then apt-get install -y cron &>/dev/null; fi
    (crontab -l 2>/dev/null | grep -v 'geoip.dat' | grep -v 'geosite.dat'; echo "$cron_job") | crontab -
    
    echo -e "    └─ 自动更新: ${GREEN}已配置 (每周日 4:00)${PLAIN}"
}

# ==========================================
# 主入口函数 (Main Function)
# ==========================================
core_install() {
    echo -e "\n${BLUE}--- 2. 核心组件 (Core) ---${PLAIN}"

    # 1. 抑制交互与系统清理 (合并显示)
    export DEBIAN_FRONTEND=noninteractive
    mkdir -p /etc/needrestart/conf.d
    echo "\$nrconf{restart} = 'a';" > /etc/needrestart/conf.d/99-xray-auto.conf
    rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*
    
    # 2. 系统更新 (合并为一个任务显示)
    execute_task "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' upgrade" "系统更新与升级"

    # 3. 依赖安装 (静默处理)
    # 这里的策略是：先显示“正在检查依赖”，然后只对缺失的包进行安装提示
    # 如果全部已安装，瞬间闪过，非常清爽
    
    local DEPENDENCIES=("curl" "wget" "tar" "unzip" "fail2ban" "rsyslog" "chrony" "iptables" "iptables-persistent" "qrencode" "jq" "cron" "python3-systemd" "lsof")
    local MISSING_PKGS=()

    echo -ne "${INFO} 正在检查系统依赖..."
    
    for pkg in "${DEPENDENCIES[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            MISSING_PKGS+=("$pkg")
        fi
    done
    
    # 清除“正在检查”那一行，显示结果
    echo -e "\r\033[K${OK} 系统依赖检查完成"

    # 只有当有缺失包时，才显示安装过程
    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        for pkg in "${MISSING_PKGS[@]}"; do
            execute_task "apt-get install -y $pkg" "安装依赖组件: $pkg"
            
            # 简单校验
            if ! dpkg -s "$pkg" &>/dev/null; then
                apt-get update -qq --fix-missing
                execute_task "apt-get install -y $pkg" "重试安装依赖: $pkg"
            fi
        done
    else
        echo -e "    └─ 所有依赖已就绪，跳过安装。"
    fi

    # 4. 调用安装函数
    install_xray_robust
    install_geodata_robust

    echo -e "${INFO} ${GREEN}核心组件部署完成。${PLAIN}"
}
