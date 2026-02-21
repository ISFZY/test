#!/bin/bash

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
GRAY="\033[90m"
PLAIN="\033[0m"

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: 请使用 sudo 或 root 用户运行此脚本！${PLAIN}"
    exit 1
fi

CONFIG_FILE="/usr/local/etc/xray/config.json"

clear
echo -e "${RED}=============================================================${PLAIN}"
echo -e "${RED}               Xray 一键卸载 (Uninstall Xray)               ${PLAIN}"
echo -e "${RED}=============================================================${PLAIN}"
echo -e "${YELLOW}警告：第一阶段将执行 Xray 核心及面板组件的彻底清理。${PLAIN}"
echo -e "  1. 停止并移除 Xray 服务及其配置"
echo -e "  2. 智能清理当初为您开放的防火墙随机端口"
echo -e "  3. 删除所有管理快捷指令 (info, user 等 15 个脚本)"
echo -e "  4. 清理 GeoData 定时更新任务与 Systemd 覆写残留"
echo -e "${RED}=============================================================${PLAIN}"
echo ""

# --- 第一阶段交互确认 ---
while true; do
    read -p "确认要卸载 Xray 核心及应用组件吗？[y/n]: " key
    case "$key" in
        [yY]) 
            echo -e "\n${GREEN}>>> 操作已确认，开始应用层卸载...${PLAIN}"
            break 
            ;;
        [nN]) 
            echo -e "\n${YELLOW}>>> 操作已取消。${PLAIN}"
            exit 0 
            ;;
        *) 
            # 动态擦除报错，保持界面整洁
            echo -e "\033[1A\033[K${RED}错误：必须输入 y 或 n ${PLAIN}"
            ;;
    esac
done

# --- 1. 动态清理防火墙端口 ---
echo -e "${GREEN}>>> 正在清理防火墙放行的端口...${PLAIN}"
if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
    # 在删除配置前，先提取当初生成的端口
    PORT_VISION=$(jq -r '.inbounds[] | select(.tag=="vision_node") | .port // empty' "$CONFIG_FILE" 2>/dev/null)
    PORT_XHTTP=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .port // empty' "$CONFIG_FILE" 2>/dev/null)
    
    _del_fw() {
        local port=$1
        if [ -n "$port" ]; then
            iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
            iptables -D INPUT -p udp --dport $port -j ACCEPT 2>/dev/null
            if [ -f /proc/net/if_inet6 ]; then
                ip6tables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
                ip6tables -D INPUT -p udp --dport $port -j ACCEPT 2>/dev/null
            fi
            echo -e "   [OK] 已关闭防火墙端口: $port"
        fi
    }
    _del_fw "$PORT_VISION"
    _del_fw "$PORT_XHTTP"
    
    # 保存防火墙规则
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save >/dev/null 2>&1
    fi
else
    echo -e "   [WARN] 无法读取配置文件，跳过端口清理。"
fi

# --- 2. 停止并删除应用 ---
echo -e "${GREEN}>>> 正在停止并移除服务...${PLAIN}"
systemctl stop xray >/dev/null 2>&1
systemctl disable xray >/dev/null 2>&1

rm -f /etc/systemd/system/xray.service
rm -f /lib/systemd/system/xray.service
# 填补漏洞：移除 systemd 覆写文件夹
rm -rf /etc/systemd/system/xray.service.d

if [ -d "/usr/local/etc/xray" ]; then
    rm -rf "/usr/local/etc/xray"
    echo -e "   [OK] 已删除配置目录 (/usr/local/etc/xray)"
fi

rm -f /usr/local/bin/xray
rm -rf /usr/local/share/xray
rm -rf /var/log/xray
echo -e "   [OK] 已删除核心程序、数据与日志"

# --- 3. 删除工具脚本 ---
TOOLS=("user" "backup" "sniff" "info" "zone" "net" "bbr" "bt" "f2b" "ports" "sni" "swap" "xw" "updata" "remove" "uninstall")
echo -e "${GREEN}>>> 正在清理快捷指令...${PLAIN}"
for tool in "${TOOLS[@]}"; do
    if [ -f "/usr/local/bin/$tool" ]; then
        rm -f "/usr/local/bin/$tool"
    fi
done
echo -e "   [OK] 已清理全部管理面板指令"

# --- 4. 清理定时任务与残留 ---
if command -v crontab &>/dev/null; then
    crontab -l 2>/dev/null | grep -v "geoip.dat" | grep -v "geosite.dat" | crontab -
    echo -e "   [OK] 已清理 GeoData 定时更新任务"
fi
rm -f /etc/needrestart/conf.d/99-xray-auto.conf 2>/dev/null

systemctl daemon-reload
systemctl reset-failed

if [ -d "/root/xray-install" ]; then
    rm -rf "/root/xray-install"
fi

# 第二阶段：系统环境复原
echo -e "\n${BLUE}=============================================================${PLAIN}"
echo -e "${BLUE}          第二阶段：系统环境深度复原 (Optional)              ${PLAIN}"
echo -e "${BLUE}=============================================================${PLAIN}"
echo -e "${YELLOW}检测到系统层面存在 Xray-Auto 的全局网络与性能优化痕迹。${PLAIN}"
echo -e "若您的服务器将用于建站或其他业务，保留它们(BBR/Swap/Fail2ban)是有益的。"
echo -e "如果需要彻底清除，您可以选择继续深度复原：\n"
echo -e "  - ${GRAY}删除虚拟内存${PLAIN} (/swapfile)"
echo -e "  - ${GRAY}移除 BBR 优化配置${PLAIN} (恢复系统默认网络队列)"
echo -e "  - ${GRAY}恢复网络优先级${PLAIN} (重置 IPv4/IPv6 双栈策略)"
echo -e "  - ${GRAY}卸载 WARP 客户端${PLAIN} (若已安装)"
echo -e "  - ${GRAY}清除 Fail2ban 配置${PLAIN} (恢复默认防爆破策略)"
echo -e "${BLUE}-------------------------------------------------------------${PLAIN}"

# --- 第二阶段交互确认 ---
while true; do
    read -p "是否执行系统环境深度复原？[y/n]: " sys_key
    case "$sys_key" in
        [yY]) 
            echo -e "\n${GREEN}>>> 开始执行系统环境复原...${PLAIN}"
            
            # 1. 虚拟内存
            if [ -f /swapfile ]; then
                echo -e "   [-] 正在关闭并删除 Swap 分区..."
                swapoff /swapfile 2>/dev/null
                rm -f /swapfile
                sed -i '/\/swapfile/d' /etc/fstab
            fi
            sysctl -w vm.swappiness=60 >/dev/null 2>&1
            sed -i "s/^vm.swappiness.*/vm.swappiness = 60/" /etc/sysctl.conf 2>/dev/null
            
            # 2. BBR
            if [ -f /etc/sysctl.d/99-xray-bbr.conf ]; then
                echo -e "   [-] 正在移除 BBR 优化配置..."
                rm -f /etc/sysctl.d/99-xray-bbr.conf
                sysctl --system >/dev/null 2>&1
            fi

            # 3. 网络优先级 (gai.conf & sysctl ipv6)
            echo -e "   [-] 正在恢复网络优先级与 IPv6 状态..."
            sed -i '/^precedence ::ffff:0:0\/96  100/d' /etc/gai.conf 2>/dev/null
            sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
            sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1
            sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf 2>/dev/null

            # 4. WARP
            if command -v warp &>/dev/null; then
                echo -e "   [-] 正在卸载 WARP 客户端..."
                warp u >/dev/null 2>&1
            fi

            # 5. Fail2ban
            if [ -f /etc/fail2ban/jail.local ]; then
                echo -e "   [-] 正在移除自定义 Fail2ban 规则..."
                rm -f /etc/fail2ban/jail.local
                systemctl restart fail2ban >/dev/null 2>&1
            fi

            echo -e "${GREEN}>>> 深度复原已完成。${PLAIN}"
            break
            ;;
        [nN]) 
            echo -e "\n${YELLOW}>>> 跳过深度复原，保留系统级优化。${PLAIN}"
            break
            ;;
        *) 
            echo -e "\033[1A\033[K${RED}错误：必须输入 y 或 n ${PLAIN}"
            ;;
    esac
done

echo -e "\n${GREEN}=============================================================${PLAIN}"
echo -e "${GREEN}                卸载全部完成 (Done)                          ${PLAIN}"
echo -e "${GREEN}=============================================================${PLAIN}\n"

