import contextlib
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import tomllib
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "chezmoi/private_dot_local/bin/executable_sync-agent-mcp"
loader = importlib.machinery.SourceFileLoader("sync_agent_mcp", str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
sync = importlib.util.module_from_spec(spec)
loader.exec_module(sync)


class ExecutorAgentConfigTest(unittest.TestCase):
    def test_json_preserves_other_settings_and_servers(self):
        old = {"model": "keep", "mcpServers": {"other": {"command": "keep"}, "executor": {"url": "old"}}}
        result = json.loads(sync.json_config(json.dumps(old), {"command": "bridge"}))
        self.assertEqual(result["model"], "keep")
        self.assertEqual(result["mcpServers"]["other"], {"command": "keep"})
        self.assertEqual(result["mcpServers"]["executor"], {"command": "bridge"})

    def test_toml_preserves_other_settings_and_removes_old_headers(self):
        old = '''# keep this comment
model = "keep"
[mcp_servers.executor]
url = "old"
[mcp_servers.executor.http_headers]
Authorization = "old-secret"
[mcp_servers.other]
command = "keep"
[projects."/home/z/code"]
trust_level = "trusted"
'''
        entry = {"command": "/home/z/.local/bin/executor-mcp", "args": [], "startup_timeout_sec": 30}
        result = sync.toml_config(old, entry)
        parsed = tomllib.loads(result)
        self.assertIn("# keep this comment", result)
        self.assertNotIn("old-secret", result)
        self.assertEqual(parsed["model"], "keep")
        self.assertEqual(parsed["projects"], tomllib.loads(old)["projects"])
        self.assertEqual(parsed["mcp_servers"]["other"], {"command": "keep"})
        self.assertEqual(parsed["mcp_servers"]["executor"], entry)
        self.assertEqual(sync.toml_config(result, entry), result)

    def test_toml_quoted_server(self):
        for name in ('"executor"', "'executor'"):
            result = sync.toml_config(f'[mcp_servers.{name}]\ncommand = "old"\n', {"command": "new"})
            self.assertEqual(tomllib.loads(result)["mcp_servers"]["executor"]["command"], "new")

    def test_unusual_toml_fails_closed(self):
        with self.assertRaises(ValueError):
            sync.toml_config('["mcp_servers"."executor"]\ncommand = "old"\n', {"command": "new"})

    def test_apply_idempotent_backup_permissions_and_pi_overlay(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            home = Path(directory)
            shared = home / ".config/mcp/mcp.json"
            shared.parent.mkdir(parents=True)
            shared.write_text('{"theme": "keep"}\n')
            overlay = home / ".pi/agent/mcp.json"
            overlay.parent.mkdir(parents=True)
            overlay.write_text('{"mcpServers": {"executor": {"disabled": true}}}\n')
            self.assertEqual(sync.apply(home), 3)
            self.assertEqual(sync.apply(home), 0)
            self.assertIn('"disabled": true', overlay.read_text())
            backup = home / ".local/state/executor-agent-config/backups/.config/mcp/mcp.json"
            self.assertEqual(backup.read_text(), '{"theme": "keep"}\n')
            self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
            for path in (home / ".codex/config.toml", shared):
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            command = str(home / ".local/bin/executor-mcp")
            codex = tomllib.loads((home / ".codex/config.toml").read_text())
            self.assertEqual(codex["mcp_servers"]["executor"]["command"], command)
            opencode = json.loads((home / ".config/opencode/opencode.jsonc").read_text())
            self.assertEqual(opencode["mcp"]["executor"]["command"], [command])
            for name in (".claude.json", ".cursor", ".gemini", ".copilot", ".grok"):
                self.assertFalse((home / name).exists(), name)

    def test_mac_uses_local_executor_and_preserves_model_settings(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            home = Path(directory)
            codex = home / ".codex/config.toml"
            codex.parent.mkdir()
            codex.write_text('model = "keep-model"\n[mcp_servers.executor]\nurl = "http://old"\n[mcp_servers.executor.http_headers]\nAuthorization = "old-token"\n')
            shared = home / ".config/mcp/mcp.json"
            shared.parent.mkdir(parents=True)
            shared.write_text(json.dumps({"mcpServers": {"executor": {"url": "http://old", "headers": {"Authorization": "old-token"}}}}))
            self.assertEqual(sync.apply(home, "darwin"), 3)
            self.assertEqual(sync.apply(home, "darwin"), 0)
            entry = json.loads(shared.read_text())["mcpServers"]["executor"]
            self.assertEqual(entry["command"], "/Applications/Executor.app/Contents/Resources/executor/executor")
            self.assertEqual(entry["args"], ["mcp", "--no-artifacts", "--search-tools", "--elicitation-mode", "browser"])
            self.assertNotIn("headers", entry)
            parsed = tomllib.loads(codex.read_text())
            self.assertEqual(parsed["model"], "keep-model")
            self.assertEqual(parsed["mcp_servers"]["executor"], {**entry, "startup_timeout_sec": 30})
            opencode = json.loads((home / ".config/opencode/opencode.jsonc").read_text())
            self.assertEqual(opencode["mcp"]["executor"]["command"], [entry["command"], *entry["args"]])
            self.assertNotIn("old-token", codex.read_text())

    def test_uninstalled_agent_settings_are_untouched(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            home = Path(directory)
            old = home / ".claude.json"
            old.write_text('{"saved": true}\n')
            sync.apply(home)
            self.assertEqual(old.read_text(), '{"saved": true}\n')

    def test_invalid_config_does_not_partially_apply(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            opencode = home / ".config/opencode/opencode.jsonc"
            opencode.parent.mkdir(parents=True)
            opencode.write_text("invalid JSON")
            with self.assertRaises(ValueError):
                sync.apply(home)
            self.assertFalse((home / ".codex/config.toml").exists())
            self.assertFalse((home / ".config/mcp/mcp.json").exists())
            self.assertEqual(opencode.read_text(), "invalid JSON")

    def test_symlink_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            target = home / "original.json"
            target.write_text("{}")
            shared = home / ".config/mcp/mcp.json"
            shared.parent.mkdir(parents=True)
            shared.symlink_to(target)
            with self.assertRaises(ValueError):
                sync.apply(home)
            self.assertEqual(target.read_text(), "{}")


if __name__ == "__main__":
    unittest.main()
