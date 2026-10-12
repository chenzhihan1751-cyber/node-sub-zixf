#!/usr/bin/env bash
# 缇庡浗鑺傜偣涓€閿锛歑ray VLESS+XTLS-Vision+REALITY锛堟棤闇€鍩熷悕/璇佷功锛? BBR + 闃茬伀澧欐斁琛?# 鐢ㄦ硶锛歴sh root@<IP> 'bash -s' < install-us-node.sh
set -e
export DEBIAN_FRONTEND=noninteractive
PORT="${PORT:-$((20000 + RANDOM % 20000))}"
SNI="${SNI:-www.microsoft.com}"

echo "== 1/6 鍩虹鍖?
apt-get update -qq
apt-get install -y -qq curl unzip ca-certificates ufw >/dev/null 2>&1 || true

echo "== 2/6 BBR"
if ! grep -q 'tcp_congestion_control=bbr' /etc/sysctl.conf 2>/dev/null; then
  printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1 || true
fi

echo "== 3/6 瀹夎 Xray"
bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1 || \
bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

echo "== 4/6 鐢熸垚瀵嗛挜涓?UUID"
UUID=$(/usr/local/bin/xray uuid)
KOUT=$(/usr/local/bin/xray x25519)
PRIV=$(echo "$KOUT" | grep -iE 'private' | awk '{print $NF}')
PUB=$(echo "$KOUT" | grep -iE 'public' | awk '{print $NF}')

echo "== 5/6 鍐欓厤缃?
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
systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray

echo "== 6/6 鏀捐绔彛"
ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow ${PORT}/tcp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true

IP=$(curl -s4 ifconfig.me || curl -s4 ip.sb)
LINK="vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUB}&sid=&type=tcp&flow=xtls-rprx-vision#US-REALITY"

echo ""
echo "================ 瀹屾垚 ================"
echo "绔彛: ${PORT}"
echo "鍒嗕韩閾炬帴锛堝鍏?Shadowrocket / v2rayN锛?"
echo "${LINK}"
echo "璁㈤槄锛坆ase64锛屽彲鑷鎵樼锛?"
echo -n "${LINK}" | base64 -w0
echo ""
echo "======================================"
