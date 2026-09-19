# Durable DeepSeek Harness on the Linux box

## Deployment status

The Linux user service is installed, enabled at boot, and running on
`127.0.0.1:8787`. It uses the existing mise installation and `~/.dsh` state.
Browser authentication persistence and automatic crash recovery were tested.
After fixing the non-loopback settings limitation, the Models page and custom
provider editor were also verified in the actual Mac browser through Tailscale.
Only **Local Codex pool** is active in the managed web service. New chats default
to `gpt-6-astra` with explicit `xhigh` reasoning; all five coding models expose
their proxy-supported reasoning levels. Provider persistence and the UI's model
catalog were verified after a service restart. No machine reboot or model
inference request was performed.

The user completed the Tailscale authorization step. The private endpoint is
active at **https://z.tail5606b4.ts.net:8443/** and returns HTTP 401 without a
browser cookie, as expected. The existing HTTPS port 443 application remains
on `127.0.0.1:2283`.

The one-off setup wizard and temporary deployment/Serve snapshots have been
removed. The permanent `dsh-web-login` helper, service definitions, Nix GC roots,
and private pre-service backup remain.

## Architecture

```text
Phone + Mac browsers (Tailscale connected)
                  |
  https://z.tail5606b4.ts.net:8443
                  |
     Tailscale Serve --bg (tailnet only)
                  |
       DSH Web: 127.0.0.1:8787
                  |
          existing ~/.dsh state
```

`home/deepseek-harness.nix`, imported from `home/default.nix`, owns the Linux-only
unit and `dsh-web-login` helper. It does not start a service on the Mac. The
service launches existing, version-specific mise paths directly; it does not
run `npx`, resolve `latest`, or install/update packages during startup:

- Node `26.8.1`
- DSH `0.1.5-rc.1`
- pnpm `12.4.1` on its tool PATH

Do not prune these mise installations while this unit references them. Upgrade
by installing the desired versions, updating the module, rebuilding, and
retesting startup and authentication. The interactive CLI's mise selections
remain unchanged.

The service has `Restart=on-failure`, a 10-second retry delay, no startup-rate
cutoff, `UMask=0077`, and a 30-second systemd stop timeout. It uses
`WorkingDirectory=~/code`, `DSH_HOME=~/.dsh`, and
`DSH_TELEMETRY_MODE=DISABLED`. Its command explicitly binds loopback and trusts
only the chosen remote hostname/port in addition to DSH's loopback defaults.[1]

User lingering was already enabled in `users/z/nixos.nix`, and tailscaled was
already enabled system-wide. User services therefore do not require an
interactive login. Tailscale Serve's `--bg` configuration is stored by
tailscaled and resumes after daemon or machine restarts.[3]

### Current activation and Nix ownership

The unit and helper were built directly from the Home Manager expressions,
linked into this user's configuration, and activated without sudo. Their store
outputs have explicit GC roots under
`~/.local/state/deepseek-harness/gcroots/`; garbage collection will not remove
them before the next full system activation.

The module is also imported into the normal Nix configuration for future
rebuilds. A tailnet-interface port-8443 firewall declaration was added to
`machines/nixos/default.nix`, but a full NixOS switch was **not** run. The
existing system already runs tailscaled's networking; HTTPS connectivity through
the active Serve endpoint was verified without assuming that the new firewall
declaration is active.

After the new files are included in Git's index, a normal system rebuild can
use `--flake ~/nix-config#box`. Before that, a path flake includes untracked new
modules without requiring a commit:

```sh
sudo nixos-rebuild switch --flake path:/home/z/nix-config#box
```

Note that this repository's normal Home Manager activation also runs
`chezmoi apply` and `mise install`; it is broader than enabling this one service.
That is why the initial deployment used targeted unit activation instead.

## Remote settings compatibility override

The shipped settings client disables Host persistence whenever
`ctx.remote.$host.isLoopback` is false. That prevented the Models page from
loading at the Tailscale address even though browser authentication succeeded;
its error was “settings are unavailable in this browser.” The backend was not
rejecting the settings request: the client never made it.

`lib/dsh-remote-settings.nix` fetches the exact published
`@deepseek-ai/dsh-client-ui-settings@0.1.5-rc.2` artifact by its integrity hash
and changes only the persistence decision. It additionally permits
`window.location.origin === "https://z.tail5606b4.ts.net:8443"`. Other remote
origins, other ports, and plaintext URLs retain the original restriction.
Server authentication and Host/Origin validation are unchanged.

The service's `--patch` overlay disables the original `ui-settings` loader row
and inserts the replacement package from the immutable Nix store. It must use
**disable plus insert**: an existing-row patch does not replace that row's
package name. The global mise/npm installation remains unmodified, and other
DSH launches do not acquire this service-specific override.

Live browser verification confirmed that **Settings → Models** shows
**Add provider** and **Add a custom provider**, and that the custom-provider
editor opens. No provider was saved during that check.

When upgrading Harness, recheck whether upstream has removed this limitation
and remove this compatibility package/overlay if it is no longer needed.

## Browser login survives restarts

**Correction to the original research:** the random startup token rotates, but
the installed version's browser cookie does **not** inherently expire on restart.
The Connection plugin persists its signing record at
`client-connection/browser-session` in `~/.dsh/.credentials.yaml`. Cookies default
to a 30-day absolute lifetime and bind the hostname plus port. Preserving that
file allows the same authenticated browser to reconnect after a restart.[2]

For the first login on each device, run privately on the box:

```sh
dsh-web-login
```

Open its generated HTTPS link on the phone or Mac with Tailscale connected.
The helper reads only the running service's journal invocation and rewrites the
local bootstrap URL to the trusted Tailscale authority. It does not read or
print the credential store. Its output is itself a temporary credential: do
not paste it into chat, Git, screenshots, or shared logs.

After signing in, bookmark the clean URL:

```text
https://z.tail5606b4.ts.net:8443/
```

A new browser, clearing cookies, or cookie expiry requires another login link.
If the startup journal has rotated away, restarting the service generates a
new link. Existing unexpired cookies remain valid. Deleting or replacing the
browser-session signing record revokes cookies on the next activation.[2]

The installed cookies are HttpOnly and SameSite=Strict, but are not marked
Secure because DSH's own transport is loopback HTTP. Access this remote authority
only through HTTPS; do not additionally publish a plaintext endpoint.[2]

## Service management

```sh
systemctl --user is-active deepseek-harness
systemctl --user is-enabled deepseek-harness
systemctl --user restart deepseek-harness
systemctl --user stop deepseek-harness
```

For detailed diagnostics:

```sh
journalctl --user -u deepseek-harness --since today
```

The startup log contains the bootstrap token. Review and redact logs before
sharing them; `dsh-web-login` is the focused way to retrieve the current link.

### Verification performed

- Nix-built unit and helper successfully evaluated and built.
- Unit enabled under `default.target`; user lingering verified enabled.
- Service listening only on `127.0.0.1:8787`; proxy still on `127.0.0.1:8317`.
- Unauthenticated index and API requests return 401.
- An untrusted Host returns 403.
- A valid startup link exchanges for a signed cookie and authenticated HTTP 200.
- After `systemctl --user restart`, the same cookie still returns 200 and the
  old process token returns 401. The helper returns the new invocation's link.
- After killing the main process, systemd automatically starts a new process
  and restores the HTTP authentication boundary.
- In the actual Mac browser, the Models provider directory and custom-provider
  editor load successfully through the Tailscale endpoint.
- The Mac configuration does not install this Linux-only login helper.
- Tailscale Serve reports port 8443 as tailnet-only, forwarding to the loopback
  Harness listener; the original port 443 route is unchanged.
- The HTTPS endpoint returns the expected unauthenticated 401 when checked from
  the box after the user completed setup.

An actual OS reboot and a phone-browser test were not performed. The Mac
browser test covers the settings workflow, not model inference. No active model
work was created for these tests.

## Persistent state and backups

Keep these separate from the executable installation:

| Data | Location |
| --- | --- |
| Harness settings, credentials, sessions, skills | `~/.dsh/` |
| Project files | Existing project directories |
| CLIProxyAPI account state | Existing `~/.cli-proxy-api/` |
| Service/helper definitions | This Nix repository |

`~/.dsh` and `~/.local/state/deepseek-harness` are mode 0700; the Harness credential
file remains mode 0600. A private pre-service snapshot was created at:

```text
~/.local/state/deepseek-harness/backups/before-service-20260919T045545Z.tar.gz
```

That is a local rollback snapshot, **not** an off-machine disaster-recovery
backup or a scheduled backup policy. It contains credentials and must stay
private. Back up state and projects to encrypted off-machine storage separately.

A process crash or power loss can interrupt a model request or tool command.
Automatic service restart does not guarantee automatic resumption of the
interrupted task. Recover the session, inspect completed work, and continue
explicitly. This setup also assumes the machine boots successfully and its
filesystem is available; it does not configure firmware power restoration or
unattended disk unlocking.

The node's inspected Tailscale key expiry is **2027-02-22**. Review device key
expiry in the tailnet admin console if the host must remain unattended beyond
that date; this setup did not change tailnet identity policy.

## Model providers

### Local Codex pool — configured

The custom provider `codex-local` is configured with display name **Local Codex
pool**, base URL `http://127.0.0.1:8317/v1`, and protocol `openai-responses`.
It exposes the proxy's discovered coding models:

- `gpt-5.5`
- `gpt-5.6-luna`
- `gpt-5.6-sol`
- `gpt-5.6-terra`
- `gpt-6-astra`

Image-generation models and the specialized auto-review route were not added
as general coding-agent models. Settings reference `CODEX_LOCAL_API_KEY`; its
value was copied privately from the existing proxy client-key file into DSH's
credential store through the authenticated credentials API. No management key,
Codex OAuth token, or secret was put in this repository. CLIProxyAPI still owns
account refresh and selection; its accounts and routing were not changed.[4][5]

DSH registered the provider without catalog errors, and model discovery through
DSH succeeded using the stored credential. The discovery request supplies the
provider ID, base URL, and protocol, just as the Models editor does; a provider
ID alone is insufficient for this adapter's discovery request. Inference was
not tested. New chats now default to `codex-local` / `gpt-6-astra` / `xhigh`.
An existing conversation can retain its own model and effort selection.

#### Model and reasoning controls

Open an existing conversation and click the model control near the send button:
**Model** selects a model; **Effort** selects reasoning. `/model` opens the model
picker, but effort selection is in the composer control. This release does not
show these controls on the blank, pre-session new-chat screen.

Each model's `reasoningEfforts` maps selectable levels to the same wire spelling.
The choices were checked against the local proxy's read-only
`/v0/management/model-definitions/codex` capability metadata:

- `gpt-5.5`: `low`, `medium`, `high`, `xhigh`.
- `gpt-5.6-luna`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-6-astra`: the same levels
  plus `max`.

The provider's explicit `reasoning: xhigh` makes every model advertise
`defaultEffort: xhigh`; the saved new-agent selection also carries
`reasoningEffort: xhigh`. Consequently the composer omits its synthetic
**Default** (provider-decides) option while keeping the concrete effort choices.
The UI's `session/modelCatalog` RPC was checked for all choices and defaults.
The management key was used only for local capability inspection, never as
Harness's provider credential.

#### Other providers and persistence

The service's Nix-managed Cordis overlay disables `llm-deepseek` and changes the
composition fallback model to `codex-local` / `gpt-6-astra`. This removes the
built-in DeepSeek route, rather than merely hiding its models or clearing a key.
The overlay is service-specific; other CLI profiles are not disabled by it.
OpenCode Go was removed from the shared settings at the user's request, leaving
only Local Codex pool configured.

Provider/default/effort settings were written with revision-checked API mutations.
The composition change required a service restart; the registered providers,
saved Codex credential, Astra default, and existing browser cookie survived it.
The final explicit `xhigh` choice was applied live afterward. Private pre-change
settings/credentials snapshots remain under
`~/.local/state/deepseek-harness/backups/`; no one-off setup scripts are retained.

### OpenCode Go — removed, not tested

If adding Go again, note that it documents incomplete session-header support in some
Harness adapters. The installed Chat Completions path did not show dynamic
`x-opencode-session` support. Verify or fix per-conversation headers before
calling that route working; do not substitute one static ID for all sessions.
Go's base URL is `https://opencode.ai/zen/go/v1`, and each selected model must
use the protocol documented for it.[6][7]

## Security and removal

DSH is experimental, unaudited software capable of executing commands as this
user. Loopback and Tailscale reduce network exposure but are not an OS sandbox.
Retain approval controls and restrict access with tailnet grants/ACLs if other
users or devices should not control the agent.[8]

To recreate the private listener if its configuration is ever removed:

```sh
sudo tailscale serve --bg --https=8443 http://127.0.0.1:8787
```

To remove only the Harness Tailscale listener:

```sh
sudo tailscale serve --https=8443 off
```

Do not use `tailscale serve reset`, which also removes the existing app's
configuration. Stop/disable the DSH service independently, remove its module
import if retiring it, and preserve state until backups and recovery are settled.

## Primary sources

1. [DSH CLI reference](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/cli/reference/README.md).
2. Installed `@deepseek-ai/dsh-client-connection/README.md` for `0.1.5-rc.1`,
   section “Browser authentication and request trust”; verified by live restart
   testing. [Upstream reference](https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/client/connection/README.md).
3. [Tailscale Serve reference](https://tailscale.com/kb/1242/tailscale-serve).
4. [DSH model configuration](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/guide/providers.md).
5. [CLIProxyAPI capabilities](https://help.router-for.me/introduction/what-is-cliproxyapi)
   and this repository's `home/cli-proxy.nix` and `bin/cli-proxy-local.py`.
6. [OpenCode Go documentation](https://opencode.ai/docs/go/).
7. [Go maintainer session-header discussion](https://github.com/deepseek-ai/deepseek-harness/discussions/5495).
8. [DSH safety notice](https://github.com/deepseek-ai/deepseek-harness/blob/master/SAFETY.md).
