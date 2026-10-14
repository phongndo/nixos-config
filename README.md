# y and z

Personal configuration for `dp`, checked out at `~/nix-config` on both hosts.
`flake.nix` connects macOS **y** and NixOS **z** to their machine configuration,
user settings, and shared Home Manager modules.
Both hosts use Nix's Zsh as the login shell. Home Manager owns its prompt and
defers completion setup until the first Tab or Ctrl-T. Most shell integrations
are generated during the Nix build; hz loads its installed version's integration
at shell startup. Project `nix develop` shells keep their own PATH.

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

`sync-agent-mcp` configures each agent's host-local Executor connection. Pi uses
its built-in MCP support (0.99.0+) and `~/.pi/agent/mcp.json`; `/mcp` manages it.
Sync preserves Pi's enable/disable and tool-exposure choices. Executor defaults
to direct exposure because it already provides tool discovery and sandboxed
execution. Integration credentials stay in Executor's local store.

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
