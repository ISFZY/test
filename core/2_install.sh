#!/bin/bash
# --- 2. 安装流程 (Core Installation) ---

# 辅助函数定义 (Helpers)
# 1. 任务执行器
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

# 2. Xray 核心安装逻辑 (逻辑不变，UI跟随 execute_task )
install_xray_robust() {
    local max_tries=3
    local count=0
    local bin_path="/usr/local/bin/xray"
    local VER_ARG=""
    
    if [ -n "$FIXED_VER" ]; then
        VER_ARG="--version $FIXED_VER"
        # echo -e "${INFO} 版本锁定: ${YELLOW}${FIXED_VER}${PLAIN}" # 可选
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
    echo -e "${INFO} 正在安装 GeoData 路由规则库..."
    
    local share_dir="/usr/local/share/xray"
    mkdir -p "$share_dir"
    
    local urls=(
        "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
        "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
    )
    
    local tmp_ip=$(mktemp)
    local tmp_site=$(mktemp)
    local max_retries=3
    local attempt=1
    local success=false

    # 业务层级的重试循环 (最多尝试 3 次)
    while [ $attempt -le $max_retries ]; do
        echo -e "   [-] 直连拉取 GeoData (尝试 $attempt/$max_retries) ..."
        
        # curl 自身的 --retry 用于处理底层的断流
        curl -sSLk --retry 3 -o "$tmp_ip" "${urls[0]}"
        curl -sSLk --retry 3 -o "$tmp_site" "${urls[1]}"
        
        # 核心防线：文件大小校验
        local size_ip=$(du -k "$tmp_ip" | awk '{print $1}')
        local size_site=$(du -k "$tmp_site" | awk '{print $1}')
        
        if [ -n "$size_ip" ] && [ "$size_ip" -gt 1000 ] && [ -n "$size_site" ] && [ "$size_site" -gt 1000 ]; then
            success=true
            break # 校验通过，直接跳出重试循环
        else
            echo -e "   [WARN] 第 $attempt 次拉取失败 (文件损坏或过小)，准备重试..."
            sleep 2 # 稍微停顿 2 秒，避免被 GitHub 频繁请求拦截
            attempt=$((attempt + 1))
        fi
    done

    # 循环结束后，判断最终结果
    if [ "$success" = true ]; then
        mv -f "$tmp_ip" "$share_dir/geoip.dat"
        mv -f "$tmp_site" "$share_dir/geosite.dat"
        chmod 644 "$share_dir"/*.dat
        echo -e "${OK} GeoData 规则库下载并校验成功！"
    else
        echo -e "${ERR} GeoData 下载失败（连续 $max_retries 次拉取均损坏），为保障服务安全，已终止安装！"
        rm -f "$tmp_ip" "$tmp_site"
        exit 1
    fi
    
    # --- 定时任务 (Cron) ---
    local safe_cron_cmd="tmp_ip=\$(mktemp) && tmp_site=\$(mktemp) && curl -sSLk --retry 3 -o \$tmp_ip ${urls[0]} && curl -sSLk --retry 3 -o \$tmp_site ${urls[1]} && if [ \$(du -k \$tmp_ip | awk '{print \$1}') -gt 1000 ] && [ \$(du -k \$tmp_site | awk '{print \$1}') -gt 1000 ]; then mv -f \$tmp_ip $share_dir/geoip.dat && mv -f \$tmp_site $share_dir/geosite.dat && systemctl restart xray; else rm -f \$tmp_ip \$tmp_site; fi"
    
    local cron_job="0 4 * * 0 $safe_cron_cmd >/dev/null 2>&1"
    
    if command -v crontab &>/dev/null; then
        (crontab -l 2>/dev/null | grep -v "geoip.dat" | grep -v "geosite.dat"; echo "$cron_job") | crontab -
    echo -e "    └─ 自动更新: ${GREEN}已配置 (每周日 4:00)${PLAIN}"
    else
        echo -e "${WARN} 未检测到 crontab，跳过自动更新配置"
    fi
}

# 主入口函数 (Main Function)
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
