#!/bin/bash
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; PLAIN="\033[0m"

# 0. 权限检测
if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi

# --- 辅助函数：交互优化 ---

# 1. 动态清空行并报错
print_error() {
    local msg="$1"
    # \r 回到行首 -> \033[K 清除行 -> 打印红字 -> 暂停 -> 清除
    printf "\r\033[K${RED}%s${PLAIN}" "$msg"
    sleep 1.5
    printf "\r\033[K"
}

# 2. 严格的整数输入获取
# 参数: $1=提示语, $2=变量名(引用), $3=最小值, $4=最大值
get_valid_int() {
    local prompt="$1"
    local __resultvar=$2
    local min=${3:-0}
    local max=${4:-999999}
    local input_val

    while true; do
        read -p "$prompt" input_val
        
        # 处理默认值逻辑 (如果输入为空)
        if [ -z "$input_val" ]; then
            eval $__resultvar="DEFAULT"
            return 0
        fi

        # 校验: 是否为纯数字
        if [[ ! "$input_val" =~ ^[0-9]+$ ]]; then
            # 光标上移一行并清除，覆盖错误输入
            printf "\033[1A\033[K"
            print_error "错误：请输入有效的数字！"
            continue
        fi

        # 校验: 数值范围
        if [ "$input_val" -lt "$min" ] || [ "$input_val" -gt "$max" ]; then
            printf "\033[1A\033[K"
            print_error "错误：数值必须在 $min - $max 之间！"
            continue
        fi

        # 输入合法
        eval $__resultvar="'$input_val'"
        break
    done
}

# --- 核心功能 ---

# 获取当前状态
get_status() {
    # 1. 获取 Swap 大小
    SWAP_TOTAL=$(free -m | grep Swap | awk '{print $2}')
    if [ "$SWAP_TOTAL" -eq 0 ]; then
        STATUS_SWAP="${RED}未启用${PLAIN}"
    else
        STATUS_SWAP="${GREEN}已启用 (${SWAP_TOTAL}MB)${PLAIN}"
    fi

    # 2. 获取 Swappiness 值 (优先使用 sysctl，失败则读取文件)
    SWAPPINESS=$(sysctl -n vm.swappiness 2>/dev/null)
    if [ -z "$SWAPPINESS" ]; then
        SWAPPINESS=$(cat /proc/sys/vm/swappiness 2>/dev/null)
    fi
    
    # 兜底：如果依然获取不到，显示未知
    if [ -z "$SWAPPINESS" ]; then
        SWAPPINESS="${RED}读取失败${PLAIN}"
    fi
}

# 添加 Swap
add_swap() {
    echo -e "\n${BLUE}正在创建 Swap 分区...${PLAIN}"
    
    local swap_size
    while true; do
        get_valid_int "请输入 Swap 大小 (MB) [回车默认 1024]: " swap_size 1 65536
        if [ "$swap_size" == "DEFAULT" ]; then
            swap_size=1024
            break
        else
            break
        fi
    done

    # 清理旧的
    if [ -f /swapfile ]; then 
        echo -e "${YELLOW}发现旧 Swap，正在清理...${PLAIN}"
        swapoff /swapfile 2>/dev/null
        rm -f /swapfile
    fi

    # 创建新的
    echo -e "${BLUE}正在分配空间 (大小: ${swap_size}MB)...${PLAIN}"
    fallocate -l ${swap_size}M /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    # 写入 fstab (持久化)
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    # 检查配置文件中是否已经存在 vm.swappiness 设置
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        # 获取当前内核中的值 (如果获取失败则默认为 60)
        current_swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo 60)
        
        echo "vm.swappiness = $current_swappiness" >> /etc/sysctl.conf
        echo -e "${GREEN}检测到配置文件未设置 Swappiness，已自动固化当前值 ($current_swappiness) 到配置文件。${PLAIN}"
    else
        # 如果已经存在，不覆盖
        echo -e "${YELLOW}检测到配置文件已存在 Swappiness 设置，跳过自动添加。${PLAIN}"
    fi

    echo -e "${GREEN}成功创建 ${swap_size}MB Swap！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 删除 Swap (联动调整 Swappiness)
del_swap() {
    echo -e "\n${YELLOW}正在删除 Swap...${PLAIN}"
    swapoff /swapfile 2>/dev/null
    rm -f /swapfile
    # 从 fstab 移除
    sed -i '/\/swapfile/d' /etc/fstab
    
    echo -e "${GREEN}Swap 分区已删除。${PLAIN}"
    
    # 恢复 Swappiness 默认值
    echo -e "${BLUE}正在重置 Swappiness 亲和度为默认值 (60)...${PLAIN}"
    sysctl -w vm.swappiness=60 >/dev/null
    if grep -q "vm.swappiness" /etc/sysctl.conf; then
        sed -i "s/^vm.swappiness.*/vm.swappiness = 60/" /etc/sysctl.conf
    else
        echo "vm.swappiness = 60" >> /etc/sysctl.conf
    fi
    echo -e "${GREEN}Swappiness 已重置。${PLAIN}"

    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 调整 Swappiness
set_swappiness() {
    echo -e "\n${BLUE}当前亲和度 (Swappiness): ${YELLOW}${SWAPPINESS}${PLAIN}"
    echo -e "说明: 值越小(0-10)，越倾向于使用物理内存。"
    echo -e "      值越大(60-100)，越倾向于使用硬盘交换。"
    echo -e "------------------------------------------------"
    
    local new_val
    while true; do
        get_valid_int "请输入新的值 [0-100] (默认: 60): " new_val 0 100
        if [ "$new_val" == "DEFAULT" ]; then
            new_val=60
            break
        else
            break
        fi
    done

    # 临时生效
    sysctl -w vm.swappiness=$new_val >/dev/null
    
    # 永久生效 (修改 /etc/sysctl.conf)
    if grep -q "vm.swappiness" /etc/sysctl.conf; then
        sed -i "s/^vm.swappiness.*/vm.swappiness = $new_val/" /etc/sysctl.conf
    else
        echo "vm.swappiness = $new_val" >> /etc/sysctl.conf
    fi
    echo -e "${GREEN}设置成功！当前亲和度已改为: ${new_val}${PLAIN}"
    
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# --- 主菜单 ---
while true; do
    clear
    get_status
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}           虚拟内存管理 (Swap Manager)            ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  Swap 状态   : ${STATUS_SWAP}"
    echo -e "  Swappiness  : ${YELLOW}${SWAPPINESS}${PLAIN}"
    echo -e "---------------------------------------------------"
    echo -e "  1. 添加 / 修改 Swap"
    echo -e "  2. 关闭 / 删除 Swap (并重置 Swappiness)"
    echo -e "---------------------------------------------------"
    echo -e "  3. 调整 Swappiness 亲和度 (性能优化)"
    echo -e "---------------------------------------------------"
    echo -e "  0. 退出"
    echo -e ""
    
    # 循环读取输入，直到输入正确
    while true; do
        read -p "请输入选项 [0-3]: " choice
        case "$choice" in
            0|1|2|3)
                break
                ;;
            *)
                # 错误处理：原地报错
                print_error "输入错误：只能输入 0-3 之间的数字！"
                ;;
        esac
    done

    # 执行逻辑
    case "$choice" in
        1) add_swap ;;
        2) del_swap ;;
        3) set_swappiness ;;
        0) clear; exit 0 ;;
        *) ;;
    esac
done
