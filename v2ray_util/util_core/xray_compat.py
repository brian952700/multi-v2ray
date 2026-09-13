"""Translate legacy mKCP settings for Xray's FinalMask configuration.

Retain the legacy representation as ignored metadata so management menus and
share links can still describe the original header/seed without losing data.
"""
import copy
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

MARKER = '_multi_v2ray_kcp'
HEADERS = {'srtp': 'header-srtp', 'utp': 'header-utp', 'dtls': 'header-dtls',
           'wechat-video': 'header-wechat', 'wireguard': 'header-wireguard'}


def streams(config):
    for direction in ('inbounds', 'outbounds'):
        for item in config.get(direction, []):
            stream = item.get('streamSettings', {})
            if stream.get('network') == 'kcp':
                yield stream


def modern_config(config):
    result = copy.deepcopy(config)
    for stream in streams(result):
        kcp = stream.get('kcpSettings', {})
        if 'header' not in kcp and 'seed' not in kcp:
            continue
        if stream.get('finalmask', {}).get('udp'):
            raise ValueError('Legacy mKCP and custom FinalMask are both set; refusing to overwrite either')
        old = {key: kcp.pop(key) for key in ('header', 'seed') if key in kcp}
        header = old.get('header', {}).get('type', 'none')
        if header not in HEADERS and header != 'none':
            raise ValueError('Unsupported legacy mKCP header: ' + header)
        masks = []
        if header != 'none':
            masks.append({'type': HEADERS[header]})
        if old.get('seed') is not None:
            masks.append({'type': 'mkcp-aes128gcm', 'settings': {'password': old['seed']}})
        else:
            masks.append({'type': 'mkcp-original'})
        stream.setdefault('finalmask', {})['udp'] = masks
        stream[MARKER] = old
    return result


def legacy_view(config):
    result = copy.deepcopy(config)
    for stream in streams(result):
        if MARKER in stream:
            stream.setdefault('kcpSettings', {}).update(stream.pop(MARKER))
            stream.get('finalmask', {}).pop('udp', None)
            if not stream.get('finalmask'):
                stream.pop('finalmask', None)
    return result


def prepare_config(path='/etc/xray/config.json'):
    binary = '/usr/bin/xray/xray'
    version = subprocess.check_output([binary, 'version'], text=True)
    match = re.search(r'Xray (\d+)\.(\d+)\.(\d+)', version)
    if not match or tuple(map(int, match.groups())) < (26, 3, 27):
        return
    target = Path(path)
    original = json.loads(target.read_text())
    converted = modern_config(original)
    if converted == original:
        return
    # Validate the entire candidate with the installed core before replacing it.
    with tempfile.NamedTemporaryFile(mode='w', dir=target.parent, suffix='.json', delete=False) as temp:
        json.dump(converted, temp, indent=2)
        candidate = temp.name
    try:
        subprocess.check_call([binary, 'run', '-test', '-c', candidate])
        backup = target.with_name(target.name + '.pre-finalmask')
        if not backup.exists():
            shutil.copy2(target, backup)
        shutil.copymode(target, candidate)
        os.replace(candidate, target)
    finally:
        if os.path.exists(candidate):
            os.unlink(candidate)
