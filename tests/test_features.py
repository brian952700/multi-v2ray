"""Regression checks for existing configuration editing and bundled resources."""
import gettext
import json
from pathlib import Path
import tempfile
import unittest
import uuid
from unittest.mock import patch

from v2ray_util.resources import resource_filename
from v2ray_util.util_core import config as config_module
from v2ray_util.util_core.profile import Profile
from v2ray_util.util_core.utils import StreamType
from v2ray_util.util_core.writer import NodeWriter, GroupWriter, StreamWriter


class ExistingFeatures(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.config = self.root / 'config.json'
        self.conf = self.root / 'util.cfg'
        self.conf.write_text('[path]\nconfig_path=%s\n[data]\nlang=en\n' % self.config)
        p = patch.object(config_module, 'CONF_FILE', str(self.conf))
        p.start()
        self.addCleanup(p.stop)
        p = patch('v2ray_util.util_core.profile.get_ip', return_value='127.0.0.1')
        p.start()
        self.addCleanup(p.stop)
        self.reset_config()

    def reset_config(self):
        content = json.loads(Path(resource_filename('v2ray_util', 'json_template/server.json')).read_text())
        content['inbounds'][0]['port'] = 21000
        content['inbounds'][0]['settings']['clients'][0]['id'] = str(uuid.uuid4())
        content['inbounds'][0]['streamSettings']['network'] = 'tcp'
        self.config.write_text(json.dumps(content))

    def read(self):
        return json.loads(self.config.read_text())

    def test_resources_and_both_languages(self):
        for lang in ('en_US', 'zh_CH'):
            gettext.translation('lang', resource_filename('v2ray_util', 'locale_i18n'), languages=[lang])
        self.assertTrue(Path(resource_filename('v2ray_util.global_setting.iptables_ctr', 'clean_traffic.sh')).is_file())
        self.assertTrue(Path(resource_filename('v2ray_util.util_core.v2ray', 'util.cfg')).is_file())

    def test_user_add_remove_and_port_management(self):
        NodeWriter().create_new_user(email='test@example.com')
        self.assertEqual(len(self.read()['inbounds'][0]['settings']['clients']), 2)
        group = Profile().group_list[0]
        NodeWriter().del_user(group, 1)
        self.assertEqual(len(self.read()['inbounds'][0]['settings']['clients']), 1)
        NodeWriter().create_new_port(22000)
        self.assertEqual(len(self.read()['inbounds']), 2)
        group = Profile().group_list[1]
        NodeWriter().del_port(group)
        self.assertEqual(len(self.read()['inbounds']), 1)
        GroupWriter('A', 0).write_port(23000)
        self.assertEqual(self.read()['inbounds'][0]['port'], 23000)

    def test_existing_noncertificate_transports(self):
        cases = [
            (StreamType.TCP, {}, 'vmess'),
            (StreamType.TCP_HOST, {'host': 'example.com'}, 'vmess'),
            (StreamType.WS, {'host': 'example.com'}, 'vmess'),
            (StreamType.KCP_SRTP, {}, 'vmess'),
            (StreamType.KCP_UTP, {}, 'vmess'),
            (StreamType.KCP_WECHAT, {}, 'vmess'),
            (StreamType.KCP_DTLS, {}, 'vmess'),
            (StreamType.KCP_WG, {}, 'vmess'),
            (StreamType.VLESS_TCP, {}, 'vless'),
            (StreamType.VLESS_UTP, {}, 'vless'),
            (StreamType.SOCKS, {'user': 'test', 'pass': 'testpass'}, 'socks'),
            (StreamType.SS, {'method': 'aes-128-gcm', 'password': 'testpass'}, 'shadowsocks'),
            (StreamType.MTPROTO, {}, 'mtproto'),
            (StreamType.QUIC, {'security': 'none', 'key': '', 'header': 'none'}, 'vmess'),
        ]
        for transport, settings, protocol in cases:
            with self.subTest(transport=transport):
                self.reset_config()
                StreamWriter('A', 0, transport).write(**settings)
                inbound = self.read()['inbounds'][0]
                self.assertEqual(inbound['protocol'], protocol)
                self.assertEqual(inbound['port'], 21000)
                self.assertEqual(len(Profile().group_list), 1)


if __name__ == '__main__':
    unittest.main()
