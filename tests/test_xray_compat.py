"""Configuration migration must be reversible and never replace an invalid candidate."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

# Load independently so these tests also run without installed translations.
spec = importlib.util.spec_from_file_location('compat', Path(__file__).resolve().parents[1] / 'v2ray_util/util_core/xray_compat.py')
compat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compat)


class Migration(unittest.TestCase):
    def config(self, header='utp', seed=None):
        kcp = {'header': {'type': header}, 'mtu': 1350}
        if seed is not None:
            kcp['seed'] = seed
        return {'inbounds': [{'port': 23456, 'protocol': 'vmess',
            'settings': {'clients': [{'id': 'unchanged'}]},
            'streamSettings': {'network': 'kcp', 'kcpSettings': kcp}}]}

    def test_roundtrip_and_idempotence(self):
        for header in ('none', *compat.HEADERS):
            for seed in (None, '', 'existing-client-secret'):
                with self.subTest(header=header, seed=seed):
                    original = self.config(header, seed)
                    untouched = copy.deepcopy(original)
                    modern = compat.modern_config(original)
                    self.assertEqual(original, untouched)
                    self.assertEqual(compat.legacy_view(modern), original)
                    self.assertEqual(compat.modern_config(modern), modern)

    def test_preserve_custom_mask(self):
        original = self.config()
        original['inbounds'][0]['streamSettings']['finalmask'] = {'udp': [{'type': 'custom'}]}
        with self.assertRaises(ValueError):
            compat.modern_config(original)

    def test_validate_before_replace_and_keep_first_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'config.json'
            original = json.dumps(self.config())
            target.write_text(original)
            with patch.object(compat.subprocess, 'check_output', return_value='Xray 26.3.27'), patch.object(compat.subprocess, 'check_call', side_effect=subprocess.CalledProcessError(1, 'xray')):
                with self.assertRaises(subprocess.CalledProcessError):
                    compat.prepare_config(target)
            self.assertEqual(target.read_text(), original)
            self.assertFalse(target.with_name('config.json.pre-finalmask').exists())
            with patch.object(compat.subprocess, 'check_output', return_value='Xray 26.3.27'), patch.object(compat.subprocess, 'check_call'):
                compat.prepare_config(target)
                self.assertEqual(compat.legacy_view(json.loads(target.read_text())), json.loads(original))
                target.write_text(json.dumps(self.config('srtp')))
                compat.prepare_config(target)
            self.assertEqual(target.with_name('config.json.pre-finalmask').read_text(), original)


if __name__ == '__main__':
    unittest.main()
