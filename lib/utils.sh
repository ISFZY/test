#!/bin/bash
# ------------------------------------------------------------------
# Utils: 通用工具库 (极简版)
# ------------------------------------------------------------------

# 1. 颜色与 UI 定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 2. 标准化日志前缀
INFO="${BLUE}[INFO]${PLAIN}"
OK="${GREEN}[OK]${PLAIN}"
ERR="${RED}[ERR]${PLAIN}"
WARN="${YELLOW}[WARN]${PLAIN}"

# 3 简单的旋转动画
# Linux 等待动画： | / - \
UI_SPINNER_FRAMES=("|" "/" "-" "\\")

# 4. 基础日志函数
log_info() { echo -e "${INFO} $*"; }
log_warn() { echo -e "${WARN} $*"; }
log_err()  { echo -e "${ERR} $*" >&2; }

# 5. 任务执行函数 (Execute Task)
# 用法: execute_task "命令" "描述"
# 功能: 执行命令，成功显示 [OK]，失败显示 [ERR] 并终止脚本
execute_task() {
    local cmd="$1"
    local desc="$2"
    
    # 打印开始提示 (不换行，制造 pending 效果)
    echo -ne "${INFO} ${desc}..."
    
    # 将错误输出捕获到临时文件，以便失败时显示
    local err_log=$(mktemp)
    
    if eval "$cmd" >/dev/null 2>$err_log; then
        # 成功：清除该行，打印绿色 OK
        rm -f "$err_log"
        echo -e "\r${OK} ${desc}                    "
        return 0
    else
        # 失败：换行，打印红色 ERR，并输出错误日志
        echo -e "\r${ERR} ${desc} [FAILED]"
        echo -e "${RED}=== 错误详情 ===${PLAIN}"
        cat "$err_log"
        echo -e "${RED}================${PLAIN}"
        rm -f "$err_log"
        
        # 严重错误直接退出，保证原子性
        echo -e "${RED}[FATAL] 脚本执行中断。${PLAIN}"
        exit 1
    fi
}

# 6. Banner 展示
# 基础信息配置
AUTHOR="ISFZY"
PROJECT_URL="https://github.com/ISFZY/Xray-Auto"

print_banner() {
    clear
    echo -e "${BLUE}===============================================================${PLAIN}"
    echo -e "${BLUE}           Xray Auto Installer ${YELLOW}${PLAIN}"
    echo -e "${BLUE}===============================================================${PLAIN}"
    echo -e "  ${GREEN}作    者 :${PLAIN} ${AUTHOR}"
    echo -e "  ${GREEN}项目地址 :${PLAIN} ${PROJECT_URL}"
    echo -e "${BLUE}===============================================================${PLAIN}"
    echo ""
}

# 7. 简单的锁机制 (防止并发运行)
check_lock() {
    local lock_file="/tmp/xray_install.lock"
    
    # 检查锁文件是否存在且进程是否在运行
    if [ -f "$lock_file" ]; then
        local pid=$(cat "$lock_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${ERR} 检测到脚本正在运行 (PID: $pid)，请勿重复执行！"
            exit 1
        else
            # 锁文件存在但进程已死 (Stale Lock)，清理
            rm -f "$lock_file"
        fi
    fi
    
    # 创建新锁
    echo $$ > "$lock_file"
    
    # 脚本退出时自动删除锁
    trap 'rm -f "/tmp/xray_install.lock"; exit' INT TERM EXIT
}

confirm_installation() {
    echo -e "${YELLOW}注意：本脚本将安装 Xray 及相关依赖，并可能修改系统配置。${PLAIN}"
    echo -e "${YELLOW}Note: This script will install Xray and modify system config.${PLAIN}"
    echo ""
    
    # -p 显示提示信息
    read -p "确认继续安装吗? [y/n] (Confirm to install?): " choice
    
    # 判断用户输入
    case "$choice" in
        y|Y) 
            echo -e "${GREEN}>>> 用户确认，开始安装...${PLAIN}"
            echo ""
            ;;
        *) 
            echo -e "${RED}>>> 用户取消，安装已终止。${PLAIN}"
            exit 1
            ;;
    esac
}
