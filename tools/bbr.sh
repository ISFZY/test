#!/bin/bash

# 基础配置
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"
SYSCTL_CONF="/etc/sysctl.d/99-xray-bbr.conf"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi
clear

# 核心函数
get_status() {
    local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local qd=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    local has_file=0
    [ -f "$SYSCTL_CONF" ] && has_file=1

    # --- 1. 拥塞算法状态 (事实) ---
    if [[ "$cc" == "bbr" ]]; then
        STATUS_BBR="${GREEN}已开启 (BBR)${PLAIN}"
    else
        STATUS_BBR="${YELLOW}未开启 (${cc})${PLAIN}"
    fi

    # --- 2. 策略模式判定 ---
    if [[ "$cc" == "bbr" ]] && [ $has_file -eq 1 ]; then
        # 情况A: 脚本文件存在 + 内核是BBR -> 完美生效
        STATUS_MODE="${GREEN}Google 优化 (脚本管理)${PLAIN}"
        
    elif [[ "$cc" != "bbr" ]] && [ $has_file -eq 0 ]; then
        # 情况B: 无文件 + 不是BBR -> 这就是最标准的 Linux 默认
        STATUS_MODE="${GRAY}Linux 默认 (${cc})${PLAIN}"
        
    elif [[ "$cc" == "bbr" ]] && [ $has_file -eq 0 ]; then
        # 情况C: 无文件 + 内核是BBR -> 说明系统出厂就带 BBR
        STATUS_MODE="${GRAY}Linux 默认 (系统自带 BBR)${PLAIN}"
        
    else
        # 情况D: 有文件 + 不是BBR -> 也就是文件写了但没生效
        STATUS_MODE="${RED}配置异常 (未生效)${PLAIN}"
    fi

    # --- 3. 队列调度状态 ---
    # 只有在 Google 策略生效时，我们才严格检查 FQ
    if [[ "$STATUS_MODE" == *Google* ]]; then
        if [[ "$qd" == "fq" ]]; then
            STATUS_QDISC="${GREEN}FQ${PLAIN}"
        else
            STATUS_QDISC="${RED}${qd} (建议 FQ)${PLAIN}"
        fi
    else
        # 原生模式下，系统用什么就是什么，标灰即可
        STATUS_QDISC="${GRAY}${qd}${PLAIN}"
    fi
}

apply_sysctl() {
    echo -e "\n${BLUE}[INFO] 正在应用内核参数...${PLAIN}"
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
    echo -e "${GREEN}设置已生效！${PLAIN}"
    sleep 2
}

enable_bbr() {
    echo -e "\n${BLUE}正在应用 Google BBR 优化策略...${PLAIN}"
    modprobe tcp_bbr && modprobe sch_fq
    
    # 写入 Google BBR 标准配置
    cat > "$SYSCTL_CONF" <<CONF
# Google BBR Strategy
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
CONF
    apply_sysctl
}

disable_bbr() {
    echo -e "\n${BLUE}正在恢复 Linux 系统默认策略...${PLAIN}"
    rm -f "$SYSCTL_CONF"
    # 重载系统默认配置
    sysctl --system >/dev/null 2>&1
    echo -e "${GREEN}已恢复至 Linux 原生标准。${PLAIN}"
    sleep 2
}

# 主交互逻辑
while true; do
    get_status
    
    # 无闪烁重绘
    tput cup 0 0
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}          BBR 网络优化 (Network Manager)          ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  拥塞算法 : ${STATUS_BBR}\033[K"
    echo -e "  队列调度 : ${STATUS_QDISC}\033[K"
    echo -e "  当前策略 : ${STATUS_MODE}\033[K"
    echo -e "---------------------------------------------------"
    echo -e "  1. ${GREEN}Google 优化策略${PLAIN} (BBR + FQ)"
    echo -e "  2. ${YELLOW}Linux  默认策略${PLAIN} (Cubic + FQ_CODEL)"
    echo -e "---------------------------------------------------"
    echo -e "  0. 退出 (Exit)"
    echo -e ""
    
    # 清除下方残留
    tput ed

    while true; do
        echo -ne "\r\033[K请输入选项 [0-2]: "
        read -n 1 -s -r choice
        case "$choice" in
            1|2|0) break ;;
            *) echo -ne "\r\033[K${RED}输入无效...${PLAIN}"; sleep 0.5 ;;
        esac
    done

    case "$choice" in
        1) enable_bbr ;;
        2) disable_bbr ;;
        0) echo -e "\nbye."; exit 0 ;;
    esac
done
