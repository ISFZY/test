#!/bin/bash

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
GRAY="\033[90m"
PLAIN="\033[0m"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi

XRAY_BIN="/usr/local/bin/xray"

update_core() {
    echo -e "\n${BLUE}>>> 正在请求官方脚本更新 Xray 核心...${PLAIN}"
    
    # 调用官方脚本执行平滑升级
    if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --without-geodata; then
        systemctl restart xray
        echo -e "\n${GREEN}>>> 核心更新成功！${PLAIN}"
        "$XRAY_BIN" version | head -n 1
    else
        echo -e "\n${RED}>>> 核心更新失败，请检查网络连接。${PLAIN}"
    fi
    
    echo ""
    read -p "按回车键返回主菜单..."
}

update_geodata() {
    echo -e "\n${BLUE}>>> 正在手动更新 GeoData 路由规则库...${PLAIN}"
    
    local share_dir="/usr/local/share/xray"
    local urls=(
        "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
        "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
    )
    
    local tmp_ip=$(mktemp)
    local tmp_site=$(mktemp)
    local max_retries=3
    local attempt=1
    local success=false
    
    # 增加业务层级的重试循环
    while [ $attempt -le $max_retries ]; do
        echo -e "   [-] 直连拉取 GeoData (尝试 $attempt/$max_retries) ..."
        
        # 纯直连下载
        curl -kL --retry 3 -o "$tmp_ip" "${urls[0]}"
        curl -kL --retry 3 -o "$tmp_site" "${urls[1]}"
        
        # 核心防线：文件大小校验 (大于 1000KB)
        local size_ip=$(du -k "$tmp_ip" | awk '{print $1}')
        local size_site=$(du -k "$tmp_site" | awk '{print $1}')
        
        if [ -n "$size_ip" ] && [ "$size_ip" -gt 1000 ] && [ -n "$size_site" ] && [ "$size_site" -gt 1000 ]; then
            success=true
            break # 校验通过，跳出重试循环
        else
            echo -e "   [WARN] 第 $attempt 次拉取失败 (文件损坏或过小)，准备重试..."
            sleep 2 # 停顿 2 秒防屏蔽
            attempt=$((attempt + 1))
        fi
    done
    
    # 循环结束后，判断最终结果
    if [ "$success" = true ]; then
        echo -e "${OK} 校验通过，正在应用新规则..."
        mv -f "$tmp_ip" "$share_dir/geoip.dat"
        mv -f "$tmp_site" "$share_dir/geosite.dat"
        chmod 644 "$share_dir"/*.dat
        
        systemctl restart xray
        echo -e "\n${GREEN}>>> GeoData 更新完成！服务已重启以加载新规则。${PLAIN}"
    else
        echo -e "\n${RED}>>> 更新失败：连续 $max_retries 次拉取均异常！${PLAIN}"
        echo -e "${YELLOW}已自动拦截损坏的规则库，当前 Xray 服务不受影响。${PLAIN}"
        rm -f "$tmp_ip" "$tmp_site"
    fi
    
    echo ""
    read -p "按回车键返回主菜单..."
}

while true; do
    clear
    
    # 获取当前本地版本
    if [ -x "$XRAY_BIN" ]; then
        LOCAL_VER=$("$XRAY_BIN" version | head -n 1 | awk '{print $2}')
    else
        LOCAL_VER="${RED}未安装${PLAIN}"
    fi

    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}           Xray 更新管理 (Update Manager)         ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  当前核心版本: ${GREEN}${LOCAL_VER}${PLAIN}"
    echo -e "---------------------------------------------------"
    echo -e "  1. 升级 Xray 核心至最新版"
    echo -e "  2. 手动更新 GeoData 路由规则库"
    echo -e "---------------------------------------------------"
    echo -e "  0. 退出 (Exit)"
    echo -e ""

    # 防回车键残留的安全输入循环
    while true; do
        read -p "请输入选项 [0-2]: " choice
        case "$choice" in
            1) update_core; break ;;
            2) update_geodata; break ;;
            0) clear; exit 0 ;;
            *) echo -e "\033[1A\033[K${RED}输入无效，请重新输入${PLAIN}" ;;
        esac
    done
done
