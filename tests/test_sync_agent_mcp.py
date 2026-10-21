import contextlib
import io
import json
from pathlib import Path
import runpy
import tempfile
import tomllib
import unittest


SYNC = runpy.run_path(str(
    Path(__file__).resolve().parents[1]
    / "chezmoi/private_dot_local/bin/executable_sync-agent-mcp"
))
ENTRY = {"command": "/local/executor", "args": ["mcp"]}


class RexMcpSyncTests(unittest.TestCase):
    def test_existing_remote_entry_keeps_runtime_formatting(self):
        old = json.dumps({"mcpServers": {"superlogical": {
            "type": "http", "url": SYNC["SUPERLOGICAL_URL"],
        }}}, separators=(",", ":"))
        self.assertEqual(SYNC["remote_config"](old, transport="http"), old)

    def test_all_harnesses_receive_remote_server_on_both_hosts(self):
        for platform in ("darwin", "linux"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                commented = home / ".config/opencode/opencode.jsonc"
                commented.parent.mkdir(parents=True)
                original = '// Local settings\n{"mcp":{"other":{"type":"remote","url":"https://example.test"}}}\n'
                commented.write_text(original)
                with contextlib.redirect_stdout(io.StringIO()):
                    SYNC["apply"](home, platform)
                for relative, key, transport in (
                    (".pi/agent/mcp.json", "mcpServers", None),
                    (".claude.json", "mcpServers", "http"),
                    (".fx/mcp.json", "mcp", "http"),
                    (".config/opencode/opencode.json", "mcp", "remote"),
                ):
                    entry = json.loads((home / relative).read_text())[key]["superlogical"]
                    self.assertEqual(entry["url"], SYNC["SUPERLOGICAL_URL"])
                    self.assertEqual(entry.get("type"), transport)
                    self.assertNotIn("command", entry)
                codex = tomllib.loads((home / ".codex/config.toml").read_text())
                self.assertEqual(codex["mcp_servers"]["superlogical"]["url"], SYNC["SUPERLOGICAL_URL"])
                self.assertEqual(commented.read_text(), original)
                self.assertEqual(SYNC["plan"](home, platform), {})

    def test_remote_sync_preserves_settings_oauth_and_other_servers(self):
        server = {"url": "https://old.test", "enabled": False,
                  "exposure": "deferred", "oauth": {"clientId": "local-client"}}
        old = {"custom": True, "mcpServers": {"other": ENTRY, "superlogical": server}}
        result = json.loads(SYNC["remote_config"](json.dumps(old)))
        self.assertEqual(result, {**old, "mcpServers": {
            **old["mcpServers"], "superlogical": {**server, "url": SYNC["SUPERLOGICAL_URL"]},
        }})

    def test_codex_preserves_comments_controls_and_nested_oauth(self):
        old = '# Keep this comment\nmodel = "test"\n[mcp_servers.other]\ncommand = "other"\n[mcp_servers.superlogical]\ncommand = "old"\nenabled = false\n[mcp_servers.superlogical.oauth]\nclient_id = "local-client"\n'
        result = SYNC["toml_config"](old, {"url": SYNC["SUPERLOGICAL_URL"]}, "superlogical")
        self.assertTrue(result.startswith('# Keep this comment\nmodel = "test"'))
        parsed = tomllib.loads(result)
        self.assertEqual(parsed["mcp_servers"]["other"], {"command": "other"})
        self.assertEqual(parsed["mcp_servers"]["superlogical"], {
            "url": SYNC["SUPERLOGICAL_URL"], "enabled": False,
            "oauth": {"client_id": "local-client"},
        })

    def test_opencode_current_schema_preserves_other_servers(self):
        old = {"mcp": {"servers": {"other": ENTRY}}}
        result = json.loads(SYNC["remote_config"](json.dumps(old), "mcp", "remote"))
        self.assertEqual(result["mcp"]["servers"]["other"], ENTRY)
        self.assertEqual(result["mcp"]["servers"]["superlogical"], {
            "type": "remote", "url": SYNC["SUPERLOGICAL_URL"],
        })

    def test_invalid_claude_profile_prevents_any_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / ".claude.json").write_text("{invalid")
            with self.assertRaises(ValueError):
                SYNC["apply"](home)
            self.assertFalse((home / ".pi").exists())


class FxMcpSyncTests(unittest.TestCase):
    def test_new_profile_uses_fx_local_transport(self):
        self.assertEqual(
            json.loads(SYNC["fx_config"]("", ENTRY)),
            {"mcp": {"executor": {"type": "local", **ENTRY}}},
        )

    def test_preserves_servers_and_user_controls_when_replacing_connection(self):
        old = {
            "custom_setting": True,
            "mcp": {
                "other": {"type": "http", "url": "https://example.test/mcp"},
                "executor": {
                    "type": "http", "url": "https://obsolete.test/mcp",
                    "environment": {"OLD": "value"}, "headers": {"X-Old": "value"},
                    "command": "old", "args": ["old"],
                    "enabled": False, "required": True, "operation_timeout_ms": 90000,
                },
            },
        }
        result = json.loads(SYNC["fx_config"](json.dumps(old), ENTRY))
        self.assertEqual(result["custom_setting"], old["custom_setting"])
        self.assertEqual(result["mcp"]["other"], old["mcp"]["other"])
        self.assertEqual(result["mcp"]["executor"], {
            "type": "local", **ENTRY,
            "enabled": False, "required": True, "operation_timeout_ms": 90000,
        })

    def test_legacy_servers_remain_visible_after_adding_preferred_map(self):
        old = {"mcpServers": {"other": {"command": ["other-server"]}}}
        result = json.loads(SYNC["fx_config"](json.dumps(old), ENTRY))
        self.assertEqual(result["mcpServers"], old["mcpServers"])
        self.assertEqual(result["mcp"]["other"], old["mcpServers"]["other"])

    def test_both_hosts_use_local_executor_and_sync_is_idempotent(self):
        for platform in ("darwin", "linux"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                profile = home / ".fx/mcp.json"
                profile.parent.mkdir()
                old = '{"mcp":{"other":{"command":["other-server"]}}}\n'
                profile.write_text(old)
                with contextlib.redirect_stdout(io.StringIO()):
                    SYNC["apply"](home, platform)
                executor = json.loads(profile.read_text())["mcp"]["executor"]
                expected = (
                    "/Applications/Executor.app/Contents/Resources/executor/executor"
                    if platform == "darwin" else str(home / ".local/bin/executor-mcp")
                )
                self.assertEqual(executor["command"], expected)
                self.assertEqual(executor["type"], "local")
                if platform == "darwin":
                    self.assertIn(str(home / ".executor"), executor["args"])
                else:
                    self.assertEqual(executor["args"], [])
                self.assertEqual(SYNC["plan"](home, platform), {})
                backup = home / ".local/state/executor-agent-config/backups/.fx/mcp.json"
                self.assertEqual(backup.read_text(), old)

    def test_invalid_fx_profile_prevents_writes_to_other_agents(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            profile = home / ".fx/mcp.json"
            profile.parent.mkdir()
            profile.write_text("{invalid")
            with self.assertRaises(ValueError):
                SYNC["apply"](home)
            self.assertEqual(profile.read_text(), "{invalid")
            self.assertFalse((home / ".pi").exists())
            self.assertFalse((home / ".codex").exists())

    def test_symlinked_fx_profile_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            target = home / "external.json"
            target.write_text("{}")
            profile = home / ".fx/mcp.json"
            profile.parent.mkdir()
            profile.symlink_to(target)
            with self.assertRaises(ValueError):
                SYNC["apply"](home)
            self.assertEqual(target.read_text(), "{}")
            self.assertTrue(profile.is_symlink())
            self.assertFalse((home / ".pi").exists())


if __name__ == "__main__":
    unittest.main()
