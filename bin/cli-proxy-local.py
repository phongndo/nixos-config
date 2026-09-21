"""Local service bootstrap only; CLIProxyAPI owns OAuth, refresh, and routing."""
import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys
import tempfile
import urllib.error
import urllib.request


def private_directory(path):
    if path.is_symlink():
        raise ValueError('Runtime directories must not be symlinks')
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.chmod(0o700)


def read_key(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd) as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError('Key must be an owned regular file')
        if stat.S_IMODE(info.st_mode) != 0o600:
            raise ValueError('Key must have mode 0600')
        key = stream.read(66).strip()
    if not re.fullmatch('[0-9a-f]{64}', key):
        raise ValueError('Invalid key; refusing to rotate it automatically')
    return key


def ensure_key(path):
    # Called under the configuration lock; keys are never printed or put in argv.
    if not path.exists() and not path.is_symlink():
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as key_file:
            key_file.write(secrets.token_hex(32) + '\n')
    return read_key(path)


def initialize(root):
    private_directory(root)
    private_directory(root / 'auth')
    lock = os.open(root / 'config.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(lock, 'w') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        config = json.loads((root / 'config.template.json').read_text())
        if config.get('host') != '127.0.0.1':
            raise ValueError('This local deployment must bind to 127.0.0.1')
        if type(config.get('port')) is not int or not 1 <= config['port'] <= 65535:
            raise ValueError('Invalid local port')
        management = config.get('remote-management', {})
        if management.get('secret-key') or management.get('allow-remote') is not False:
            raise ValueError('Management must be local-only with a runtime-generated key')
        if type(management.get('disable-control-panel')) is not bool:
            raise ValueError('Explicit control-panel setting required')
        if config.get('ws-auth') is not True:
            raise ValueError('WebSocket authentication must remain enabled')
        config['api-keys'] = [ensure_key(root / 'client-key')]
        if management['disable-control-panel'] is False:
            management['secret-key'] = ensure_key(root / 'management-key')
        config['auth-dir'] = str(root / 'auth')
        target = root / 'config.json'
        if target.is_symlink():
            raise ValueError('Generated configuration must not be a symlink')
        encoded = json.dumps(config, indent=2) + '\n'
        if target.exists() and target.read_text() == encoded:
            target.chmod(0o600)
            return target
        # JSON is also valid YAML. Never put the generated secret-bearing file
        # in a derivation, chezmoi's source, command arguments, or diagnostics.
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', dir=root, delete=False) as output:
                temporary = Path(output.name)
                output.write(encoded)
            temporary.replace(target)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        return target


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def check(root):
    # Upstream may rewrite its generated config as YAML when hashing the
    # management key. The managed template remains the endpoint authority.
    config = json.loads((root / 'config.template.json').read_text())
    if config.get('host') != '127.0.0.1':
        raise ValueError('Refusing a non-loopback endpoint')
    url = f"http://127.0.0.1:{int(config['port'])}/v1/models"
    # Ignore ambient HTTP proxy settings and never forward the key on redirects.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirects())
    request = urllib.request.Request(url, headers={
        'Authorization': 'Bearer ' + read_key(root / 'client-key'),
    })
    with opener.open(request, timeout=10) as response:
        payload = response.read(1024 * 1024 + 1)
    if len(payload) > 1024 * 1024:
        raise ValueError('Model listing too large')
    models = json.loads(payload).get('data', [])
    ids = sorted({model['id'] for model in models if isinstance(model.get('id'), str)})
    print('Local proxy reachable. Available model IDs:')
    # JSON escaping avoids interpreting terminal controls from upstream metadata.
    for model in ids:
        print('  ' + json.dumps(model))
    if not ids:
        print('  No models yet; run cli-proxy-local login.')


def main():
    os.umask(0o077)
    executable, *arguments = sys.argv[1:]
    if not arguments or arguments[0] not in {'init', 'login', 'serve', 'check', 'bank-resets'}:
        raise ValueError('Usage: cli-proxy-local {init|login [--no-browser]|serve|check|bank-resets {status|run|serve}}')
    command, *extra = arguments
    root = Path.home() / '.cli-proxy-api'
    if command == 'bank-resets':
        if len(extra) != 1 or extra[0] not in {'status', 'run', 'serve'}:
            raise ValueError('Usage: cli-proxy-local bank-resets {status|run|serve}')
        import cli_proxy_resets
        key = read_key(root / 'management-key')
        if extra[0] != 'status':
            private_directory(root / 'logs')
        sys.exit(cli_proxy_resets.main(root, extra[0], key))
    if extra and not (command == 'login' and extra == ['--no-browser']):
        raise ValueError('Only login accepts the optional --no-browser flag')
    if command == 'check':
        check(root)
        return
    config = initialize(root)
    if command == 'init':
        print('Local proxy configuration ready; credentials were not printed.')
        return
    os.chdir(root)
    env = dict(os.environ)
    env.pop('MANAGEMENT_PASSWORD', None)
    args = [executable, '--config', str(config)]
    if command == 'login':
        args += ['--codex-login', *extra]
    os.execve(executable, args, env)


if __name__ == '__main__':
    try:
        main()
    except urllib.error.HTTPError as error:
        print(f'Local proxy returned HTTP {error.code}; no response body logged.', file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f'Local proxy setup/check failed ({type(error).__name__}). '
              'Check ~/.cli-proxy-api/config.template.json, private runtime permissions, '
              'and the local service; existing secrets were left in place.', file=sys.stderr)
        sys.exit(1)
