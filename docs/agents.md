# Agent installation

The supported agent roster on both the Mac and NixOS box is **DSH, Codex,
OpenCode, and Pi**. Mise owns their installations through
`chezmoi/dot_config/mise/config.toml.tmpl`; the shared `latest` selections
remain in place for normal future updates.

Versions verified on both machines during setup:

| Agent | Version |
| --- | --- |
| DSH | `0.1.5-rc.1` |
| Codex | `0.154.0` |
| OpenCode | `1.18.31` |
| Pi | `0.85.1` |

Pi loads skills directly from `~/code/pi-extensions`. Skill distribution only
copies into the Codex, OpenCode, and DSH directories. Legacy targets are cleaned
using the sync tool's ownership manifests; user-modified or unowned files are
not deleted. Old agent sessions and account stores are preserved.

## DSH on NixOS

DSH is installed as the official `@deepseek-ai/dsh` npm package through mise,
with the managed Node runtime. Linux also installs `pnpm`, required by the
`dsh plugin` profile manager. The `web` and `headless` profiles have been
initialized, and the Executor MCP plugin is in the shared
`~/.dsh/cordis.patch.yml` overlay.

The **Local Codex pool** provider (`codex-local`) now connects to the existing
Linux CLIProxyAPI using its private client key. It is the managed web service's
only active model provider: DeepSeek is disabled by its Nix overlay, and OpenCode
Go was removed from settings. New chats default to `gpt-6-astra` with `xhigh`
reasoning. In an existing conversation, the control near Send offers **Model**
and **Effort**; all five Codex models expose their supported concrete levels,
without the ambiguous **Default** effort option. Provider persistence, discovery,
and the UI model catalog were verified; inference was not tested. No Mac
model/permission settings or Codex OAuth accounts were copied, and the Mac's
`danger-full-access` setting remains unused.

The box now runs a boot-enabled `deepseek-harness.service` user service on
`127.0.0.1:8787`. It pins the tested DSH and Node installations independently
of the interactive mise `latest` selections. Do not start another process on
that port. Manage it with:

```sh
systemctl --user is-active deepseek-harness
systemctl --user restart deepseek-harness
```

Private phone/Mac access is enabled through Tailscale Serve on HTTPS port 8443.
A Nix-managed compatibility override enables this release's Models settings at
the exact trusted HTTPS origin; the original client otherwise disables settings
on non-loopback addresses. See [Durable Harness setup](deepseek-harness-remote.md).

For a new browser or expired login, run `dsh-web-login` privately on the box and
open its link on that device. After signing in, bookmark the clean HTTPS address.
The startup link contains a temporary credential: do not share or commit it.
Browser cookies persist across server restarts using the signing record in
`~/.dsh/.credentials.yaml` and default to a 30-day lifetime.

After choosing a default model, one-shot terminal tasks use:

```sh
dsh --profile headless "your task"
```

This release ships a web interface and headless mode, not a built-in interactive
terminal UI. Additional plugins can be managed with, for example:

```sh
dsh plugin --profile web list --depth=0
```

DSH owns `~/.dsh/profiles/`, `~/.dsh/settings.yaml`, and
`~/.dsh/.credentials.yaml`; these are excluded from chezmoi. The non-secret
Executor overlay is managed separately. See [Executor setup](executor.md) for
the shared Mac backend and its availability requirements.

## Verification and cleanup

Verified the DSH CLI, both profile help commands, profile composition, pnpm
and profile-manager execution, and a real web launch returning authenticated
HTML with HTTP 200. The temporary test server was stopped afterward. No paid
model request was made.

Cursor was the only extra installed agent CLI and was uninstalled. Extra
agent Executor entries and obsolete Cursor/Copilot managed config were removed
from box. Those runtime configs were backed up under
`~/.local/state/agent-cleanup/20260915-033653/`; saved sessions and credentials
were not removed. The shared chezmoi source no longer manages Cursor/Copilot
settings or distributes skills to the removed agents.
