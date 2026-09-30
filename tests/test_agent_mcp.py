"""Native agent MCP configuration stays host-local and preserves Pi preferences."""
import contextlib
import io
import json
from pathlib import Path
import runpy
import tempfile
import tomllib
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "chezmoi"
SYNC = runpy.run_path(str(SOURCE / "private_dot_local/bin/executable_sync-agent-mcp"))


class AgentMcpTest(unittest.TestCase):
    def test_native_configs_on_both_hosts_and_idempotence(self):
        for platform in ("darwin", "linux"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as temp:
                home = Path(temp)
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(SYNC["apply"](home, platform), 3)
                    self.assertEqual(SYNC["apply"](home, platform), 0)
                pi = json.loads((home / ".pi/agent/mcp.json").read_text())["mcpServers"]["executor"]
                codex = tomllib.loads((home / ".codex/config.toml").read_text())["mcp_servers"]["executor"]
                opencode = json.loads((home / ".config/opencode/opencode.jsonc").read_text())["mcp"]["executor"]
                if platform == "darwin":
                    command = "/Applications/Executor.app/Contents/Resources/executor/executor"
                    args = ["mcp", "--scope", str(home / ".executor"), "--no-artifacts",
                            "--search-tools", "--elicitation-mode", "browser"]
                else:
                    command, args = str(home / ".local/bin/executor-mcp"), []
                self.assertEqual(pi, {"command": command, "args": args, "exposure": "direct"})
                self.assertEqual(codex, {"command": command, "args": args, "startup_timeout_sec": 30})
                self.assertEqual(opencode, {"type": "local", "command": [command, *args],
                                           "enabled": True, "timeout": 30000})
                self.assertFalse((home / ".config/mcp/mcp.json").exists())
                self.assertEqual((home / ".pi/agent/mcp.json").stat().st_mode & 0o777, 0o600)

    def test_migrates_legacy_toggle_without_resetting_native_preferences(self):
        for disabled in (False, True):
            with self.subTest(disabled=disabled):
                config = {"mcpServers": {"executor": {"disabled": disabled}}}
                entry = {"command": "/local/executor", "args": []}
                updated = json.loads(SYNC["pi_config"](json.dumps(config), entry))
                self.assertEqual(updated["mcpServers"]["executor"], {
                    **entry, "enabled": not disabled, "exposure": "direct",
                })
                self.assertEqual(json.loads(SYNC["pi_config"](json.dumps(updated), entry)), updated)

    def test_replaces_only_executor_connection_and_preserves_native_choices(self):
        for enabled in (False, True):
            with self.subTest(enabled=enabled):
                preferences = {"enabled": enabled, "exposure": "deferred", "timeout": 120,
                               "toolExposure": {"execute": "direct", "search_*": "deferred"}}
                other = {"url": "https://example.invalid/mcp", "enabled": False}
                old = {"autoEnableCodemode": False, "mcpServers": {
                    "other": other,
                    "executor": {**preferences, "type": "http", "url": "http://old.invalid/mcp",
                                 "headers": {"Authorization": "Bearer test-secret"},
                                 "oauth": {"clientId": "old"}, "env": {"OLD": "value"},
                                 "cwd": "/old"},
                }}
                entry = {"command": "/local/executor", "args": ["mcp"]}
                updated = json.loads(SYNC["pi_config"](json.dumps(old), entry))
                self.assertEqual(updated, {"autoEnableCodemode": False, "mcpServers": {
                    "other": other, "executor": {**preferences, **entry},
                }})

    def test_legacy_file_is_not_rewritten_and_native_file_is_backed_up(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            legacy = home / ".config/mcp/mcp.json"
            legacy.parent.mkdir(parents=True)
            legacy.write_text('{"mcpServers":{"unrelated":{"command":"keep"}}}\n')
            native = home / ".pi/agent/mcp.json"
            native.parent.mkdir(parents=True)
            original = '{"mcpServers":{"executor":{"disabled":true}}}\n'
            native.write_text(original)
            with contextlib.redirect_stdout(io.StringIO()):
                SYNC["apply"](home, "darwin")
                SYNC["apply"](home, "darwin")
            backup = home / ".local/state/executor-agent-config/backups/.pi/agent/mcp.json"
            self.assertEqual(backup.read_text(), original)
            self.assertEqual(legacy.read_text(), '{"mcpServers":{"unrelated":{"command":"keep"}}}\n')
            self.assertFalse(json.loads(native.read_text())["mcpServers"]["executor"]["enabled"])

    def test_invalid_config_aborts_before_any_writes(self):
        for path, content in ((".pi/agent/mcp.json", '{"mcpServers": []}'),
                              (".codex/config.toml", "[broken")):
            with self.subTest(path=path), tempfile.TemporaryDirectory() as temp:
                home = Path(temp)
                invalid = home / path
                invalid.parent.mkdir(parents=True)
                invalid.write_text(content)
                with self.assertRaises(ValueError):
                    SYNC["apply"](home, "darwin")
                self.assertEqual(invalid.read_text(), content)
                self.assertEqual([p for p in home.rglob("*") if p.is_file()], [invalid])


if __name__ == "__main__":
    unittest.main()
