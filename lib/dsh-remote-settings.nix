{ pkgs, trustedOrigin }:

let
  # This is the exact settings-client package shipped in the pinned DSH install.
  # Keep the npm installation unchanged; only this service loads the replacement.
  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@deepseek-ai/dsh-client-ui-settings/-/dsh-client-ui-settings-0.1.5-rc.2.tgz";
    hash = "sha512-NsnZLRI2ZDzJJylx9KATuDwrTdJ0FSP93dU5SL5k2G2W4FLUspNvlAmk7bha5Miopfzmfd+h5/NvMdWe8PVVjQ==";
  };
  original = ''const persistence = ctx.remote.$host.isLoopback ? "host" : "memory";'';
  replacement = ''const persistence = ctx.remote.$host.isLoopback || window.location.origin === ${builtins.toJSON trustedOrigin} ? "host" : "memory";'';
in
pkgs.runCommand "dsh-remote-settings-0.1.5-rc.2" { inherit src; } ''
  mkdir -p "$out"
  tar -xzf "$src" --strip-components=1 -C "$out"
  substituteInPlace "$out/lib/client.js" \
    --replace-fail ${pkgs.lib.escapeShellArg original} ${pkgs.lib.escapeShellArg replacement}
''
