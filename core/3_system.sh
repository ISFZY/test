# --- 3. 安全与防火墙配置 ---
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
    
    # 2. 设定默认端口 (静默模式)
    PORT_VISION=443
    PORT_XHTTP=8443
    
    # [冲突检测] 如果 443 端口被占用 (如 Nginx)，自动切换到 4443
    if lsof -i:443 -P -n | grep -q LISTEN; then
        echo -e "${WARN} 检测到 443 端口被占用，Vision 端口自动切换为 4443"
        PORT_VISION=4443
    fi

    echo -e "${OK}   SSH    端口 : ${GREEN}$SSH_PORT${PLAIN}"
    echo -e "${OK}   Vision 端口 : ${GREEN}$PORT_VISION${PLAIN}"
    echo -e "${OK}   XHTTP  端口 : ${GREEN}$PORT_XHTTP${PLAIN}"
    echo -e "${INFO} (如需修改端口，安装后请输入 'ports')"

    # Fail2ban 配置
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
bantime = 1d
maxretry = 3
[DEFAULT]
findtime = 7d
backend = auto
[sshd]
enabled = true
port = $SSH_PORT
mode = normal
EOF
    systemctl restart rsyslog >/dev/null 2>&1
    systemctl enable fail2ban >/dev/null 2>&1
    systemctl restart fail2ban >/dev/null 2>&1
    echo -e "${OK}   Fail2ban 防护已启用"

    # 防火墙规则
    _add_fw_rule $SSH_PORT $HAS_V4 $HAS_V6
    _add_fw_rule $PORT_VISION $HAS_V4 $HAS_V6
    _add_fw_rule $PORT_XHTTP $HAS_V4 $HAS_V6
    netfilter-persistent save >/dev/null 2>&1
}

setup_kernel_optimization() {
    echo -e "\n${BLUE}--- 4. 内核优化 (Kernel Opt) ---${PLAIN}"
    
    # 1. 自动开启 BBR
    echo "net.core.default_qdisc=fq" > /etc/sysctl.d/99-xray-bbr.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-xray-bbr.conf
    sysctl --system >/dev/null 2>&1
    echo -e "${OK}   BBR 加速已启用"

    # 2. 自动 Swap
    local ram_size=$(free -m | awk '/Mem:/ {print $2}')
    if [ "$ram_size" -lt 2048 ] && ! grep -q "/swapfile" /proc/swaps; then
        echo -e "${INFO} 内存不足 2GB，正在配置 1GB Swap..."
        dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null 2>&1
        swapon /swapfile
        if ! grep -q "/swapfile" /etc/fstab; then echo "/swapfile none swap sw 0 0" >> /etc/fstab; fi
        echo -e "${OK}   Swap 已自动启用"
    fi
}
