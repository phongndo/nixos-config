"""Print this running DSH service's private Tailscale browser bootstrap URL.

Run explicitly in a trusted terminal. The output is a temporary credential;
never paste it into chat, commit it, or collect it in shared diagnostics.
"""

import argparse
import re
import subprocess
import sys
from urllib.parse import parse_qs, urlsplit, urlunsplit


UNIT = "deepseek-harness.service"


def login_url(log, authority):
    """Rewrite only a genuine local DSH startup URL, preserving its query."""
    remote = urlsplit("https://" + authority)
    if (
        not remote.hostname
        or remote.username is not None
        or remote.password is not None
        or remote.path
        or remote.query
        or remote.fragment
        or remote.netloc != authority
    ):
        raise ValueError("Invalid remote authority")
    # Validate the port, including urllib's out-of-range check.
    _ = remote.port
    for line in reversed(log.splitlines()):
        if "dsh web:" not in line:
            continue
        match = re.search(r"http://127\.0\.0\.1:8787/\?[^\s\x1b]+", line)
        if match is None:
            continue
        local = urlsplit(match.group())
        token = parse_qs(local.query).get("token", [])
        if len(token) != 1 or not token[0]:
            continue
        return urlunsplit(("https", authority, "/", local.query, ""))
    raise ValueError("No startup link found for this service invocation")


def command(*args):
    return subprocess.run(
        args, check=True, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=15,
    ).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--authority", required=True)
    args = parser.parse_args()
    try:
        state = dict(
            line.split("=", 1)
            for line in command(
                "systemctl", "--user", "show", UNIT,
                "--property=ActiveState", "--property=InvocationID",
            ).splitlines()
            if "=" in line
        )
        invocation = state.get("InvocationID", "")
        if state.get("ActiveState") != "active" or not re.fullmatch(
            r"[0-9a-f]{32}", invocation
        ):
            raise ValueError("Service is not active")
        log = command(
            "journalctl", "--user", "--unit=" + UNIT,
            "--invocation=" + invocation, "--output=cat", "--no-pager",
            "--quiet", "--grep=dsh web:",
        )
        print(login_url(log, args.authority))
    except (OSError, ValueError, subprocess.SubprocessError):
        # Do not echo logs, subprocess output, or credential-bearing URLs.
        print(
            "Cannot obtain the current Harness login link. Check that "
            "deepseek-harness.service is active and has finished starting. "
            "If its startup journal was rotated away, restart the service "
            "to generate a fresh link.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
