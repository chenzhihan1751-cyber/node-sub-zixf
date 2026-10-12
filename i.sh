#!/usr/bin/env bash
# 涓€閿細鈶?淇琚悶鍧忕殑 sshd 閰嶇疆锛堟仮澶?22 绔彛锛?鈶?缁?xray 鍔犱竴鏉?VLESS-WS 鍏ョ珯锛圕loudflare 鍓嶇疆鐢級
# 鐢ㄦ硶锛堟湇鍔″櫒涓婏級锛歜ash i.sh        缁撴灉锛?root/result.txt
set -uo pipefail
LOG=/root/install.log
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

echo "########## PART 1: 淇?sshd ##########"
echo "== 澶囦唤鍘熼厤缃?
cp -f /etc/ssh/sshd_config /root/sshd_config.bak.$(date +%s) 2>/dev/null || true
echo "== 鍘熼厤缃噷鐨?Port / 闈炴敞閲婅鏁?
grep -n '^Port' /etc/ssh/sshd_config || echo "  (娌℃湁 Port 琛?"
echo "== 璇硶妫€鏌ワ紙鍘熼厤缃級"
sshd -t || echo "  鍘熼厤缃娉曢敊璇?^^^"

echo "== 鍐欏叆骞插噣鐨勬渶灏忛厤缃?
cat > /etc/ssh/sshd_config <<'EOF'
Port 22
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
AuthorizedKeysFile .ssh/authorized_keys
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
sshd -t && echo "  鏂伴厤缃娉?OK"
echo "== 閲嶅惎 ssh"
systemctl enable ssh >/dev/null 2>&1 || true
systemctl restart ssh || true
sleep 2
echo -n "  ssh 鏈嶅姟鐘舵€? "; systemctl is-active ssh || true
ss -ltn 2>/dev/null | grep -qE ':22\b' && echo "  22 绔彛鍦ㄧ洃鍚?OK" || echo "  22 绔彛鏈洃鍚?!!"

echo ""
echo "########## PART 2: 鍔?VLESS-WS 鍏ョ珯 ##########"
CFG=/usr/local/etc/xray/config.json
WS_PORT="${WS_PORT:-8080}"
WS_PATH="${WS_PATH:-/ws}"
if [ ! -f "$CFG" ]; then
  echo "ERROR: 娌℃湁 $CFG锛岃烦杩?
else
  cp -f "$CFG" /root/config.json.bak.$(date +%s)
  PRIV=$(grep -oP '"privateKey"\s*:\s*"\K[^"]+' "$CFG" | head -1)
  UUID=$(grep -oP '"id"\s*:\s*"\K[^"]+' "$CFG" | head -1)
  SNI=$(grep -oP '"dest"\s*:\s*"\K[^":]+' "$CFG" | head -1)
  PORT=$(grep -oP '"port"\s*:\s*\K[0-9]+' "$CFG" | head -1)
  echo "  鎻愬彇: reality_port=$PORT uuid=$UUID sni=$SNI privlen=${#PRIV}"
  [ -n "${SNI:-}" ] || SNI=www.microsoft.com
  if [ -n "${PRIV:-}" ] && [ -n "${UUID:-}" ]; then
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
    /usr/local/bin/xray run -test -config "$CFG" && echo "  xray 閰嶇疆鏍￠獙 OK" || echo "  xray 閰嶇疆鏍￠獙澶辫触 !!"
    systemctl restart xray
    sleep 2
    echo -n "  xray 鐘舵€? "; systemctl is-active xray || true
    ss -ltn 2>/dev/null | grep -E ":(${PORT}|${WS_PORT})\b" || true
    command -v ufw >/dev/null && { ufw allow ${WS_PORT}/tcp >/dev/null 2>&1 || true; }
    IP=$(curl -s4 --max-time 8 ifconfig.me || echo UNKNOWN)
    { echo "IP=${IP}"; echo "REALITY_PORT=${PORT}"; echo "WS_PORT=${WS_PORT}"; echo "WS_PATH=${WS_PATH}"; echo "UUID=${UUID}"; } > /root/result.txt
    echo ""; echo "================ RESULT ================"; cat /root/result.txt; echo "========================================"
  else
    echo "ERROR: 鏃犳硶浠庡師閰嶇疆鎻愬彇 privateKey/UUID"
    echo "RESULT=FAIL:parse" > /root/result.txt
  fi
fi
echo "ALL DONE"
