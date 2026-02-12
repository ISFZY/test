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

# 2. 标准化日志前缀 (核心修改：增加空格补位，强制对齐 [INFO])
# [INFO] = 6字符
# [WARN] = 6字符
# [ERR]  = 5字符 -> 补1空格
# [OK]   = 4字符 -> 补2空格
INFO="${BLUE}[INFO]${PLAIN}"
WARN="${YELLOW}[WARN]${PLAIN}"
ERR="${RED}[ERR] ${PLAIN}"
OK="${GREEN}[OK]  ${PLAIN}"

# 3 Linux 等待动画 (| / - \)
UI_SPINNER_FRAMES=("|" "/" "-" "\\")

# 4. 基础日志函数
log_info() { echo -e "${INFO} $*"; }
log_warn() { echo -e "${WARN} $*"; }
log_err()  { echo -e "${ERR} $*" >&2; }

# 5. 任务执行函数 (Execute Task)
execute_task() {
    local cmd="$1"
    local desc="$2"
    
    # 打印开始提示
    echo -ne "${INFO} ${desc}..."
    
    local err_log=$(mktemp)
    
    if eval "$cmd" >/dev/null 2>$err_log; then
        rm -f "$err_log"
        # 成功：[OK] 自带了2个空格，这里只需接1个空格即可对齐
        echo -e "\r${OK} ${desc}                    "
        return 0
    else
        # 失败
        echo -e "\r${ERR} ${desc} [FAILED]"
        echo -e "${RED}=== 错误详情 ===${PLAIN}"
        cat "$err_log"
        echo -e "${RED}================${PLAIN}"
        rm -f "$err_log"
        
        echo -e "${RED}[FATAL] 脚本执行中断。${PLAIN}"
        exit 1
    fi
}

# 6. Banner 展示
print_banner() {
    clear
    echo -e "${BLUE}======================================================${PLAIN}"
    echo -e "${BLUE}       Xray 全自动部署脚本 (Auto Installer)           ${PLAIN}"
    echo -e "${BLUE}======================================================${PLAIN}"
    echo -e "  ${GREEN}架构设计 :${PLAIN} Modular & Robust"
    echo -e "  ${GREEN}适配系统 :${PLAIN} Debian 10+ / Ubuntu 20+"
    echo -e "${BLUE}======================================================${PLAIN}"
    echo ""
}

# 7. 简单的锁机制
check_lock() {
    local lock_file="/tmp/xray_install.lock"
    if [ -f "$lock_file" ]; then
        local pid=$(cat "$lock_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${ERR} 检测到脚本正在运行 (PID: $pid)，请勿重复执行！"
            exit 1
        else
            rm -f "$lock_file"
        fi
    fi
    echo $$ > "$lock_file"
    trap 'rm -f "/tmp/xray_install.lock"; exit' INT TERM EXIT
}
