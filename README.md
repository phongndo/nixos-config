# nix-config

nix-darwin for the Mac **y** and NixOS for **z**, with Home Manager for dp. Clone to `~/nix-config`.

- New Mac: install Determinate Nix and Homebrew, then run `bin/bootstrap`.
- Update a host: `bin/sync` (needs a clean `main`), or `hm` to switch to the checkout as it is.
- Steps Nix can't do (secrets, sign-ins) are commented where they apply: `git grep Manual:`.
