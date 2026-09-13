#!/bin/bash
set -euo pipefail
export TERM=xterm
export DEBIAN_FRONTEND=noninteractive
trap 'systemctl --no-pager --full status v2ray xray || true; journalctl --no-pager -n 100 || true' ERR
cp -a /source /tmp/project
cd /tmp/project
timeout 600 bash v2ray.sh --zh
systemctl is-active --quiet v2ray
systemctl is-enabled --quiet v2ray
systemctl is-enabled --quiet multi-v2ray-iptables.service
/usr/bin/v2ray/v2ray test -c /etc/v2ray/config.json
/opt/multi-v2ray/venv/bin/python /source/tests/proxy_smoke.py v2ray
v2ray stop
test "$(systemctl is-active v2ray)" = inactive
v2ray start
v2ray restart
systemctl is-active --quiet v2ray
sha256sum /etc/v2ray/config.json > /tmp/config.sha256
bash v2ray.sh --keep
sha256sum --check /tmp/config.sha256
bash go.sh -x
xray new
systemctl is-active --quiet xray
/usr/bin/xray/xray run -test -c /etc/xray/config.json
/opt/multi-v2ray/venv/bin/python /source/tests/proxy_smoke.py xray
xray stop
test "$(systemctl is-active xray)" = inactive
xray start
xray restart
systemctl is-active --quiet xray
iptables -S INPUT
test -s /root/.iptables
systemctl start multi-v2ray-iptables.service
systemctl is-active --quiet multi-v2ray-iptables.service
echo 'PASS: systemd install, both core lifecycles, proxy traffic and keep-mode preservation'
