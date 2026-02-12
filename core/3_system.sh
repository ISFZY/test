# --- 3. 安全与防火墙配置 ---

# [辅助函数] 获取一个未被占用的随机高位端口 (10000-65535)
get_random_port() {
    local port
    while true; do
        # 生成 10000 到 65535 之间的随机数
        port=$(shuf -i 10000-65535 -n 1)
        
        # 使用 lsof 检查端口是否被占用
        if ! lsof -i:$port -P -n >/dev/null 2>&1; then
            echo "$port"
            return 0
        fi
    done
}

_add_fw_rule() {
    local port=$1; local v4=$2; local v6=$3
    if [ "$v4" = true ]; then
        iptables -C INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport $port -j ACCEPT
        iptables -C INPUT -p udp --dport $port -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport $port -j ACCEPT
    fi
    if [ "$v6" = true ] && [ -f /proc/net/if_inet6 ]; then
        ip6tables -C INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null || ip6tables -A INPUT -p tcp --dport $port -j ACCEPT
        ip6tables -C INPUT -p udp --dport $port -j ACCEPT 2>/dev/null || ip6tables -A INPUT -p udp --dport $port -j ACCEPT
    fi
}

setup_firewall_and_security() {
    echo -e "\n${BLUE}--- 3. 端口与安全 (Security) ---${PLAIN}"
    
    # 1. 自动获取 SSH 端口
    local current_ssh_port=$(grep "^Port" /etc/ssh/sshd_config | head -n 1 | awk '{print $2}' | tr -d '\r')
    SSH_PORT=${current_ssh_port:-22}
    
    # 2. 分配随机高位端口
    echo -e "${INFO} 正在分配随机高位端口..."
    
    # 分配 Vision 端口 (显式避开 SSH 端口)
    while true; do
        PORT_VISION=$(get_random_port)
        if [ "$PORT_VISION" != "$SSH_PORT" ]; then
            break
        fi
    done
    
    # 分配 XHTTP 端口 (显式避开 SSH 和 Vision 端口)
    while true; do
        PORT_XHTTP=$(get_random_port)
        if [ "$PORT_XHTTP" != "$PORT_VISION" ] && [ "$PORT_XHTTP" != "$SSH_PORT" ]; then
            break
        fi
    done

    echo -e "${OK} SSH    端口 : ${GREEN}$SSH_PORT${PLAIN}"
    echo -e "${OK} Vision 端口 : ${GREEN}$PORT_VISION${PLAIN} (随机/Random)"
    echo -e "${OK} XHTTP  端口 : ${GREEN}$PORT_XHTTP${PLAIN} (随机/Random)"
    echo -e "${INFO} (请务必记录以上端口信息)"

    # 3. 写入 Fail2ban 初始配置
    # 确保 f2b.sh 面板打开时能读到正确的默认参数 (指数封禁 + 随机端口应用)
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
# --- 基础设置 ---
ignoreip = 127.0.0.1/8 ::1
bantime = 1d
findtime = 1d
maxretry = 3

# --- 指数封禁设置 (默认开启) ---
bantime.increment = true
bantime.factor = 1
bantime.maxtime = 5w

# --- 系统设置 ---
backend = systemd
mode = normal

[sshd]
enabled = true
port = $SSH_PORT
EOF

    # 重启 Fail2ban 服务
    systemctl unmask fail2ban >/dev/null 2>&1
    systemctl enable fail2ban >/dev/null 2>&1
    systemctl restart fail2ban >/dev/null 2>&1
    echo -e "${OK} Fail2ban 已启用 (默认策略: 指数递增封禁)"

    # 4. 防火墙放行 (应用随机端口)
    _add_fw_rule $SSH_PORT $HAS_V4 $HAS_V6
    _add_fw_rule $PORT_VISION $HAS_V4 $HAS_V6
    _add_fw_rule $PORT_XHTTP $HAS_V4 $HAS_V6
    
    # 5. 持久化防火墙规则
    netfilter-persistent save >/dev/null 2>&1
    echo -e "${OK} 防火墙规则已持久化保存"
}

setup_kernel_optimization() {
    echo -e "\n${BLUE}--- 4. 内核优化 (Kernel Opt) ---${PLAIN}"
    
    # 1. 自动开启 BBR
    # 写入配置到 sysctl
    echo "net.core.default_qdisc=fq" > /etc/sysctl.d/99-xray-bbr.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-xray-bbr.conf
    # 应用配置
    sysctl --system >/dev/null 2>&1
    echo -e "${OK} BBR 加速已启用"
}
