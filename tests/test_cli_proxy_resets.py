"""No real redemption requests: policy + loopback transport contract tests."""
import contextlib
from datetime import datetime, timedelta, timezone
import io
import json
import logging
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bin'))
import cli_proxy_resets as resets

NOW = 1_800_000_000.0
ACCOUNT = ('auth-1', 'account-1')
OTHER = ('auth-2', 'account-2')


def credit(name='credit-1', delta=300, **changes):
    return {
        'id': name, 'reset_type': 'codex_rate_limits', 'status': 'available',
        'expires_at': datetime.fromtimestamp(NOW + delta, timezone.utc).isoformat(),
        **changes,
    }


class FakeProxy:
    def __init__(self, rows=None):
        self.rows = {ACCOUNT: [credit()] if rows is None else rows}
        self.calls = []
        self.cleared = []
        self.result = {'code': 'reset'}
        self.clear_failure = False

    def accounts(self):
        return list(self.rows)

    def upstream(self, account, data=None):
        self.calls.append((account, data))
        if data is None:
            rows = self.rows[account]
            if isinstance(rows, Exception):
                raise rows
            return {'credits': rows}
        if isinstance(self.result, Exception):
            raise self.result
        if self.result['code'] == 'reset':
            self.rows[account] = [r for r in self.rows[account] if r['id'] != data['credit_id']]
        return self.result

    def recover_cooldown(self, account):
        pass

    def clear_cooldown(self, account):
        if self.clear_failure:
            raise TimeoutError()
        self.cleared.append(account)

    @property
    def redemptions(self):
        return [data for _, data in self.calls if data is not None]


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.logs = io.StringIO()
        self.handler = logging.StreamHandler(self.logs)
        resets.LOG.addHandler(self.handler)

    def tearDown(self):
        resets.LOG.removeHandler(self.handler)

    def poll(self, proxy, now=NOW, status=False):
        return resets.Worker(proxy, lambda: now).poll(status)

    def test_five_minute_boundary_and_expiry(self):
        for delta, expected in [(301, 0), (300, 1), (299, 1), (1, 1), (0, 0), (-1, 0)]:
            with self.subTest(delta=delta):
                proxy = FakeProxy([credit(delta=delta)])
                self.poll(proxy)
                self.assertEqual(len(proxy.redemptions), expected)

    def test_schedules_exact_deadline_without_busy_polling(self):
        for delta, delay in [(301, 1), (420, 120), (86400, 300)]:
            proxy = FakeProxy([credit(delta=delta)])
            self.assertEqual(self.poll(proxy), (delay, False))

    def test_earliest_specific_credit_only(self):
        proxy = FakeProxy([credit('later', 290), credit('first', 100), credit('future', 10000)])
        self.poll(proxy)
        self.assertEqual(len(proxy.redemptions), 1)
        self.assertEqual(proxy.redemptions[0]['credit_id'], 'first')
        self.assertEqual(proxy.cleared, [ACCOUNT])

    def test_invalid_unknown_missing_details_never_fallback_to_count(self):
        for change in [
            {'expires_at': None}, {'expires_at': 'tomorrow'},
            {'expires_at': '2027-01-15T08:00:00'}, {'id': ''}, {'id': 'bad\nheader'},
            {'status': 'redeemed'}, {'status': 'unknown'}, {'reset_type': 'future_type'},
        ]:
            with self.subTest(change=change):
                proxy = FakeProxy([credit(**change)])
                self.poll(proxy)
                self.assertEqual(proxy.redemptions, [])
        with self.assertRaises(resets.ProtocolError):
            resets.available_credits({'available_count': 2})
        with self.assertRaises(resets.ProtocolError):
            resets.available_credits({'credits': [credit(), credit(delta=200)]})

    def test_explicit_timezone_offsets(self):
        row = credit()
        row['expires_at'] = datetime.fromisoformat(row['expires_at']).astimezone(
            timezone(timedelta(hours=-7))).isoformat()
        self.assertEqual(resets.available_credits({'credits': [row]})[0][1], NOW + 300)

    def test_status_is_read_only_even_when_due(self):
        proxy = FakeProxy()
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.poll(proxy, status=True)
        self.assertIn('due', output.getvalue())
        self.assertNotIn('account-1', output.getvalue())
        self.assertEqual(proxy.redemptions, [])
        self.assertEqual(proxy.cleared, [])

    def test_one_failed_account_does_not_block_another(self):
        proxy = FakeProxy()
        proxy.rows[ACCOUNT] = resets.HTTPFailure(401)
        proxy.rows[OTHER] = [credit('other')]
        self.assertEqual(self.poll(proxy), (30, True))
        self.assertEqual(proxy.redemptions[0]['credit_id'], 'other')
        self.assertIn('HTTP 401', self.logs.getvalue())

    def test_nothing_to_reset_is_retried_with_new_attempt_key(self):
        proxy = FakeProxy()
        proxy.result = {'code': 'nothing_to_reset'}
        self.assertEqual(self.poll(proxy), (30, False))
        self.poll(proxy, NOW + 30)
        first, second = proxy.redemptions
        self.assertEqual(first['credit_id'], second['credit_id'])
        self.assertNotEqual(first['redeem_request_id'], second['redeem_request_id'])
        self.assertEqual(proxy.cleared, [])

    def test_two_hosts_target_same_credit_and_idempotency_key(self):
        first, second = FakeProxy(), FakeProxy()
        self.poll(first)
        second.result = {'code': 'already_redeemed'}
        self.poll(second)
        self.assertEqual(first.redemptions, second.redemptions)
        self.assertEqual(second.cleared, [ACCOUNT])

    def test_no_credit_never_falls_back_to_next_reset(self):
        proxy = FakeProxy([credit(), credit('not-selected', 250)])
        proxy.result = {'code': 'no_credit'}
        self.poll(proxy)
        self.assertEqual(len(proxy.redemptions), 1)
        self.assertEqual(proxy.cleared, [])

    def test_timeout_retry_still_targets_same_credit_not_next_one(self):
        proxy = FakeProxy([credit(), credit('later', 1000)])
        proxy.result = TimeoutError('sensitive body')
        self.assertEqual(self.poll(proxy), (30, True))
        proxy.result = {'code': 'already_redeemed'}
        self.poll(proxy, NOW + 31)
        self.assertEqual([r['credit_id'] for r in proxy.redemptions], ['credit-1', 'credit-1'])
        self.assertNotIn('sensitive body', self.logs.getvalue())

    def test_unknown_result_is_not_success(self):
        proxy = FakeProxy()
        proxy.result = {'code': 'unexpected'}
        self.assertEqual(self.poll(proxy), (30, True))
        self.assertEqual(proxy.cleared, [])

    def test_failed_cooldown_clear_retries_without_spending_another_credit(self):
        proxy = FakeProxy()
        proxy.clear_failure = True
        worker = resets.Worker(proxy, lambda: NOW)
        self.assertEqual(worker.poll(), (30, True))
        proxy.clear_failure = False
        worker.poll()
        self.assertEqual(len(proxy.redemptions), 1)
        self.assertEqual(proxy.cleared, [ACCOUNT])

    def test_sleep_rechecks_wall_clock_after_wake(self):
        clock = iter([NOW, NOW + 600])
        sleeps = []
        resets.sleep_until(NOW + 300, lambda: next(clock), sleeps.append)
        self.assertEqual(sleeps, [30])

    def test_clock_is_rechecked_after_network_and_sleep(self):
        proxy = FakeProxy()
        # At poll start the credit is not expired, but a slow list returns after expiry.
        clock = iter([NOW, NOW + 301, NOW + 301])
        resets.Worker(proxy, lambda: next(clock)).poll()
        self.assertEqual(proxy.redemptions, [])


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.requests = []
        self.redirect = False
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                self.handle_request()

            def do_POST(self):
                self.handle_request()

            def handle_request(self):
                data = self.rfile.read(int(self.headers.get('Content-Length', 0)))
                body = json.loads(data) if data else None
                owner.requests.append((self.path, self.headers['Authorization'], body))
                if owner.redirect:
                    self.send_response(302)
                    self.send_header('Location', '/must-not-follow')
                    self.end_headers()
                    return
                if self.path.endswith('/auth-files'):
                    result = {'files': [
                        {'provider': 'codex', 'auth_index': 'a', 'disabled': False,
                         'id_token': {'chatgpt_account_id': 'acct'}},
                        {'provider': 'codex', 'disabled': True},
                        {'provider': 'codex', 'auth_index': 'missing-account-id'},
                        {'provider': 'other'},
                    ]}
                else:
                    result = {'status_code': 200, 'body': json.dumps({'credits': [credit()]})}
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(result).encode())

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / 'config.template.json').write_text(json.dumps({
            'host': '127.0.0.1', 'port': self.server.server_port,
        }))
        self.proxy = resets.Proxy(self.root, 'local-secret')

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def test_account_discovery_and_exact_upstream_contract(self):
        with patch.dict(os.environ, {'http_proxy': 'http://127.0.0.1:1', 'no_proxy': ''}):
            proxy = resets.Proxy(self.root, 'local-secret')
            account, = proxy.accounts()
            self.assertEqual(account, ('a', 'acct'))
            proxy.upstream(account)
            proxy.upstream(account, {'credit_id': 'specific', 'redeem_request_id': 'unique'})
        for _, key, body in self.requests:
            self.assertEqual(key, 'Bearer local-secret')
            if body:
                self.assertNotIn('local-secret', json.dumps(body))
                self.assertEqual(body['auth_index'], 'a')
                self.assertEqual(body['header']['Authorization'], 'Bearer $TOKEN$')
                self.assertEqual(body['header']['ChatGPT-Account-Id'], 'acct')
        read_body, consume_body = [r[2] for r in self.requests[1:]]
        self.assertEqual(read_body['method'], 'GET')
        self.assertEqual(read_body['url'], resets.RESET_URL)
        self.assertEqual(consume_body['method'], 'POST')
        self.assertEqual(consume_body['url'], resets.RESET_URL + '/consume')
        self.assertEqual(json.loads(consume_body['data'])['credit_id'], 'specific')

    def test_remote_redemption_recovers_only_confirmed_available_usage(self):
        allowed = {'allowed': True, 'limit_reached': False}
        for usage, clears in [
            ({'rate_limit': allowed}, True),
            ({'rate_limit': {'allowed': False, 'limit_reached': True}}, False),
            ({'rate_limit': {'allowed': True}}, False),
            ({}, False),
            ({'rate_limit': allowed, 'additional_rate_limits': {}}, False),
            ({'rate_limit': allowed, 'additional_rate_limits': [
                {'rate_limit': {'allowed': False, 'limit_reached': True}}]}, False),
            ({'rate_limit': allowed, 'additional_rate_limits': [{'rate_limit': allowed}]}, True),
        ]:
            with self.subTest(usage=usage):
                self.proxy.unavailable = {ACCOUNT}
                with patch.object(self.proxy, 'upstream', return_value=usage) as upstream, \
                        patch.object(self.proxy, 'clear_cooldown') as clear:
                    self.proxy.recover_cooldown(ACCOUNT)
                    upstream.assert_called_once_with(ACCOUNT, usage=True)
                    self.assertEqual(clear.called, clears)
        self.proxy.unavailable = set()
        with patch.object(self.proxy, 'upstream') as upstream:
            self.proxy.recover_cooldown(ACCOUNT)
            upstream.assert_not_called()

    def test_management_redirect_is_not_followed(self):
        self.redirect = True
        with self.assertRaises(resets.urllib.error.HTTPError):
            self.proxy.accounts()
        self.assertEqual(len(self.requests), 1)

    def test_nonloopback_config_rejected(self):
        for host, port in [('example.com', 8317), ('127.0.0.1', True), ('127.0.0.1', 65536)]:
            (self.root / 'config.template.json').write_text(json.dumps({'host': host, 'port': port}))
            with self.assertRaises(resets.ProtocolError):
                resets.Proxy(self.root, 'local-secret')


if __name__ == '__main__':
    unittest.main()
