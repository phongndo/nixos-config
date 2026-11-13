y is a Mac on nix-darwin with Determinate Nix and z is NixOS, both configured in ~/nix-config; if `IN_NIX_SHELL` is set, the project's dev shell is already active, so run tools directly, otherwise use `nix develop -c <command>`; use `nix shell nixpkgs#<package> -c <command>` for one-off tools.

Project secrets live in 1Password Environments: on y, manage them with the 1Password MCP server; on z, run commands with `op run --environment <id> -- <command>`. Never print secret values.

Use Rex instead of tmux for terminal sessions, tabs, panes, and long-running commands; see the `rex` skill or `rex skill show`.

When done, clean up what you started: Rex panes and tabs (not your own unless asked), background processes, temp files, branches, and worktrees; mention anything left running.

Executor (the `executor` MCP server) connects my apps: Discord, Exa, Fastmail, Figma, Firecrawl, GitHub, Google (Gmail, Calendar, Drive, Docs, Sheets, Slides, Forms, Contacts, Tasks, Meet, Photos), Hacker News, Hugging Face, Kalshi, Notion, Polymarket US, Slack, Spotify, T3 Code, Tailscale, and YouTube; find tools with its `search` tool.

If I tell you to use a tool, or you need one to finish the task, treat that as my approval: call it without asking first, and when an Executor call pauses for approval, resume it as approved.
