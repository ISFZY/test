#!/bin/bash

# ==============================================================================
# Project: https://github.com/ISFZY/Xray-Auto
# Author : ISFZY
# ==============================================================================

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 定义安装目录
INSTALL_DIR="xray-install"
REPO_URL="https://github.com/ISFZY/Xray-Auto.git"

# 1. 分支选择逻辑 (Branch Selection)
#    优先读取用户传入的第一个参数 (例如: bash bootstrap.sh dev)
#    如果没有参数，默认使用 "main" 分支
TARGET_BRANCH="${VERSION:-${1:-main}}"

echo -e "${GREEN}>>> 准备安装分支/版本: ${YELLOW}${TARGET_BRANCH}${PLAIN}"

# 2. 环境检查与依赖安装 (Dependencies)

# 检查是否为 Root 用户
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: 请使用 sudo 或 root 用户运行此脚本！${PLAIN}"
    exit 1
fi

# ---------------- 新增：纯 IPv6 环境 GitHub 连通性修复 ----------------
# 简单的纯 v6 探测：如果 ping 不通 8.8.8.8，但能 ping 通 Cloudflare v6，则注入 DNS64
if ! ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
    if ping6 -c 1 -W 2 2606:4700:4700::1111 &> /dev/null; then
        echo -e "${YELLOW}检测到纯 IPv6 环境，正在配置 DNS64 (Trex) 以连接 GitHub 等 IPv4 资源...${PLAIN}"
        # 备份原有的 resolv.conf
        cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null
        # 写入免费且稳定的公共 DNS64
        echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2fac::1" > /etc/resolv.conf
    fi
fi

# 检查并安装 Git
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}检测到未安装 Git，正在自动安装...${PLAIN}"
    if [ -f /etc/debian_version ]; then
        apt-get update -y && apt-get install -y git
    elif [ -f /etc/redhat-release ]; then
        yum install -y git
    else
        echo -e "${RED}无法检测操作系统，请手动安装 git 后重试。${PLAIN}"
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        echo -e "${RED}Git 安装失败，请检查网络或源设置。${PLAIN}"
        exit 1
    fi
fi

# 3. 拉取代码 (Clone Repository)

# 清理旧目录
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}清理旧安装目录...${PLAIN}"
    rm -rf "$INSTALL_DIR"
fi

echo -e "${GREEN}>>> 正在拉取代码...${PLAIN}"

# 执行克隆
if git clone -b "${TARGET_BRANCH}" --depth 1 "$REPO_URL" "$INSTALL_DIR"; then
    echo -e "${GREEN}代码拉取成功！${PLAIN}"
else
    echo -e "${RED}代码拉取失败！${PLAIN}"
    echo -e "请检查分支名称 '${TARGET_BRANCH}' 是否存在，或检查网络连接。"
    exit 1
fi

# 4. 移交执行权 (Handover)

cd "$INSTALL_DIR" || exit 1

# 赋予权限
chmod +x install.sh
chmod +x core/*.sh 2>/dev/null
chmod +x lib/*.sh 2>/dev/null
chmod +x tools/*.sh 2>/dev/null

echo -e "${GREEN}>>> 启动安装程序...${PLAIN}"
echo ""

bash install.sh
