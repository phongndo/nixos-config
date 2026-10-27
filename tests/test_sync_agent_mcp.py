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


class RexCommunityRemovalTests(unittest.TestCase):
    def test_owned_community_is_removed_from_all_harnesses_on_both_hosts(self):
        for platform in ("darwin", "linux"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                community = {"url": SYNC["RETIRED_REX_COMMUNITY_URL"],
                             "enabled": False, "oauth": {"clientId": "local-client"}}
                profiles = (
                    (".pi/agent/mcp.json", "mcpServers"),
                    (".claude.json", "mcpServers"),
                    (".fx/mcp.json", "mcp"),
                    (".config/opencode/opencode.json", "mcp"),
                )
                for relative, key in profiles:
                    profile = home / relative
                    profile.parent.mkdir(parents=True, exist_ok=True)
                    profile.write_text(json.dumps({
                        "custom": True, key: {"superlogical": community, "other": ENTRY},
                    }))
                codex = home / ".codex/config.toml"
                codex.parent.mkdir()
                codex.write_text(
                    '# Keep this comment\nmodel = "test"\n'
                    '[mcp_servers.other]\ncommand = "other"\n'
                    '[mcp_servers.superlogical]\n'
                    f'url = "{SYNC["RETIRED_REX_COMMUNITY_URL"]}"\nenabled = false\n'
                    '[mcp_servers.superlogical.oauth]\nclient_id = "local-client"\n'
                )
                with contextlib.redirect_stdout(io.StringIO()):
                    SYNC["apply"](home, platform)
                for relative, key in profiles:
                    data = json.loads((home / relative).read_text())
                    self.assertTrue(data["custom"])
                    self.assertEqual(data[key]["other"], ENTRY)
                    self.assertNotIn("superlogical", data[key])
                parsed = tomllib.loads(codex.read_text())
                self.assertTrue(codex.read_text().startswith('# Keep this comment\nmodel = "test"'))
                self.assertEqual(parsed["mcp_servers"]["other"], {"command": "other"})
                self.assertNotIn("superlogical", parsed["mcp_servers"])
                self.assertEqual(SYNC["plan"](home, platform), {})

    def test_custom_same_name_is_preserved_including_formatting(self):
        custom = {"url": "https://custom.test/mcp", "enabled": False,
                  "oauth": {"clientId": "local-client"}}
        for key in ("mcpServers", "mcp"):
            for nested in (False, True):
                with self.subTest(key=key, nested=nested):
                    servers = {"other": ENTRY, "superlogical": custom}
                    old = json.dumps({key: {"servers": servers} if nested else servers},
                                     separators=(",", ":"))
                    self.assertEqual(SYNC["remove_rex_community"](old, key), old)
        old = ('# Preserve custom server\n[mcp_servers.superlogical]\n'
               'url = "https://custom.test/mcp"\nenabled = false\n'
               '[mcp_servers.superlogical.oauth]\nclient_id = "local-client"\n')
        self.assertEqual(SYNC["toml_config"](old, None, "superlogical"), old)

    def test_legacy_json_maps_cannot_restore_retired_connection(self):
        community = {"url": SYNC["RETIRED_REX_COMMUNITY_URL"]}
        old = {"mcp": {"servers": {"superlogical": community, "other": ENTRY}},
               "mcpServers": {"superlogical": community, "legacy": ENTRY}}
        result = json.loads(SYNC["remove_rex_community"](json.dumps(old), "mcp"))
        self.assertEqual(result, {"mcp": {"servers": {"other": ENTRY}},
                                  "mcpServers": {"legacy": ENTRY}})

    def test_quoted_codex_tables_remove_only_owned_server_and_nested_oauth(self):
        old = ('# Keep this comment\nmodel = "test"\n'
               '[mcp_servers."superlogical"]\n'
               f'url = "{SYNC["RETIRED_REX_COMMUNITY_URL"]}"\n'
               '[mcp_servers."superlogical".oauth]\nclient_id = "old-client"\n'
               '[mcp_servers.superlogical_custom]\ncommand = "other"\n')
        result = SYNC["toml_config"](old, None, "superlogical")
        self.assertTrue(result.startswith('# Keep this comment\nmodel = "test"'))
        self.assertEqual(tomllib.loads(result), {"model": "test", "mcp_servers": {
            "superlogical_custom": {"command": "other"},
        }})

    def test_opencode_legacy_jsonc_removes_owned_connection_without_adding_executor(self):
        for nested in (False, True):
            with self.subTest(nested=nested), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                legacy = home / ".config/opencode/opencode.jsonc"
                legacy.parent.mkdir(parents=True)
                servers = {"superlogical": {"url": SYNC["RETIRED_REX_COMMUNITY_URL"]},
                           "other": ENTRY}
                legacy.write_text(json.dumps({"custom": True,
                    "mcp": {"servers": servers} if nested else servers}))
                with contextlib.redirect_stdout(io.StringIO()):
                    SYNC["apply"](home)
                result = json.loads(legacy.read_text())
                self.assertTrue(result["custom"])
                self.assertEqual(result["mcp"], {"servers": {"other": ENTRY}} if nested
                                 else {"other": ENTRY})
                self.assertEqual(SYNC["plan"](home), {})

    def test_commented_owned_community_prevents_partial_migration(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            legacy = home / ".config/opencode/opencode.jsonc"
            legacy.parent.mkdir(parents=True)
            original = '// Preserve comments\n' + json.dumps({"mcp": {
                "superlogical": {"url": SYNC["RETIRED_REX_COMMUNITY_URL"]},
            }})
            legacy.write_text(original)
            with self.assertRaises(ValueError):
                SYNC["apply"](home)
            self.assertEqual(legacy.read_text(), original)
            self.assertFalse((home / ".codex").exists())
            self.assertFalse((home / ".pi").exists())

    def test_unrelated_commented_opencode_settings_remain_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            legacy = home / ".config/opencode/opencode.jsonc"
            legacy.parent.mkdir(parents=True)
            original = '// Local settings\n{"mcp":{"superlogical":{"url":"https://custom.test"}}}\n'
            legacy.write_text(original)
            with contextlib.redirect_stdout(io.StringIO()):
                SYNC["apply"](home)
            self.assertEqual(legacy.read_text(), original)

    def test_invalid_claude_profile_prevents_any_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / ".claude.json").write_text("{invalid")
            with self.assertRaises(ValueError):
                SYNC["apply"](home)
            self.assertFalse((home / ".pi").exists())


class RadiusConfigTests(unittest.TestCase):
    def test_both_hosts_receive_radius_only_in_pi(self):
        for platform in ("darwin", "linux"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                with contextlib.redirect_stdout(io.StringIO()):
                    SYNC["apply"](home, platform)
                pi = json.loads((home / ".pi/agent/mcp.json").read_text())
                self.assertEqual(pi["mcpServers"]["radius"], {
                    "url": SYNC["RADIUS_URL"], "auth": {"provider": "radius"},
                })
                for relative, key in ((".claude.json", "mcpServers"),
                                      (".fx/mcp.json", "mcp"),
                                      (".config/opencode/opencode.json", "mcp")):
                    data = json.loads((home / relative).read_text())
                    self.assertNotIn("radius", data[key])
                codex = tomllib.loads((home / ".codex/config.toml").read_text())
                self.assertNotIn("radius", codex["mcp_servers"])
                self.assertEqual(SYNC["plan"](home, platform), {})

    def test_radius_keeps_mutable_controls_and_local_auth_settings(self):
        radius = {"url": "https://old.test/mcp", "enabled": False,
                  "exposure": "deferred", "timeout": 90000,
                  "auth": {"provider": "old", "profile": "personal"}}
        old = {"custom": True, "mcpServers": {"radius": radius, "other": ENTRY}}
        result = json.loads(SYNC["pi_config"](json.dumps(old), ENTRY))
        self.assertTrue(result["custom"])
        self.assertEqual(result["mcpServers"]["other"], ENTRY)
        self.assertEqual(result["mcpServers"]["radius"], {
            **radius, "url": SYNC["RADIUS_URL"],
            "auth": {"provider": "radius", "profile": "personal"},
        })


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

    def test_both_hosts_use_local_wrapper_and_sync_is_idempotent(self):
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
                expected = str(home / ".local/bin/executor-mcp")
                self.assertEqual(executor["command"], expected)
                self.assertEqual(executor["type"], "local")
                self.assertEqual(executor["args"], [])
                pi = json.loads((home / ".pi/agent/mcp.json").read_text())
                codex = tomllib.loads((home / ".codex/config.toml").read_text())
                claude = json.loads((home / ".claude.json").read_text())
                opencode = json.loads((home / ".config/opencode/opencode.json").read_text())
                for configured in (pi["mcpServers"]["executor"],
                                   codex["mcp_servers"]["executor"],
                                   claude["mcpServers"]["executor"]):
                    self.assertEqual(configured["command"], expected)
                    self.assertEqual(configured["args"], [])
                self.assertEqual(claude["mcpServers"]["executor"]["type"], "stdio")
                self.assertEqual(opencode["mcp"]["executor"], {
                    "type": "local", "command": [expected],
                })
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


class SharedExecutorConfigTests(unittest.TestCase):
    def test_claude_http_entry_migrates_without_losing_other_settings(self):
        old = {"projects": {"/project": {}}, "mcpServers": {
            "executor": {"type": "http", "url": "http://localhost:4788/mcp",
                         "headers": {"Authorization": "old"}, "enabled": False},
            "other": ENTRY,
        }}
        result = json.loads(SYNC["json_executor_config"](json.dumps(old), ENTRY))
        self.assertEqual(result["projects"], old["projects"])
        self.assertEqual(result["mcpServers"]["other"], ENTRY)
        self.assertEqual(result["mcpServers"]["executor"], {
            "type": "stdio", **ENTRY, "enabled": False,
        })

    def test_codex_retains_tool_controls_when_connection_changes(self):
        old = '[mcp_servers.executor]\nurl = "https://old.test"\nenabled = false\ntool_timeout_sec = 90\n[mcp_servers.executor.tools.execute]\napproval_mode = "prompt"\n'
        result = tomllib.loads(SYNC["toml_config"](old, ENTRY))
        self.assertEqual(result["mcp_servers"]["executor"], {
            **ENTRY, "enabled": False, "tool_timeout_sec": 90,
            "tools": {"execute": {"approval_mode": "prompt"}},
        })

    def test_opencode_legacy_override_uses_wrapper_and_preserves_controls(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            legacy = home / ".config/opencode/opencode.jsonc"
            legacy.parent.mkdir(parents=True)
            other = {"type": "remote", "url": "https://example.test/mcp"}
            legacy.write_text(json.dumps({"mcp": {
                "other": other,
                "executor": {"type": "local", "command": ["/Applications/Executor.app/executor"],
                             "enabled": True, "timeout": 30000},
            }}))
            with contextlib.redirect_stdout(io.StringIO()):
                SYNC["apply"](home, "darwin")
            actual = json.loads(legacy.read_text())["mcp"]
            self.assertEqual(actual["other"], other)
            self.assertEqual(actual["executor"], {
                "type": "local", "command": [str(home / ".local/bin/executor-mcp")],
                "enabled": True, "timeout": 30000,
            })
            self.assertEqual(SYNC["plan"](home, "darwin"), {})

    def test_commented_opencode_override_prevents_partial_migration(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            legacy = home / ".config/opencode/opencode.jsonc"
            legacy.parent.mkdir(parents=True)
            original = '// Preserve comments\n{"mcp":{"executor":{"command":["old"]}}}'
            legacy.write_text(original)
            with self.assertRaises(ValueError):
                SYNC["apply"](home)
            self.assertEqual(legacy.read_text(), original)
            self.assertFalse((home / ".codex").exists())

    def test_opencode_nested_map_keeps_other_servers(self):
        old = {"mcp": {"servers": {"executor": {
            "type": "remote", "url": "https://old.test", "enabled": False,
        }, "other": ENTRY}}}
        result = json.loads(SYNC["json_executor_config"](
            json.dumps(old), ENTRY, "mcp", "local", command_list=True,
        ))
        self.assertEqual(result["mcp"]["servers"]["executor"], {
            "type": "local", "command": [ENTRY["command"], *ENTRY["args"]], "enabled": False,
        })
        self.assertEqual(result["mcp"]["servers"]["other"], ENTRY)


if __name__ == "__main__":
    unittest.main()
