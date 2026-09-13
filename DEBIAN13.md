# Debian 13 compatibility

The Debian installer uses Python 3.13 in `/opt/multi-v2ray/venv`, installs
the manager from this repository, and downloads the latest stable V2Ray or
Xray release. It does not pin an obsolete core or modify Debian's system Python.
Install from a checkout with `bash ./v2ray.sh --zh`; use `--keep` to preserve
existing core configurations. Run as root, as required by the original installer.

## Review branch installation / 测试分支安装

Until this change is merged, the master installation URL still serves the old
installer. To test this branch on a Debian 13 test machine:

```bash
export MULTI_V2RAY_REF=ci/debian13-compatibility
curl -fL --retry 3 "https://raw.githubusercontent.com/brian952700/multi-v2ray/${MULTI_V2RAY_REF}/v2ray.sh" -o /tmp/multi-v2ray-install.sh
bash /tmp/multi-v2ray-install.sh --zh
```

已有节点请在最后一行追加 `--keep`，保留配置更新管理程序。首次安装沿用原行为，
生成随机端口和 UUID。运行 `xray` 可以安装并管理独立的 Xray 核心。
合并前不要运行 `update.sh` 子命令，它会更新到 master；测试分支的管理程序更新
请重复上面的命令并追加 `--keep`。`v2ray update` / `xray update` 更新的是核心。

## Configuration migration / 配置迁移

Xray 26.3.27 moved mKCP `header` and `seed` into `finalmask.udp`.
The manager converts these settings before starting Xray and when saving edits,
validates the candidate with the installed core, then atomically replaces the
configuration. The first original file is retained as
`/etc/xray/config.json.pre-finalmask`. UUIDs, ports and other settings are retained.
Ignored metadata retains the original mKCP settings for menus and share links.
Custom FinalMask settings are not overwritten. A rejected edit leaves the
previous on-disk configuration intact.

新版核心不再支持的协议不能仅靠改字段就保持客户端兼容。例如 Xray 已移除旧
HTTP/2 和 QUIC 传输；它们的替代方案 XHTTP 需要同步调整客户端。这里保留原菜单，
不擅自转换成不同传输协议。需要旧传输时可使用支持它的 V2Ray 核心；Xray 会先校验
配置，拒绝不支持的修改。不能把“Debian 13 可运行”理解为“所有旧协议在所有新核心上可用”。

## Tests and limits / 测试范围

`.github/workflows/debian13.yml` runs the actual installer in isolated Debian 13
amd64 containers, records Python/core versions and the image digest, and covers:

- Installed package imports, Chinese/English resources and generated credentials.
- Existing user/port and non-certificate configuration editing.
- Keep-mode reinstall without changing either core configuration.
- Latest-core validation, service start/stop/restart and real HTTP proxy traffic.
- Migration round trips, idempotence, conflict rejection and backup preservation.
- A separate systemd container for installation, firewall rule restoration,
  container restart persistence, and uninstall.

Check the Actions result for the exact revision being installed. A passing run
does not cover a real VPS kernel reboot, every client, provider firewalls, every
protocol combination or automatic certificate issuance. The workflow intentionally
uses latest upstream releases; future incompatible releases can fail these checks.

Debian 防火墙规则通过 `multi-v2ray-iptables.service` 恢复，IPv4/IPv6 分别保存到
`/root/.iptables` 和 `/root/.ip6tables`。未连接或修改用户的真实服务器。
