# --- 生成配置 (Config) ---
core_config() {
    echo -e "\n${BLUE}--- 5. 生成配置 (Config) ---${PLAIN}"

    # 1. 默认 SNI
    SNI_HOST="www.icloud.com"
    echo -e "${OK}   默认伪装域名: ${GREEN}${SNI_HOST}${PLAIN}"
    echo -e "${INFO} (如需优选域名，安装后请输入 'sni' 指令)"

    # 2. 准备目录与核心
    mkdir -p /usr/local/etc/xray
    XRAY_BIN="/usr/local/bin/xray"

    # 核心文件熔断检查
    if [ ! -f "$XRAY_BIN" ]; then
        echo -e "${RED}[FATAL] 找不到 Xray 核心文件，配置生成失败！${PLAIN}"
        exit 1
    fi

    # 3. 生成身份信息
    UUID=$($XRAY_BIN uuid)
    KEYS=$($XRAY_BIN x25519)
    PRIVATE_KEY=$(echo "$KEYS" | grep "Private" | awk '{print $NF}')
    PUBLIC_KEY=$(echo "$KEYS" | grep -E "Public|Password" | awk '{print $NF}')
    SHORT_ID=$(openssl rand -hex 8)
    XHTTP_PATH="/$(openssl rand -hex 4)"

    if [ -z "$UUID" ] || [ -z "$PRIVATE_KEY" ]; then
        echo -e "${ERR} 密钥生成失败，无法写入配置！"
        exit 1
    fi

    # 4. 写入 config.json
    
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
        "clients": [ { "id": "${UUID}", "flow": "xtls-rprx-vision", "email": "admin" } ],
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
        "clients": [ { "id": "${UUID}", "flow": "", "email": "admin" } ],
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

    # 5. Systemd 资源限制优化
    mkdir -p /etc/systemd/system/xray.service.d
    echo -e "[Service]\nLimitNOFILE=infinity\nLimitNPROC=infinity\nTasksMax=infinity" > /etc/systemd/system/xray.service.d/override.conf

    echo -e "${OK}   配置文件生成完毕。"
}
