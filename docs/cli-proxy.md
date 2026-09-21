# Local Codex proxy: banked-reset expiry fallback

`cli-proxy-local bank-resets` is a companion worker, not a loadable CLIProxyAPI
plugin. `home/cli-proxy.nix` installs it alongside the proxy on both machines:
launchd on macOS and a systemd user service on Linux. Model requests still use
the machine-local proxy; the worker adds no synchronous work to inference.

## Behavior

- Inspect enabled Codex OAuth credentials through the local management API.
  CLIProxyAPI continues to own tokens and refresh; the worker never reads OAuth
  files or shares credentials between machines.
- Leave banked resets alone until **five minutes before their exact expiry**.
  Only available `codex_rate_limits` credits with an explicit ID and timezone-aware
  expiry are eligible. Never infer an expiry from a count or spend an unknown type.
- Check every five minutes while idle, scheduling an earlier check for a known
  redemption deadline. Retry due credits and failed checks every 30 seconds.
  Recheck wall time after sleep/network requests; startup checks immediately.
- Redeem the earliest eligible credit by **specific credit ID**, never the generic
  “consume any credit” operation. Both machines derive the same idempotency UUID
  for the same credit and 30-second attempt window. Later retries use a new
  attempt UUID so a cached `nothing_to_reset` response cannot permanently prevent
  retrying; the explicit credit ID prevents falling back to a different credit.
- Attempt at most one redemption per account per check. Treat `reset` and
  `already_redeemed` separately from `nothing_to_reset` and `no_credit`.
- Clear the affected local proxy credential's cooldown after confirmed redemption.
  If the other machine or a manual action already redeemed it, a locally
  unavailable credential is also checked against fresh upstream usage. Clear
  that stale cooldown only when the ordinary and all reported additional limits
  explicitly allow usage and report no limit reached. Missing/unknown data does
  not authorize clearing a cooldown.
- A per-machine file lock prevents two local redemption workers. No central
  coordinator or cross-machine inference traffic is required.

This is expiry protection, **not** automatic early redemption when a usage limit
is reached. A reset refreshes eligible usage windows; it is not additive credit
and can change the weekly reset date.

## Commands and services

After deploying the configuration through the usual Nix rebuild:

```sh
cli-proxy-local bank-resets status  # Read-only: account aliases, expiries, due/waiting
cli-proxy-local bank-resets run     # One real redemption check; refuses if worker is running
cli-proxy-local bank-resets serve   # Foreground worker (normally managed by the OS)
```

The management key and enabled local management API from the existing proxy
setup are required. `status` does not create logs/locks, redeem credits, or clear
cooldowns. Normal worker logs are rotated at 1 MiB (two backups):

```text
~/.cli-proxy-api/logs/bank-resets.log
```

Logs use hashed account/credit aliases and fixed error categories, never tokens,
response bodies, or account email addresses. Worker state is not synchronized by
chezmoi. The lock and logs are private machine-local runtime files.

Service inspection:

```sh
# macOS
launchctl print "gui/$(id -u)/com.dp.cli-proxy-bank-resets"

# Linux (run as the configured home-manager user)
systemctl --user status cli-proxy-bank-resets.service
```

## Limits

At least one configured machine must be awake, online, logged into a valid
account, and running its user service near expiry. The worker cannot redeem
while both hosts are asleep/offline, restore expired credits, or override
OpenAI's eligibility checks. A wake during the remaining expiry window is
noticed within approximately 30 seconds plus request time. Keep system clocks
synchronized. No power-management or systemd lingering settings are changed.

`nothing_to_reset` is retried while the credit remains unexpired, but if OpenAI
never finds an eligible usage window, the credit may still expire unused. Network
failures, authentication failures, or upstream API changes can also prevent
redemption; inspect the log and read-only status rather than treating this as a
guarantee. Manual redemptions remain available.

The worker uses the backend contract shipped in Codex via CLIProxyAPI's generic
management API, not a separately guaranteed public OpenAI API. Source review and
read-only access do not prove live redemption or server-side concurrency behavior.
Regression tests simulate those responses without spending real credits.

## Verification and upstream contracts

Run the affected checks with the repository's pinned Nix Python:

```sh
nix shell --inputs-from . nixpkgs#python3 -c python3 -B -m unittest discover -s tests -v
```

Contracts checked on **2026-09-21**:

- [OpenAI: how banked resets work](https://help.openai.com/en/articles/20001498-how-banked-codex-resets-work)
- [Codex reset listing and consumption](https://github.com/openai/codex/blob/ee2149a9b42ff487910514d1236349efcd00a641/codex-rs/backend-client/src/client/rate_limit_resets.rs)
- [Codex credit and result types](https://github.com/openai/codex/blob/ee2149a9b42ff487910514d1236349efcd00a641/codex-rs/backend-client/src/types.rs)
- [CLIProxyAPI v7.3.3 management API-call contract](https://github.com/router-for-me/CLIProxyAPI/blob/v7.3.3/internal/api/handlers/management/api_tools.go)
- [CLIProxyAPI v7.3.3 account metadata](https://github.com/router-for-me/CLIProxyAPI/blob/v7.3.3/internal/api/handlers/management/auth_files.go)
- [CLIProxyAPI v7.3.3 local cooldown clearing](https://github.com/router-for-me/CLIProxyAPI/blob/v7.3.3/internal/api/handlers/management/quota.go)
