#!/usr/bin/env bash
# 缁欏凡鏈?REALITY 閰嶇疆"鍔犱竴鏉?VLESS-WS 鍏ョ珯"锛堢粰 Cloudflare 鍓嶇疆鐢級銆?# 淇濈暀鍘?REALITY 鍏ョ珯涓庣閽ワ紝鍙拷鍔?WS 鍏ョ珯锛岀劧鍚庨噸鍚?xray銆?# 鐢ㄦ硶锛堟湇鍔″櫒涓婏級锛歜ash i.sh     缁撴灉锛?root/result.txt锛堝惈 ws 璺緞涓?uuid锛?set -uo pipefail
LOG=/root/install.log
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

CFG=/usr/local/etc/xray/config.json
WS_PORT="${WS_PORT:-8080}"
WS_PATH="${WS_PATH:-/ws}"
BAK=/root/config.json.bak.$(date +%s)

echo "== 0. $(date -Is)"
[ -f "$CFG" ] || { echo "ERROR: 娌℃湁 $CFG"; echo "RESULT=FAIL:no-config" > /root/result.txt; exit 1; }

echo "== 1. 澶囦唤鍘熼厤缃?-> $BAK"
cp -f "$CFG" "$BAK"

echo "== 2. 浠庡師閰嶇疆閲屾彁鍙栧弬鏁?
PRIV=$(grep -oP '"privateKey"\s*:\s*"\K[^"]+' "$CFG" | head -1)
UUID=$(grep -oP '"id"\s*:\s*"\K[^"]+' "$CFG" | head -1)
SNI=$(grep -oP '"dest"\s*:\s*"\K[^":]+' "$CFG" | head -1)
PORT=$(grep -oP '"port"\s*:\s*\K[0-9]+' "$CFG" | head -1)
echo "  reality_port=$PORT uuid=$UUID sni=$SNI priv_len=${#PRIV}"
[ -n "$PRIV" ] && [ -n "$UUID" ] || { echo "ERROR: 鎻愬彇澶辫触"; echo "RESULT=FAIL:parse" > /root/result.txt; exit 1; }
[ -n "$SNI" ] || SNI=www.microsoft.com

echo "== 3. 鍐欐柊閰嶇疆锛圧EALITY + WS 涓ゆ潯鍏ョ珯锛?
cat > "$CFG" <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0", "port": ${PORT}, "protocol": "vless",
      "settings": { "clients": [ { "id": "${UUID}", "flow": "xtls-rprx-vision" } ], "decryption": "none" },
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": { "show": false, "dest": "${SNI}:443", "xver": 0,
          "serverNames": [ "${SNI}" ], "privateKey": "${PRIV}", "shortIds": [ "" ] }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ] }
    },
    {
      "listen": "0.0.0.0", "port": ${WS_PORT}, "protocol": "vless",
      "settings": { "clients": [ { "id": "${UUID}" } ], "decryption": "none" },
      "streamSettings": { "network": "ws", "security": "none",
        "wsSettings": { "path": "${WS_PATH}", "headers": { "Host": "${SNI}" } } },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ] }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" }, { "protocol": "blackhole", "tag": "block" } ]
}
JSON

echo "== 4. 閰嶇疆鏍￠獙"
/usr/local/bin/xray run -test -config "$CFG" || { echo "ERROR: 鏍￠獙澶辫触锛屽洖婊?; cp -f "$BAK" "$CFG"; systemctl restart xray; echo "RESULT=FAIL:config-test" > /root/result.txt; exit 1; }

echo "== 5. 閲嶅惎鏈嶅姟"
systemctl restart xray
sleep 2
systemctl is-active xray
ss -ltn 2>/dev/null | grep -E ":(${PORT}|${WS_PORT})\b" || true

echo "== 6. 鏀捐 WS 绔彛"
command -v ufw >/dev/null && { ufw allow ${WS_PORT}/tcp >/dev/null 2>&1 || true; }

IP=$(curl -s4 --max-time 10 ifconfig.me || echo UNKNOWN)
{
  echo "IP=${IP}"
  echo "REALITY_PORT=${PORT}"
  echo "WS_PORT=${WS_PORT}"
  echo "WS_PATH=${WS_PATH}"
  echo "UUID=${UUID}"
} > /root/result.txt
echo ""; echo "================ RESULT ================"; cat /root/result.txt; echo "========================================"
