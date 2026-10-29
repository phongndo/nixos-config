---
name: previews
description: Share HTML artifacts or development apps for viewing in a browser on another device, through the shared Previews tab on Linux host z. Use when the user wants to preview, view, or share a page or app.
---

# Shared previews on z

Serve HTML artifacts and development apps from the **Previews** tab in Rex
session **$** on the Linux host z. Mac and phone browsers reach it through
Tailscale. Files and server processes stay on z; from another host, work on z
over SSH.

## Find or start the shared tab

Inspect `rex ls --json` and `rex window ls -s '$' --json`. Find the **Previews**
window and its blocks; inspect their processes before sending terminal input.
Reuse the running static server. If the tab is missing, start it with:

```sh
rex window new -s '$' Previews --focus=false --keep-open --json \
  -- "$HOME/.agents/skills/previews/serve"
```

The launcher uses miniserve from `~/nix-config`'s pinned nixpkgs without a global
installation. Port **8765** is reserved for shared static files. The tab keeps
running when an agent or Rex app disconnects. Closing it or rebooting stops the
server; the command above recreates it. Published files survive in the data
directory.

## Publish HTML or files

The publish directory is `${XDG_DATA_HOME:-$HOME/.local/share}/previews`.
Create a task-specific subdirectory, then copy only the requested output and
its assets. Preserve other tasks' files. For example:

```sh
mkdir -p "$HOME/.local/share/previews/my-task"
cp /tmp/my-lesson.html "$HOME/.local/share/previews/my-task/index.html"
```

Link directly to the HTML filename, for example
`http://z.tail5606b4.ts.net:8765/my-task/index.html`. Directory URLs show a file
listing. The hostname comes from `tailscale status --json`; recheck it if a
link stops working. Verify the URL returns the expected content before sharing
it. Use a browser check when the artifact has interactive behavior.

## Run a development app

Add a labelled pane to the existing **Previews** window using `rex split` with
one of that window's block IDs as the anchor. Keep focus unchanged. Use the
project's declared tooling and environment; choose a free port other than 8765
and include the project and port in the pane label. Consult the app's command
help to bind it to this host's `tailscale ip -4` address. Configure the specific
Tailscale hostname if its host checks require it.

Return the app's hostname-and-port URL after checking the actual response. A
static file server does not run application backends. App processes need their
own panes and ports. If HTTPS is required, inspect `tailscale serve status`
before adding a private Serve route; preserve existing routes. Stop only your
own pane when the app is no longer needed, leaving the shared file server up.

## Access and limits

This is a private preview workflow. Tailscale policy controls which devices can
reach each port; allowed visitors can read the published files. Publish only
shareable artifacts, with secrets and repository internals left outside the
publish directory. The static launcher blocks symlinks, keeps hidden files
hidden, and enables no browser upload or deletion. Keep its directory-listing
mode; the launcher records the reason for avoiding automatic index selection.

Development apps may expose debugging or write operations, so review what a
particular app makes available before sharing it. Bind previews to Tailscale,
preserve normal app host checks, and keep public Funnel exposure and access-rule
changes outside this workflow. Browser access does not require copying files
to the Mac or opening a remote shell on it.
