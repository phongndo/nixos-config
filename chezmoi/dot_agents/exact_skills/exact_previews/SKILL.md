---
name: previews
description: Use when the user wants to see an HTML page, artifact, or running dev app from z in a browser, or asks for a preview link to open on their Mac or phone.
---

# Shared previews on z

z serves previews over Tailscale to Mac and phone browsers. Files and processes
stay on z; from another host, work on z over SSH. z's hostname is
`tailscale status --json | jq -r .Self.DNSName` without the trailing dot.

## Publish HTML or files

The `previews` user service always serves `~/.local/share/previews` read-only at
`http://<z's hostname>:8765/`. It starts at boot and restarts itself; check it
with `systemctl --user status previews` rather than starting another server.

Create a task-specific subdirectory, then copy only the requested output and its
assets. Preserve other tasks' files. For example:

```sh
mkdir -p ~/.local/share/previews/my-task
cp /tmp/my-lesson.html ~/.local/share/previews/my-task/index.html
```

Link directly to the HTML file, for example
`http://<z's hostname>:8765/my-task/index.html`; a directory URL shows a file
listing. Verify the URL returns the expected content before sharing it. Use a
browser check when the artifact has interactive behavior.

## Run a development app

Run each app as its own transient user service, so it outlives the agent's
session and stays easy to inspect:

```sh
systemd-run --user --unit preview-<project> --collect --same-dir -E PATH="$PATH" \
  -- <the project's dev command>
```

Use the project's declared tooling, for example `nix develop -c npm run dev`.
Bind the app to `tailscale ip -4` on a free port from 8766 to 8799, and allow z's
hostname if the app checks hosts; consult its command help for the flags. Check
the actual response before returning the URL. Read its output with
`journalctl --user -u preview-<project>`, and stop it with
`systemctl --user stop preview-<project>` when it's no longer needed.

If HTTPS is required, inspect `tailscale serve status` before adding a private
Serve route, and preserve existing routes.

## Access and limits

This is a private preview workflow. Tailscale policy controls which devices can
reach each port; allowed visitors can read the published files. Publish only
shareable artifacts, with secrets and repository internals left outside the
publish directory. The static server blocks symlinks, keeps hidden files hidden,
and allows no upload or deletion, and the sandbox keeps it read-only.

Development apps may expose debugging or write operations, so review what a
particular app makes available before sharing it. Bind previews to Tailscale,
preserve normal app host checks, and keep public Funnel exposure and access-rule
changes outside this workflow.
