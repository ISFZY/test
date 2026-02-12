#!/bin/bash
# --- 4. 生成配置 (Config Generation) ---

core_config() {
    echo -e "\n${BLUE}--- 5. 生成 Xray 配置文件 (Config) ---${PLAIN}"

    # 1. 检查必要变量 (从 3_system.sh 继承)
    # 如果这些端口为空，说明上一步出错了
    if [ -z "$PORT_VISION" ] || [ -z "$PORT_XHTTP" ]; then
        echo -e "${RED}[FATAL] 端口参数丢失！请检查系统配置步骤。${PLAIN}"
        exit 1
    fi

    # 2. 默认伪装域名 (SNI)
    SNI_HOST="www.icloud.com"
    echo -e "${OK}   使用伪装域名: ${GREEN}${SNI_HOST}${PLAIN}"

    # 3. 准备目录与核心
    mkdir -p /usr/local/etc/xray
    XRAY_BIN="/usr/local/bin/xray"

    if [ ! -f "$XRAY_BIN" ]; then
        echo -e "${RED}[FATAL] 找不到 Xray 核心文件，请检查安装步骤！${PLAIN}"
        exit 1
    fi

    # 4. 生成身份认证信息
    echo -e "${INFO} 正在生成密钥对与 UUID..."
    
    UUID=$($XRAY_BIN uuid)
    KEYS=$($XRAY_BIN x25519)
    # 提取密钥 (更加健壮的 awk 逻辑)
    PRIVATE_KEY=$(echo "$KEYS" | grep "Private" | awk -F': ' '{print $2}' | xargs)
    PUBLIC_KEY=$(echo "$KEYS" | grep -E "Public|Password" | awk -F': ' '{print $2}' | xargs)
    
    # ShortId: Reality 的短 ID，推荐 8 位 16 进制 (4字节)
    SHORT_ID=$(openssl rand -hex 4)
    # XHTTP Path: 随机路径
    XHTTP_PATH="/$(openssl rand -hex 4)"

    if [ -z "$UUID" ] || [ -z "$PRIVATE_KEY" ]; then
        echo -e "${ERR} 密钥生成失败，无法继续！"
        exit 1
    fi

    # 5. 写入 config.json
    cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "dns": { "servers": [ "localhost" ] },
  "inbounds": [
    {
      "tag": "vision_node",
      "port": ${PORT_VISION},
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}", "flow": "xtls-rprx-vision", "email": "admin_vision" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SNI_HOST}:443",
          "serverNames": [ "${SNI_HOST}" ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [ "${SHORT_ID}" ],
          "fingerprint": "chrome"
        }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ], "routeOnly": true }
    },
    {
      "tag": "xhttp_node",
      "port": ${PORT_XHTTP},
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}", "email": "admin_xhttp" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": { "path": "${XHTTP_PATH}" },
        "realitySettings": {
          "show": false,
          "dest": "${SNI_HOST}:443",
          "serverNames": [ "${SNI_HOST}" ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [ "${SHORT_ID}" ],
          "fingerprint": "chrome"
        }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ], "routeOnly": true }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": {
    "domainStrategy": "${DOMAIN_STRATEGY:-IPIfNonMatch}",
    "rules": [
      { "type": "field", "ip": [ "geoip:private" ], "outboundTag": "block" },
      { "type": "field", "protocol": [ "bittorrent" ], "outboundTag": "block" }
    ]
  }
}
EOF

    # 6. Systemd 资源限制优化 (Systemd Override)
    # 这对高性能节点非常重要，防止连接数过多导致服务崩溃
    mkdir -p /etc/systemd/system/xray.service.d
    echo -e "[Service]\nLimitNOFILE=infinity\nLimitNPROC=infinity\nTasksMax=infinity" > /etc/systemd/system/xray.service.d/override.conf
    # 重载 systemd 配置 (因为我们修改了 service.d)
    systemctl daemon-reload >/dev/null 2>&1

    echo -e "${OK}   Xray 配置文件生成完毕。"
}
