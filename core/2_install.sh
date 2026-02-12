#!/bin/bash
# --- 2. 安装流程 (Core Installation) ---

echo -e "\n${BLUE}--- 2. 开始安装核心组件 (Core Install) ---${PLAIN}"

# [兼容性保障] 防止 execute_task 未定义导致的报错
if ! command -v execute_task >/dev/null 2>&1; then
    execute_task() {
        local cmd="$1"
        local desc="$2"
        echo -e "${INFO} 正在执行: $desc ..."
        if eval "$cmd" >/dev/null 2>&1; then
            echo -e "${OK}   $desc 成功"
        else
            echo -e "${ERR}   $desc 失败"
            return 1
        fi
    }
fi

# 抑制 apt 交互弹窗
export DEBIAN_FRONTEND=noninteractive
mkdir -p /etc/needrestart/conf.d
echo "\$nrconf{restart} = 'a';" > /etc/needrestart/conf.d/99-xray-auto.conf

# === 1. 系统级更新 ===
rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*
execute_task "apt-get update -qq"  "  刷新软件源"
execute_task "DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' upgrade" "  系统组件升级"

# === 2. 依赖安装 ===
DEPENDENCIES=("curl" "wget" "tar" "unzip" "fail2ban" "rsyslog" "chrony" "iptables" "iptables-persistent" "qrencode" "jq" "cron" "python3-systemd" "lsof")

echo -e "${INFO} 正在检查并安装系统依赖..."
for pkg in "${DEPENDENCIES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        echo -e "${OK}   依赖已就绪: $pkg"
        continue
    fi

    execute_task "apt-get install -y $pkg" "  安装依赖: $pkg"
    
    # 二次校验与修复
    if ! dpkg -s "$pkg" &>/dev/null; then
        echo -e "${WARN} 依赖 $pkg 安装校验失败！尝试修复源..."
        apt-get update -qq --fix-missing
        execute_task "apt-get install -y $pkg" "重试安装: $pkg"
        
        if ! dpkg -s "$pkg" &>/dev/null; then
            echo -e "${ERR} [FATAL] 核心依赖无法安装: $pkg"
            echo -e "${YELLOW}请检查您的软件源 (apt sources) 是否正常。${PLAIN}"
            exit 1
        fi
    fi
done

# === 3. Xray 核心安装 ===
install_xray_robust() {
    local max_tries=3
    local count=0
    local bin_path="/usr/local/bin/xray"
    local VER_ARG=""
    
    if [ -n "$FIXED_VER" ]; then
        VER_ARG="--version $FIXED_VER"
        echo -e "${INFO} 已启用版本锁定: ${YELLOW}${FIXED_VER}${PLAIN}"
    fi
    
    mkdir -p /usr/local/share/xray/

    while [ $count -lt $max_tries ]; do
        if [ $count -gt 0 ]; then desc="  安装 Xray Core (第 $((count+1)) 次尝试)"; else desc="  安装 Xray Core"; fi
        
        # 使用官方标准安装脚本 (直连 github raw)
        local install_cmd="bash -c \"\$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)\" @ install --without-geodata $VER_ARG"
        
        if execute_task "$install_cmd" "$desc"; then
            if [ -f "$bin_path" ] && "$bin_path" version &>/dev/null; then
                local ver=$("$bin_path" version | head -n 1 | awk '{print $2}')
                echo -e "${OK}   Xray 核心校验通过: ${GREEN}${ver}${PLAIN}"
                return 0
            fi
        fi
        
        echo -e "${WARN} 安装/校验失败，清理环境后重试..."
        rm -rf "$bin_path" "/usr/local/share/xray/"
        ((count++))
        sleep 2
    done
    
    echo -e "${ERR} [FATAL] Xray Core 安装最终失败！请检查网络连接。"
    exit 1
}

install_xray_robust

# === 4. GeoData 核心数据库安装 ===
install_geodata_robust() {
    local share_dir="/usr/local/share/xray"
    local bin_dir="/usr/local/bin"
    mkdir -p "$share_dir"
    
    declare -A files
    files["geoip.dat"]="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
    files["geosite.dat"]="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

    echo -e "${INFO} 开始下载规则数据库 (GeoIP + Geosite)..."

    for name in "${!files[@]}"; do
        local url="${files[$name]}"
        local file_path="$share_dir/$name"
        local link_path="$bin_dir/$name"

        execute_task "curl -L -o $file_path $url" "  下载 $name"

        local fsize=$(du -k "$file_path" 2>/dev/null | awk '{print $1}')
        if [ ! -f "$file_path" ] || [ -z "$fsize" ] || [ "$fsize" -lt 50 ]; then
            echo -e "${WARN} $name 文件校验失败 (Size: ${fsize}KB)，尝试重试..."
            rm -f "$file_path"
            execute_task "curl -L -o $file_path $url" "  重试下载 $name"
        fi

        ln -sf "$file_path" "$link_path"
    done

    # === 配置自动更新任务 ===
    # 每周日凌晨 4:00 更新
    local update_cmd="curl -L -o $share_dir/geoip.dat ${files[geoip.dat]} && curl -L -o $share_dir/geosite.dat ${files[geosite.dat]} && /usr/bin/systemctl restart xray"
    local cron_job="0 4 * * 0 $update_cmd >/dev/null 2>&1"
    
    if ! command -v crontab &>/dev/null; then apt-get install -y cron &>/dev/null; fi
    (crontab -l 2>/dev/null | grep -v 'geoip.dat' | grep -v 'geosite.dat'; echo "$cron_job") | crontab -
    
    echo -e "${OK}   GeoData 安装完毕，并自动更新 (每周日 4:00)"
}

install_geodata_robust

echo -e "${OK}   核心组件安装完毕 (Core Install Completed)。\n"
