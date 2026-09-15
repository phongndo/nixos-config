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

No provider credentials or Mac model/permission settings were copied. Configure
a working provider in the web UI before asking DSH to run model tasks. Until
then, the application can launch, but a model task is not expected to succeed.
The Mac's `danger-full-access` setting was deliberately not copied.

Start the web UI on the box:

```sh
dsh web --no-open --port 8787
```

To use the box's web UI from the Mac, run this in a Mac terminal and keep it
open:

```sh
ssh -t -o ExitOnForwardFailure=yes -L 8787:127.0.0.1:8787 box \
  'mise exec -- dsh web --no-open --port 8787'
```

Open the full `http://127.0.0.1:8787/?...` startup URL printed by DSH. Its token
is a temporary UI credential: do not share it or commit it. The application
stays loopback-only; no firewall change or public bind is needed. Ctrl-C stops
the UI and tunnel. If port 8787 is occupied locally, choose another free port
consistently in all three places in that command.

After configuring a provider, one-shot terminal tasks use:

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
