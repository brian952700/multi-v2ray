"""Verify real VMess traffic through the generated default configuration."""
import functools
import http.server
import json
import pathlib
import subprocess
import sys
import tempfile
import threading
import time

core = sys.argv[1]
server = json.loads(pathlib.Path('/etc/' + core + '/config.json').read_text())
inbound = server['inbounds'][0]
with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    (root / 'probe').write_text('multi-v2ray-debian13-ok')
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=directory)
    httpd = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    config = {
        'inbounds': [{'listen': '127.0.0.1', 'port': 18081, 'protocol': 'socks',
                      'settings': {'auth': 'noauth'}}],
        'outbounds': [{'protocol': 'vmess', 'settings': {'vnext': [
            {'address': '127.0.0.1', 'port': int(inbound['port']),
             'users': [{'id': inbound['settings']['clients'][0]['id'], 'alterId': 0}]}]},
            'streamSettings': inbound['streamSettings']}]
    }
    client_config = root / 'client.json'
    client_config.write_text(json.dumps(config))
    with (root / 'client.log').open('w+') as log:
        client = subprocess.Popen(['/usr/bin/' + core + '/' + core, 'run', '-c', str(client_config)],
                                  stdout=log, stderr=log)
        try:
            result = None
            for attempt in range(15):
                result = subprocess.run(['curl', '--fail', '--silent', '--show-error', '--max-time', '3',
                    '--noproxy', '', '--socks5-hostname', '127.0.0.1:18081',
                    'http://127.0.0.1:%s/probe' % httpd.server_port], capture_output=True, text=True)
                if result.returncode == 0:
                    break
                if client.poll() is not None:
                    break
                time.sleep(1)
            assert result.returncode == 0, result.stderr
            assert result.stdout == 'multi-v2ray-debian13-ok', result.stdout
            print('PASS: real HTTP traffic via SOCKS -> VMess -> generated server')
        finally:
            client.terminate()
            try:
                client.wait(timeout=5)
            except subprocess.TimeoutExpired:
                client.kill()
                client.wait()
            log.seek(0)
            print(log.read())
            httpd.shutdown()
