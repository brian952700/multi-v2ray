#!/bin/bash
set -e
if [[ -s /root/.iptables ]]; then
    iptables-restore -w 5 -c < /root/.iptables
fi
if [[ -s /root/.ip6tables ]]; then
    ip6tables-restore -w 5 -c < /root/.ip6tables
fi
