# y and z

Personal configuration for `dp`, checked out at `~/nix-config` on both hosts.
`flake.nix` connects macOS **y** and NixOS **z** to their machine configuration,
user settings, and shared Home Manager modules.
Both hosts use Nix's Zsh as the login shell. Home Manager owns its prompt and
defers completion setup until the first Tab or Ctrl-T; shell integrations are
generated during the Nix build. Project `nix develop` shells keep their own PATH.

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

Homebrew apps, mise tools, and live chezmoi files are intentionally outside
Nix's reproducibility and rollback guarantees. Files marked `writable` in
`home/files.nix` link to this checkout so application edits can be reviewed
and committed. Neovim plugins use their own [lockfile and restore workflow](nvim/README.md).

Keep credentials, OAuth state, databases, and machine SSH keys outside this
repository. Skill sync reads the separate `~/code/pi-extensions` checkout;
its source and destinations are declared in
`chezmoi/dot_config/agent-skills/targets.json`.

## Check and apply

From the repository root, without activating either host:

```sh
nix flake check --all-systems --no-build --no-write-lock-file
deadnix --fail .
statix check .
python3 -m unittest discover -s tests
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

After switching, run `source ./tests/zsh.zsh` in an interactive Zsh to check
completion and the Ctrl-R, Ctrl-T, and Ctrl-G shortcuts.

On a new Mac, install Determinate Nix and Homebrew first, then use
`./bin/bootstrap`. Determinate owns y's Nix daemon; NixOS owns z's daemon
using the pinned Determinate package.

On z, provision the declared disks, SSH keys, and Tailscale login separately.
Immich needs `/var/lib/immich/.env` with mode `0600`, based on
`machines/nixos/immich/.env.example`. Tailscale Serve routing is provisioned
on the machine and is not restored by a Nix rebuild.
