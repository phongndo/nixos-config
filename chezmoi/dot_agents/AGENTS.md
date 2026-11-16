y is a Mac on nix-darwin with Determinate Nix and z is NixOS, both configured in ~/nix-config; if `IN_NIX_SHELL` is set, the project's dev shell is already active, so run tools directly, otherwise use `nix develop -c <command>`; use `nix shell nixpkgs#<package> -c <command>` for one-off tools.

Project secrets live in 1Password Environments: on y, manage them with the 1Password MCP server; on z, run commands with `op run --environment <id> -- <command>`. Never print secret values.

Use Rex, not tmux, for terminal sessions, tabs, panes, and commands that outlive a tool call or that I should see (dev servers, watchers, long builds and test runs); run short commands directly. Load the `rex` skill before your first Rex command. In a Rex terminal, work in `$REX_SESSION`; outside one (`REX_SESSION` unset), leave my sessions alone: create one for the task with `rex new <task-label> -c <dir> --json`, use its `.session_id` wherever the skill says `$REX_SESSION`, and tell me its name. To run on z from y, use `rex -S z`.

When done, clean up what you started: Rex panes, tabs, and sessions you created (not your own pane unless asked), background processes, temp files, branches, and worktrees; mention anything left running.

Executor (the `executor` MCP server) connects my apps: Discord, Exa, Fastmail, Figma, Firecrawl, GitHub, Google (Gmail, Calendar, Drive, Docs, Sheets, Slides, Forms, Contacts, Tasks, Meet, Photos), Hacker News, Hugging Face, Kalshi, Notion, Polymarket US, Slack, Spotify, T3 Code, Tailscale, and YouTube; find tools with its `search` tool.

If I tell you to use a tool, or you need one to finish the task, treat that as my approval: call it without asking first, and when an Executor call pauses for approval, resume it as approved.
