"""Expiry-only Codex reset redemption, outside the inference request path.

CLIProxyAPI owns OAuth. Only its loopback management API sees the management
key; account tokens are substituted by the proxy, never read by this process.
See docs/cli-proxy.md for the upstream contracts and operational limitations.
"""
import fcntl
import hashlib
import json
import logging
from logging.handlers import RotatingFileHandler
import os
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone


LEAD_SECONDS = 300
POLL_SECONDS = 300
RETRY_SECONDS = 30
RESET_URL = 'https://chatgpt.com/backend-api/wham/rate-limit-reset-credits'
MAX_RESPONSE = 4 * 1024 * 1024
LOG = logging.getLogger('bank-resets')


class ProtocolError(ValueError):
    """A response cannot safely be used to redeem a specific reset."""


class HTTPFailure(Exception):
    def __init__(self, status):
        self.status = status


def error_label(error):
    # Neither exception messages nor response bodies are safe diagnostics.
    if isinstance(error, (HTTPFailure, urllib.error.HTTPError)):
        return f'HTTP {error.status if isinstance(error, HTTPFailure) else error.code}'
    return type(error).__name__


FAILURES = (OSError, ValueError, TypeError, KeyError, HTTPFailure)


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Proxy:
    def __init__(self, root, key):
        config = json.loads((root / 'config.template.json').read_text())
        port = config.get('port')
        if config.get('host') != '127.0.0.1' or type(port) is not int or not 1 <= port <= 65535:
            raise ProtocolError('Expected a loopback proxy')
        self.base = f'http://127.0.0.1:{port}/v0/management/'
        self.key = key
        self.unavailable = set()
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirects())

    def request(self, path, data=None):
        request = urllib.request.Request(
            self.base + path,
            data=None if data is None else json.dumps(data).encode(),
            headers={'Authorization': 'Bearer ' + self.key, 'Content-Type': 'application/json'},
        )
        with self.opener.open(request, timeout=15) as response:
            payload = response.read(MAX_RESPONSE + 1)
        if len(payload) > MAX_RESPONSE:
            raise ProtocolError('Response too large')
        result = json.loads(payload)
        if not isinstance(result, dict):
            raise ProtocolError('Expected an object')
        return result

    def accounts(self):
        files = self.request('auth-files').get('files')
        if not isinstance(files, list):
            raise ProtocolError('Missing account list')
        accounts = []
        self.unavailable = set()
        for entry in files:
            if not isinstance(entry, dict):
                raise ProtocolError('Invalid account entry')
            if entry.get('provider') != 'codex' or entry.get('disabled') is True:
                continue
            claims = entry.get('id_token')
            account_id = claims.get('chatgpt_account_id') if isinstance(claims, dict) else None
            index = entry.get('auth_index')
            # Never guess the workspace or let api-call choose a credential.
            if not safe_id(account_id) or not safe_id(index):
                LOG.warning('Skipping a Codex credential without account ID/auth index')
                continue
            account = (index, account_id)
            accounts.append(account)
            if entry.get('unavailable') is True:
                self.unavailable.add(account)
        return accounts

    def upstream(self, account, data=None, *, usage=False):
        index, account_id = account
        url = RESET_URL + ('' if data is None else '/consume')
        if usage:
            if data is not None:
                raise ProtocolError('Usage is read-only')
            url = 'https://chatgpt.com/backend-api/wham/usage'
        result = self.request('api-call', {
            'auth_index': index,
            'method': 'GET' if data is None else 'POST',
            'url': url,
            'header': {
                'Authorization': 'Bearer $TOKEN$',
                'ChatGPT-Account-Id': account_id,
                'Accept': 'application/json',
                'Content-Type': 'application/json',
            },
            **({} if data is None else {'data': json.dumps(data)}),
        })
        status = result.get('status_code')
        if type(status) is not int:
            raise ProtocolError('Missing upstream status')
        if status != 200:
            raise HTTPFailure(status)
        payload = json.loads(result['body'])
        if not isinstance(payload, dict):
            raise ProtocolError('Invalid upstream response')
        return payload

    def recover_cooldown(self, account):
        # The other machine (or the user) may have redeemed before our list
        # request. Recover stale local routing state only with fresh proof that
        # upstream allows usage, never by assuming a vanished credit was used.
        if account not in self.unavailable:
            return
        usage = self.upstream(account, usage=True)
        additional = usage.get('additional_rate_limits')
        if additional is None:
            additional = []
        if not isinstance(additional, list) or not all(isinstance(row, dict) for row in additional):
            return
        limits = [usage.get('rate_limit')] + [row.get('rate_limit') for row in additional]
        if all(isinstance(limit, dict) and limit.get('allowed') is True
               and limit.get('limit_reached') is False for limit in limits):
            self.clear_cooldown(account)
            LOG.info('Account %s: cleared stale local cooldown after upstream allowed usage', alias(account[1]))

    def clear_cooldown(self, account):
        if self.request('reset-quota', {'auth_index': account[0]}).get('status') != 'ok':
            raise ProtocolError('Local cooldown was not cleared')
        self.unavailable.discard(account)


def safe_id(value):
    return isinstance(value, str) and 0 < len(value) <= 512 and all(32 < ord(c) < 127 for c in value)


def alias(value):
    return hashlib.sha256(value.encode()).hexdigest()[:10]


def available_credits(payload):
    rows = payload.get('credits')
    if not isinstance(rows, list):
        raise ProtocolError('Detailed credit list is required')
    credits = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ProtocolError('Invalid credit')
        if row.get('status') != 'available':
            continue
        # Unknown future reset types must not be automatically spent.
        if row.get('reset_type') != 'codex_rate_limits':
            LOG.warning('Skipping an unsupported reset type')
            continue
        credit_id, expiry = row.get('id'), row.get('expires_at')
        if not safe_id(credit_id) or not isinstance(expiry, str):
            LOG.warning('Skipping a reset without an exact ID and expiry')
            continue
        try:
            expires = datetime.fromisoformat(expiry)
            if expires.tzinfo is None:
                raise ValueError('Timezone required')
            timestamp = expires.timestamp()
        except (ValueError, OverflowError):
            LOG.warning('Skipping a reset with an invalid expiry')
            continue
        if credit_id in credits and credits[credit_id] != timestamp:
            raise ProtocolError('Conflicting reset expiries')
        credits[credit_id] = timestamp
    return sorted(credits.items(), key=lambda credit: (credit[1], credit[0]))


def request_id(credit_id, now):
    # Same credit + attempt slot => same UUID on both machines. A new slot lets
    # nothing_to_reset be retried after more usage, even if negative responses
    # are cached. Explicit credit_id (NEVER omitted) prevents spending a second
    # credit after a timeout, restart, manual redemption, or cross-host race.
    return str(uuid.uuid5(uuid.NAMESPACE_URL,
                         f'cli-proxy-bank-resets/v1/{credit_id}/{int(now // RETRY_SECONDS)}'))


class Worker:
    def __init__(self, proxy, clock=time.time):
        self.proxy = proxy
        self.clock = clock
        self.pending_cooldowns = set()

    def poll(self, status_only=False):
        next_check = self.clock() + POLL_SECONDS
        failed = False
        accounts = self.proxy.accounts()
        if not accounts:
            LOG.warning('No enabled Codex OAuth accounts with usable account metadata')
            return RETRY_SECONDS, True
        for account in accounts:
            label = alias(account[1])
            try:
                if not status_only and account in self.pending_cooldowns:
                    self.proxy.clear_cooldown(account)
                    self.pending_cooldowns.remove(account)
                credits = available_credits(self.proxy.upstream(account))
                if status_only:
                    print(f'Account {label}: {len(credits)} supported resets with known expiry')
                for credit_id, expires_at in credits:
                    now = self.clock()  # Recheck after every network request, including wake from sleep.
                    remaining = expires_at - now
                    if status_only:
                        expiry = datetime.fromtimestamp(expires_at, timezone.utc).isoformat()
                        state = 'expired' if remaining <= 0 else 'due' if remaining <= LEAD_SECONDS else 'waiting'
                        print(f'  {alias(credit_id)}: expires {expiry}; {state}')
                        continue
                    if remaining <= 0:
                        continue
                    if remaining > LEAD_SECONDS:
                        next_check = min(next_check, expires_at - LEAD_SECONDS)
                        continue
                    next_check = min(next_check, now + RETRY_SECONDS)
                    result = self.proxy.upstream(account, {
                        'credit_id': credit_id,
                        'redeem_request_id': request_id(credit_id, now),
                    })
                    code = result.get('code')
                    if code in {'reset', 'already_redeemed'}:
                        LOG.info('Account %s reset %s: %s', label, alias(credit_id), code)
                        self.pending_cooldowns.add(account)
                        self.proxy.clear_cooldown(account)
                        self.pending_cooldowns.remove(account)
                    elif code == 'nothing_to_reset':
                        LOG.info('Account %s: nothing eligible to reset; retrying before expiry', label)
                    elif code == 'no_credit':
                        LOG.info('Account %s: selected reset no longer available', label)
                    else:
                        raise ProtocolError('Unknown redemption result')
                    # Do not immediately spend another reset against freshly reset windows.
                    break
                if not status_only:
                    self.proxy.recover_cooldown(account)
            except FAILURES as error:
                failed = True
                next_check = min(next_check, self.clock() + RETRY_SECONDS)
                LOG.warning('Account %s check failed (%s); no response body logged', label, error_label(error))
        return max(1, next_check - self.clock()), failed


def sleep_until(deadline, clock=time.time, sleep=time.sleep):
    # Recheck wall time in short slices: suspend must not leave a five-minute
    # monotonic sleep outstanding after the machine wakes near expiry.
    while (remaining := deadline - clock()) > 0:
        sleep(min(RETRY_SECONDS, remaining))


def main(root, command, key):
    proxy = Proxy(root, key)
    if command == 'status':
        logging.basicConfig(level=logging.WARNING, format='%(message)s')
        _, failed = Worker(proxy).poll(status_only=True)
        return int(failed)

    # One redeemer per machine. The lock lives outside the OAuth directory.
    fd = os.open(root / 'bank-resets.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('A bank-reset worker is already running on this machine.')
            return 1
        handler = RotatingFileHandler(root / 'logs' / 'bank-resets.log', maxBytes=1024 * 1024, backupCount=2)
        handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))
        LOG.addHandler(handler)
        LOG.setLevel(logging.INFO)
        worker = Worker(proxy)
        LOG.info('Started expiry-only redeemer: lead=%ss; idle poll=%ss', LEAD_SECONDS, POLL_SECONDS)
        while True:
            try:
                delay, failed = worker.poll()
            except FAILURES as error:
                LOG.warning('Proxy check failed (%s); retrying', error_label(error))
                delay, failed = RETRY_SECONDS, True
            if command == 'run':
                return int(failed)
            sleep_until(time.time() + delay)
