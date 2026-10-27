# y and z

Personal configuration for `dp`, checked out at `~/nix-config` on both hosts.
`flake.nix` connects macOS **y** and NixOS **z** to their machine configuration,
user settings, and shared Home Manager modules.
Both hosts use Nix's Zsh as the login shell. Home Manager owns its prompt and
defers completion setup until the first Tab or Ctrl-T. Most shell integrations
are generated during the Nix build; hz loads its installed version's integration
at shell startup. Project `nix develop` shells keep their own PATH.
Inside Rex, both shells put its `REX_BIN_DIR` first on PATH so the CLI matches
the connected server on either host.

## Ownership

- `machines/`: boot, hardware, networking, and system services. z's storage
  devices are declared in `machines/nixos/hardware.nix`.
- `users/dp/`: account settings and platform preferences; macOS applications
  are declared through Homebrew here.
- `home/`: user packages, shells, dotfiles, and user services. System rebuilds
  include Home Manager; there is no separate Home Manager deployment.
- `chezmoi/`: mutable agent configuration and mise tools. `home/chezmoi.nix`
  is the sole activation bridge. Agent tools intentionally use `latest` for
  new features; use `mise upgrade` to update installed versions.

Nix inputs and packages are pinned by `flake.lock`. Immich container images
are pinned by digest in `machines/nixos/immich/docker-compose.yml`; update its
server and machine-learning images together.

Personal tools are managed in `chezmoi/dot_config/mise/config.toml.tmpl`:
`mark`, `hz`, and `frame` on both hosts, plus `leetvim` on y. They track the
latest published GitHub releases through mise's
[GitHub backend](https://mise.jdx.dev/dev-tools/backends/github.html).
Run `mise upgrade` to update them without a Nix rebuild, or target one tool
with `mise upgrade github:phongndo/mark`. `home/personal-projects.nix` loads
hz's Bash and Zsh integration from the installed version; open a new shell
after updating hz. On NixOS, prebuilt GNU/Linux releases use `nix-ld`.

Homebrew apps, mise tools, and live chezmoi files are intentionally outside
Nix's reproducibility and rollback guarantees. Files marked `writable` in
`home/files.nix` link to this checkout so application edits can be reviewed
and committed. Neovim plugins use their own [lockfile and restore workflow](nvim/README.md).

Keep credentials, OAuth state, databases, and machine SSH keys outside this
repository. Skill sync reads the separate `~/code/pi-extensions` checkout;
its source and destinations are declared in
`chezmoi/dot_config/agent-skills/targets.json`.
fx discovers those distributed skills directly from the Codex and Claude
skill folders, so it needs no separate skill copy or sync target.

`sync-agent-mcp` configures Pi, Codex, Claude Code, OpenCode, and fx with
`~/.local/bin/executor-mcp`. The wrapper uses mise's `mcp-remote` client to reach
Executor Cloud. Both machines use the personal `Me` workspace; connected provider
accounts are available to every authorized agent. Neither machine hosts the
catalog or depends on the other being awake. Executor's approval
rules and each provider's authorization still apply. Google is excluded from
this setup; Fastmail supplies email and calendar.

The client saves its own sign-in in `~/.mcp-auth` on each host, outside Git.
Run `~/.local/bin/executor-mcp --login` to sign in or check the connection.
For remote sign-in on z, temporarily forward its callback with
`ssh -L 3338:127.0.0.1:3338 z`, then run the login command on z and open its
authorization link on y. The tunnel is needed only for browser sign-in.
New agent sessions use the Cloud connection; reload an existing session's MCP
connection after configuration changes.

Manage service definitions and connected accounts in the
[Executor workspace](https://app.executor.sh/org/me-9f65b0).
A service being installed there does not mean its account is authorized.
Connect every needed account or workspace through Executor's secure sign-in
forms; do not copy credentials from Codex or local Executor databases.

Executor is the primary shared layer. Keep native Figma and Atlassian connectors
as fallbacks where vendor authorization or missing capabilities prevent a working
Executor replacement. Remove a direct integration only after its replacement is
verified for the required accounts and tools.

ChatGPT and Claude web/Desktop use account-level connectors, which this sync
does not configure. Connect them separately to the same Executor workspace;
[Claude's remote connector](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)
uses `https://mcp.executor.sh/mcp` and follows the Claude account across its web
and desktop apps. This is separate from the
managed Claude Code configuration above.

The local Executor server and desktop app are not required. The shared
`mcp-remote` client remains necessary on both hosts to connect stdio harnesses
to Cloud. Old private `~/.executor` data can be retained outside Git for recovery;
Cloud does not read it. Fastmail's Cloud app supports an API token when its
OAuth callback is refused.

Rex app and terminal control uses its [official CLI skill](https://www.superlogical.com/rex/docs/automate/agent-skill).
`run_after_sync-rex-agents.sh.tmpl` installs that skill for Pi, Codex, Claude Code,
and OpenCode on both hosts; fx discovers the same skill through the shared
Claude/agent directories. The installed Rex version supplies the guide and hooks.
On y, `~/.local/bin/rex` exposes the Rex Beta app's bundled CLI outside Rex terminals;
z uses its Nix-provided CLI. Check access with `rex whoami --json` and
`rex client ls`; app actions require Rex's Remote Control setting.
Rex currently provides no control MCP server. The sync removes the retired
`superlogical` community endpoint, which only searched documentation and Discord.

Radius is configured only for Pi on both hosts at `https://radius.pi.dev/mcp`,
using Pi's `radius` authentication provider. Sign in with `/login radius` in Pi
on each host. Provider credentials remain in Pi's local auth store, outside Git;
declaring the MCP endpoint does not sign the host in.

OpenCode's managed entry lives in `~/.config/opencode/opencode.json`.
Sync also updates an older plain-JSON `opencode.jsonc` executor override so it
cannot keep launching the old transport. Commented settings are preserved;
if they contain an executor override, move that entry to the managed `.json`
file before syncing. Run `opencode reload` for an existing server. fx uses `~/.fx/mcp.json`;
`/mcp reload` applies changes in a running session. Pi uses its built-in MCP
support (0.99.0+) and `~/.pi/agent/mcp.json`; `/mcp` manages it.
Sync preserves Pi's enable/disable and tool-exposure choices. Executor defaults
to direct exposure because it already provides tool discovery and sandboxed
execution.
Codex-hosted plugin accounts need independent provider
authorization before their tools can appear in Executor; installing a Codex
plugin does not transfer its credentials.

## Check and apply

To sync either existing host with the pushed configuration, run:

```sh
cd ~/nix-config
git pull --ff-only origin main # needed once to get bin/sync
./bin/sync
```

After that, run `~/nix-config/bin/sync` on each computer. It requires a clean
checkout on `main`, pulls with fast-forward only, detects y or z, builds before
switching (prompting for sudo), then upgrades the configured mise tools.
Commit and push configuration edits before syncing the other computer.

From the repository root, without activating either host:

```sh
nix flake check --all-systems --no-build --no-write-lock-file
deadnix --fail .
statix check .
```

Build on the corresponding host before applying:

```sh
# y
nix build --no-link .#darwinConfigurations.y.system
sudo darwin-rebuild switch --flake .#y

# z
nix build --no-link .#nixosConfigurations.z.config.system.build.toplevel
sudo nixos-rebuild switch --flake .#z
```

On a new Mac, install Determinate Nix and Homebrew first, then use
`./bin/bootstrap`. Determinate owns y's Nix daemon; NixOS owns z's daemon
using the pinned Determinate package.

On z, provision the declared disks, SSH keys, and Tailscale login separately.
Immich needs `/var/lib/immich/.env` with mode `0600`, based on
`machines/nixos/immich/.env.example`. Tailscale Serve routing is provisioned
on the machine and is not restored by a Nix rebuild.

Rex runs on z as dp's Home Manager user service, kept running at boot by the
account's linger setting. In Rex on y, add `http://100.122.138.125:7297` as
the remote host named `z`; the same address works with `rex -S` on the CLI.
Use the Tailscale IPv4 address to avoid Rex's
[hostname/IPv6 terminal-loading bug](https://discord.com/channels/1546797889009881158/1564343288335564820)
(verified with build 1494 on 2026-10-26).
The listener uses z's Tailscale identity and admits its owner. Check it on z
with `systemctl --user status rex` or `journalctl --user -u rex`.
The [Rex package token](https://www.superlogical.com/rex/docs/linux/installation#nix-and-nixos)
is provisioned separately in `/etc/determinate/rex.netrc`, owned by dp with
mode `0600`, so both user-side flake downloads and root builds can read it.
NixOS declares Nix's reference to it; z doesn't run Determinate's authentication
helper. The Rex input follows the Preview channel. Update its pinned release
with `nix flake update rex`, then rebuild z.

z's resource policy lives in `machines/nixos/default.nix`: it bounds Nix build
concurrency, gives builds and T3 workers separate memory budgets, and enables
compressed swap. The T3 server has its own budget outside the worker slice;
OOM failures in builds or agents should not exhaust the host. Apply the policy
with the normal NixOS rebuild, then run `systemctl --user daemon-reload` to load
the user service and slice settings. Existing T3 processes do not need restarting
for the memory limits to take effect.

Atop records process and system history under `/var/log/atop`. Inspect a day's
recording with `sudo atop -r /var/log/atop/atop_YYYYMMDD` and press `m` for memory.
Use `systemd-cgtop` for current usage by workload, `oomctl` for monitored groups,
and `journalctl -k -g 'oom-kill:|Out of memory:'` for kernel OOM events. The
sampling interval and log retention are declared with the resource policy.
