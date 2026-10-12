#!/usr/bin/env bash
# Xray VLESS+XTLS-Vision+REALITY installer, robust + verbose version.
# Usage (on the VPS):  bash i.sh
# Result: prints the vless:// link and also writes /root/result.txt
set -uo pipefail

LOG=/root/install.log
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

PORT="${PORT:-$((20000 + RANDOM % 20000))}"
SNI="${SNI:-www.microsoft.com}"

echo "== 0. env: $(date -Is) kernel=$(uname -r) uid=$(id -u)"

echo "== 1. deps"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || echo "WARN apt update failed"
apt-get install -y -qq curl wget unzip ca-certificates jq >/dev/null || echo "WARN apt install failed"
for b in curl wget; do command -v $b >/dev/null && echo "  have $b" || echo "  MISSING $b"; done

echo "== 2. BBR"
if ! grep -q 'tcp_congestion_control=bbr' /etc/sysctl.conf; then
  printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1 || true
fi
sysctl net.ipv4.tcp_congestion_control 2>/dev/null || true

echo "== 3. install xray (official installer, output NOT hidden)"
curl -sL -o /root/xray-install.sh https://github.com/XTLS/Xray-install/raw/main/install-release.sh
ls -l /root/xray-install.sh
bash /root/xray-install.sh install || echo "WARN xray installer returned $?"
if [ -x /usr/local/bin/xray ]; then
  echo "  xray path: /usr/local/bin/xray"
  /usr/local/bin/xray version | head -2
else
  echo "  ERROR: /usr/local/bin/xray missing -> abort"
  echo "RESULT=FAIL:no-xray" > /root/result.txt
  exit 1
fi

echo "== 4. keys"
mkdir -p /usr/local/etc/xray
KOUT=$(/usr/local/bin/xray x25519 2>&1)
echo "$KOUT"
PRIV=$(printf '%s\n' "$KOUT" | grep -iE 'private' | awk '{print $NF}' | tail -1)
PUB=$(printf '%s\n' "$KOUT" | grep -iE 'public' | awk '{print $NF}' | tail -1)
if [ -z "${PRIV:-}" ] || [ -z "${PUB:-}" ]; then
  echo "  WARN parse failed, falling back to line order"
  PRIV=$(printf '%s\n' "$KOUT" | sed -n '1p' | awk '{print $NF}')
  PUB=$(printf '%s\n' "$KOUT" | sed -n '2p' | awk '{print $NF}')
fi
UUID=$(/usr/local/bin/xray uuid)
echo "  uuid=$UUID priv_len=${#PRIV} pub_len=${#PUB}"
[ -n "$PRIV" ] && [ -n "$PUB" ] || { echo "  ERROR: keygen produced empty keys"; echo "RESULT=FAIL:keygen" > /root/result.txt; exit 1; }

echo "== 5. write config"
cat > /usr/local/etc/xray/config.json <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}", "flow": "xtls-rprx-vision" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SNI}:443",
          "xver": 0,
          "serverNames": [ "${SNI}" ],
          "privateKey": "${PRIV}",
          "shortIds": [ "" ]
        }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ] }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" }, { "protocol": "blackhole", "tag": "block" } ]
}
JSON
/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json || echo "WARN config test failed"

echo "== 6. service"
systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray
sleep 2
systemctl is-active xray
systemctl is-enabled xray 2>/dev/null || true

echo "== 7. firewall"
if command -v ufw >/dev/null; then
  ufw allow 22/tcp >/dev/null 2>&1 || true
  ufw allow ${PORT}/tcp >/dev/null 2>&1 || true
  echo "  ufw: 22 + ${PORT} allowed (not forcing enable)"
else
  echo "  no ufw"
fi

IP=$(curl -s4 --max-time 10 ifconfig.me || curl -s4 --max-time 10 ip.sb || echo "UNKNOWN")
LINK="vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUB}&sid=&type=tcp&flow=xtls-rprx-vision#US-REALITY"

{
  echo "IP=${IP}"
  echo "PORT=${PORT}"
  echo "UUID=${UUID}"
  echo "PUBLIC_KEY=${PUB}"
  echo "LINK=${LINK}"
} > /root/result.txt

echo ""
echo "================ RESULT ================"
cat /root/result.txt
echo "========================================"
