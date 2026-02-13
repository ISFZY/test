#!/bin/bash
# ------------------------------------------------------------------
# Utils: 通用工具库
# ------------------------------------------------------------------

# 1. 颜色与 UI 定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 2. 标准化日志前缀 (空格补位，强制对齐 [INFO])
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
        # 成功
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

AUTHOR="ISFZY"
PROJECT_URL="https://github.com/ISFZY/Xray-Auto"

print_banner() {
    clear
    echo -e "${BLUE}===============================================================${PLAIN}"
    echo -e "${BLUE}          Xray Auto Installer                                 ${PLAIN}"
    echo -e "${BLUE}===============================================================${PLAIN}"
    echo -e "${BLUE}AUTHOR  :${PLAIN} ${AUTHOR}"
    echo -e "${BLUE}PROJECT :${PLAIN} ${PROJECT_URL}"
    echo -e "${BLUE}===============================================================${PLAIN}"
    echo ""
}
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

# 8. 交互确认函数
confirm_installation() {
    echo -e "${YELLOW}即将开始安装 Xray 服务...${PLAIN}"
    
    local prompt_msg="确认继续安装? [y/n]: "
    
    while true; do
        # 1. 打印提示符 (-n 不换行)
        echo -ne "${prompt_msg}"
        
        # 2. 读取单个字符 (-n 1)，静默模式 (-s)
        read -n 1 -s key
        
        # 3. 判定逻辑
        case "$key" in
            y|Y)
                # 输入正确：手动显示字符并换行
                echo "y"
                echo -e "${INFO} 用户确认，开始执行..." 
                break 
                ;;
            n|N)
                echo "n"
                echo -e "${WARN} 用户取消安装。"
                exit 1 
                ;;
            *)
                # === 错误处理核心 ===
                # A. \r 回到行首
                # B. \033[K 清除整行
                # C. 打印红色的报错信息
                echo -ne "\r\033[K"
                echo -e "${RED}[错误] 输入无效 '${key}' (只能输入 y 或 n)${PLAIN}"
                
                # D. 循环继续
                ;;
        esac
    done
}
