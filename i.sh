#!/usr/bin/env bash
# Xray VLESS+REALITY installer v2: verbose, with a manual-install fallback.
# Usage: bash i2.sh     Result: /root/result.txt  (+ /root/install.log)
set -uo pipefail
LOG=/root/install.log
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

PORT="${PORT:-$((20000 + RANDOM % 20000))}"
SNI="${SNI:-www.microsoft.com}"
echo "== 0. $(date -Is) kernel=$(uname -r) uid=$(id -u) arch=$(uname -m)"

echo "== 1. apt deps (output visible)"
export DEBIAN_FRONTEND=noninteractive
apt-get update || echo "WARN: apt-get update failed rc=$?"
apt-get install -y curl wget unzip ca-certificates || echo "WARN: apt install rc=$?"
for b in curl wget unzip; do command -v $b >/dev/null && echo "  have $b" || echo "  MISSING $b"; done

echo "== 2. BBR"
grep -q 'tcp_congestion_control=bbr' /etc/sysctl.conf || printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1 || true
sysctl net.ipv4.tcp_congestion_control || true

echo "== 3. install xray (official script, output visible)"
curl -sSL -o /root/xray-install.sh https://github.com/XTLS/Xray-install/raw/main/install-release.sh
head -3 /root/xray-install.sh
bash /root/xray-install.sh install || echo "WARN: official installer rc=$?"

if [ ! -x /usr/local/bin/xray ]; then
  echo "== 3b. FALLBACK: manual xray install from release zip"
  curl -sSL -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
  ls -l /tmp/xray.zip
  command -v unzip >/dev/null || apt-get install -y unzip || true
  mkdir -p /usr/local/bin
  ( cd /tmp && unzip -o xray.zip -d /tmp/xray-pkg ) && cp -f /tmp/xray-pkg/xray /usr/local/bin/xray && chmod +x /usr/local/bin/xray
  mkdir -p /usr/local/etc/xray /usr/local/share/xray /var/log/xray
  cp -f /tmp/xray-pkg/*.dat /usr/local/share/xray/ 2>/dev/null || true
  cat > /etc/systemd/system/xray.service <<'UNIT'
[Unit]
Description=Xray Service
After=network.target nss-lookup.target
[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
fi

if [ ! -x /usr/local/bin/xray ]; then
  echo "RESULT=FAIL:no-xray-binary" | tee /root/result.txt
  exit 1
fi
echo "  xray ok:"; /usr/local/bin/xray version | head -2

echo "== 4. keys"
mkdir -p /usr/local/etc/xray /var/log/xray
KOUT=$(/usr/local/bin/xray x25519 2>&1); echo "$KOUT"
PRIV=$(printf '%s\n' "$KOUT" | grep -iE 'private' | awk '{print $NF}' | tail -1)
PUB=$(printf '%s\n' "$KOUT" | grep -iE 'public'  | awk '{print $NF}' | tail -1)
[ -n "${PRIV:-}" ] || PRIV=$(printf '%s\n' "$KOUT" | sed -n '1p' | awk '{print $NF}')
[ -n "${PUB:-}" ]  || PUB=$(printf '%s\n' "$KOUT" | sed -n '2p' | awk '{print $NF}')
UUID=$(/usr/local/bin/xray uuid)
echo "  uuid=$UUID privlen=${#PRIV} publen=${#PUB}"
[ -n "$PRIV" ] && [ -n "$PUB" ] && [ -n "$UUID" ] || { echo "RESULT=FAIL:keygen" | tee /root/result.txt; exit 1; }

echo "== 5. config"
cat > /usr/local/etc/xray/config.json <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    { "listen": "0.0.0.0", "port": ${PORT}, "protocol": "vless",
      "settings": { "clients": [ { "id": "${UUID}", "flow": "xtls-rprx-vision" } ], "decryption": "none" },
      "streamSettings": { "network": "tcp", "security": "reality",
        "realitySettings": { "show": false, "dest": "${SNI}:443", "xver": 0,
          "serverNames": [ "${SNI}" ], "privateKey": "${PRIV}", "shortIds": [ "" ] } },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ] } }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" }, { "protocol": "blackhole", "tag": "block" } ]
}
JSON
/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json || { echo "RESULT=FAIL:config-test" | tee /root/result.txt; exit 1; }

echo "== 6. service"
systemctl enable xray || true
systemctl restart xray
sleep 2
systemctl is-active xray || true
ss -ltn 2>/dev/null | grep -c ":${PORT}" || true

echo "== 7. firewall (ufw not enabled, only rules added)"
if command -v ufw >/dev/null; then ufw allow 22/tcp >/dev/null 2>&1 || true; ufw allow ${PORT}/tcp >/dev/null 2>&1 || true; fi

IP=$(curl -s4 --max-time 10 ifconfig.me || echo UNKNOWN)
LINK="vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUB}&sid=&type=tcp&flow=xtls-rprx-vision#US-REALITY"
{ echo "IP=${IP}"; echo "PORT=${PORT}"; echo "UUID=${UUID}"; echo "PUBLIC_KEY=${PUB}"; echo "LINK=${LINK}"; } > /root/result.txt
echo ""; echo "================ RESULT ================"; cat /root/result.txt; echo "========================================"
