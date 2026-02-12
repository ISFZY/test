#!/bin/bash

# ==================================================================
# 1. 基础准备
# ==================================================================
BASE_DIR=$(cd "$(dirname "$0")" && pwd)

if [ -f "$BASE_DIR/lib/utils.sh" ]; then
    source "$BASE_DIR/lib/utils.sh"
else
    echo "Error: lib/utils.sh not found!"
    exit 1
fi

# ==================================================================
# 2. 预检与交互
# ==================================================================
print_banner
if [ "$EUID" -ne 0 ]; then echo -e "${RED}Error: 请使用 root 运行！${PLAIN}"; exit 1; fi

# 锁机制检查
if command -v lock_acquire &> /dev/null; then
    if ! lock_acquire; then echo -e "${RED}脚本已在运行！${PLAIN}"; exit 1; fi
fi

# 确认安装
confirm_installation

# ==================================================================
# 3. 核心安装流程 (Core Modules)
# ==================================================================
echo -e "${BLUE}>>> 正在初始化环境...${PLAIN}"

# --- 1. 环境准备 ---
source "$BASE_DIR/core/1_env.sh"
pre_flight_check
check_net_stack
setup_timezone

# --- 2. 安装核心 ---
source "$BASE_DIR/core/2_install.sh"
# 兼容处理：如果 2_install.sh 封装了函数则调用，否则假设它source时已自动执行
if command -v core_install &>/dev/null; then
    core_install
fi

# --- 3. 系统配置 ---
source "$BASE_DIR/core/3_system.sh"
# 自动设置防火墙、默认端口(443/8443)、BBR、Swap
# 注意：此函数会导出 PORT_VISION 和 PORT_XHTTP 变量供后续使用
setup_firewall_and_security
setup_kernel_optimization

# --- 4. 生成配置 ---
source "$BASE_DIR/core/4_config.sh"
# 自动生成 UUID、密钥，使用步骤3确定的端口写入 config.json
core_config

# ==================================================================
# 4. 部署管理工具 (Tools)
# ==================================================================
echo -e "\n${BLUE}>>> 正在部署管理脚本...${PLAIN}"

TOOLS_DIR="$BASE_DIR/tools"
BIN_DIR="/usr/local/bin"

if [ -d "$TOOLS_DIR" ]; then
    count=$(ls "$TOOLS_DIR"/*.sh 2>/dev/null | wc -l)
    
    if [ "$count" != "0" ]; then
        for script in "$TOOLS_DIR"/*.sh; do
            if [ -f "$script" ]; then
                filename=$(basename "$script" .sh)
                target="$BIN_DIR/$filename"
                
                cp "$script" "$target"
                chmod +x "$target"
                echo -e "   ${OK} 部署命令: ${GREEN}${filename}${PLAIN}"
            fi
        done
    else
        echo -e "   ${WARN} tools 目录为空，跳过部署。"
    fi
else
    echo -e "   ${ERR} tools 目录缺失，请检查项目完整性。"
fi

# ==================================================================
# 5. 启动服务与收尾
# ==================================================================
echo -e "\n${GREEN}>>> 正在启动服务...${PLAIN}"

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

if [ $? -eq 0 ]; then
    # 自动显示 info
    if [ -f "/usr/local/bin/info" ]; then
        bash /usr/local/bin/info
    fi
else
    echo -e "\n${RED}Error: Xray 服务启动失败！${PLAIN}"
    echo -e "请检查日志: journalctl -u xray -n 20 --no-pager"
    exit 1
fi
