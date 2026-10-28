import contextlib
import io
import json
import os
from pathlib import Path
import re
import runpy
import tempfile
import tomllib
import unittest
from unittest.mock import patch


SYNC = runpy.run_path(str(Path(__file__).resolve().parents[1]
                         / "chezmoi/private_dot_local/bin/executable_sync-mark-integrations"))


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))


def snapshot(root):
    return {p.relative_to(root).as_posix(): p.read_bytes()
            for p in root.rglob("*") if p.is_file()}


class NativeCli:
    """Local fixture implementing the native inventory and install contracts."""
    def __init__(self, home, fx=True):
        self.home = home
        self.calls = []
        self.writes = []
        self.mark = "0.16.0"
        self.codex_plugins = [{"pluginId": "other@other", "name": "other", "marketplaceName": "other",
                               "version": "1.0.0", "enabled": False}]
        self.codex_markets = [{"name": "other"}]
        self.claude_plugins = [{"id": "other@other", "scope": "user", "version": "1.0.0", "enabled": False}]
        self.claude_markets = [{"name": "other", "source": "github", "repo": "somebody/other"}]
        tools = ["github:phongndo/mark", "pi", "npm:@opencode/cli", "codex", "claude"]
        if fx:
            tools.append("github:vercel-labs/fx")
        config = home / ".config/mise/config.toml"
        config.parent.mkdir(parents=True)
        config.write_text("[tools]\n" + "".join(f'{json.dumps(tool)} = "latest"\n' for tool in tools))
        write_json(home / ".pi/agent/settings.json", {"theme": "custom", "packages": ["npm:other"]})
        write_json(home / ".config/opencode/opencode.json", {"theme": "custom", "plugins": ["other"], "mcp": {"servers": {"other": {"command": ["custom"]}}}})
        write_json(home / ".fx/mcp.json", {"custom": 42, "mcp": {"other": {"command": "custom"}}})
        codex = home / ".codex/config.toml"
        codex.parent.mkdir()
        codex.write_text('model = "fixture"\n[plugins."other@other"]\nenabled = false\n')
        for relative in [".codex/auth.json", ".claude/.credentials.json", ".pi/agent/auth.json", ".fx/auth.json"]:
            path = home / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture credential must remain unchanged")

    def toml_block(self, name, body):
        path = self.home / ".codex/config.toml"
        text = path.read_text()
        pattern = r"(?ms)^\[" + re.escape(name) + r"\]\n.*?(?=^\[|\Z)"
        text = re.sub(pattern, "", text).rstrip()
        if body is not None:
            text += f"\n\n[{name}]\n{body}\n"
        path.write_text(text + "\n")

    def codex_market(self, public=True):
        self.codex_markets = [x for x in self.codex_markets if x["name"] != "mark"]
        self.codex_markets.append({"name": "mark"})
        source = "https://github.com/phongndo/mark.git" if public else "/old/mark-package"
        kind = "git" if public else "local"
        self.toml_block("marketplaces.mark", f'source_type = "{kind}"\nsource = "{source}"\nref = "integrations"')

    def install_codex(self, disabled=False):
        self.codex_plugins = [x for x in self.codex_plugins if x["pluginId"] != "mark@mark"]
        self.codex_plugins.append({"pluginId": "mark@mark", "name": "mark", "marketplaceName": "mark", "version": self.mark, "enabled": not disabled})
        self.toml_block('plugins."mark@mark"', "enabled = " + ("false" if disabled else "true"))

    def fx_package(self):
        root = self.home / ".cache/mark/integrations" / self.mark / "fx"
        for name in ["SKILL.md", "HOST.md", "open-review.mjs", "common/bridge.mjs"]:
            path = root / "skills/mark" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"official Mark {self.mark}: {name}\n")
        return root

    def __call__(self, argv, cwd, env):
        assert cwd == self.home
        assert env["MISE_AUTO_INSTALL"] == "false"
        assert argv[:3] == ["/fixture/mise", "-C", str(self.home)], argv
        if argv[3:] == ["upgrade", "github:phongndo/mark"]:
            self.writes.append(tuple(argv[3:]))
            self.mark = "0.16.0"
            return ""
        assert argv[3:5] == ["exec", "--"], argv
        args = argv[5:]
        self.calls.append(tuple(args))
        if args[-1:] == ["--version"]:
            return f"{args[0]} {self.mark if args[0] == 'mark' else '1.0.0'}"
        if args[:3] == ["codex", "plugin", "list"]:
            result = [dict(x) for x in self.codex_plugins]
            enabled = tomllib.loads((self.home / ".codex/config.toml").read_text()).get("plugins", {})
            for plugin in result:
                plugin["enabled"] = enabled.get(plugin["pluginId"], {}).get("enabled", plugin["enabled"])
            return json.dumps({"installed": result})
        if args[:4] == ["codex", "plugin", "marketplace", "list"]:
            return json.dumps({"marketplaces": self.codex_markets})
        if args[:3] == ["claude", "plugin", "list"]:
            return json.dumps(self.claude_plugins)
        if args[:4] == ["claude", "plugin", "marketplace", "list"]:
            return json.dumps(self.claude_markets)
        self.writes.append(tuple(args))
        if args == ["mark", "integration", "path", "--agent", "fx"]:
            return str(self.fx_package())
        if args[0] == "pi":
            path = self.home / ".pi/agent/settings.json"
            data = json.loads(path.read_text())
            if args[1] == "remove":
                data["packages"] = [x for x in data["packages"] if SYNC["package_source"](x) != args[2]]
            else:
                if args[2] not in [SYNC["package_source"](x) for x in data["packages"]]:
                    data["packages"].append(args[2])
                write_json(self.home / ".pi/agent/npm/node_modules/mark-pi/package.json", {"name": "mark-pi", "version": self.mark})
            write_json(path, data)
        elif args[:2] == ["opencode", "plugin"]:
            path = self.home / ".config/opencode/opencode.json"
            data = json.loads(path.read_text())
            if args[2] == "remove":
                data["plugins"] = [x for x in data["plugins"] if x != args[3]]
            else:
                if args[3] not in [SYNC["package_source"](x) for x in data["plugins"]]:
                    data["plugins"].append(args[3])
                write_json(self.home / ".cache/opencode/npm/mark-opencode@latest/123/node_modules/mark-opencode/package.json", {"name": "mark-opencode", "version": self.mark})
            write_json(path, data)
        elif args[:3] == ["codex", "plugin", "marketplace"]:
            if args[3] == "add":
                self.codex_market()
            elif args[3] == "remove":
                self.codex_markets = [x for x in self.codex_markets if x["name"] != args[4]]
                if args[4] == "mark":
                    self.toml_block("marketplaces.mark", None)
        elif args[:3] == ["codex", "plugin", "add"]:
            self.install_codex()
        elif args[:3] == ["codex", "plugin", "remove"]:
            self.codex_plugins = [x for x in self.codex_plugins if x["pluginId"] != args[3]]
            self.toml_block(f'plugins."{args[3]}"', None)
        elif args[:3] == ["claude", "plugin", "marketplace"]:
            if args[3] == "add":
                self.claude_markets.append({"name": "mark", "source": "github", "repo": "phongndo/mark", "ref": "integrations"})
            elif args[3] == "remove":
                self.claude_markets = [x for x in self.claude_markets if x["name"] != args[4]]
        elif args[:2] == ["claude", "plugin"]:
            if args[2] == "uninstall":
                self.claude_plugins = [x for x in self.claude_plugins if x["id"] != args[3]]
            elif args[2] in ("install", "update"):
                self.claude_plugins = [x for x in self.claude_plugins if x["id"] != args[3]]
                self.claude_plugins.append({"id": args[3], "scope": "user", "version": self.mark, "enabled": True})
            elif args[2] == "disable":
                next(x for x in self.claude_plugins if x["id"] == args[3])["enabled"] = False
            else:
                raise AssertionError(args)
        else:
            raise AssertionError(args)
        return "{}"


class MarkIntegrationSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name).resolve()
        self.environment = patch.dict(os.environ, {"XDG_CACHE_HOME": str(self.home / ".cache")})
        self.environment.start()
        self.cli = NativeCli(self.home)

    def tearDown(self):
        self.environment.stop()
        self.temp.cleanup()

    def reconcile(self, check=False):
        with contextlib.redirect_stdout(io.StringIO()):
            return SYNC["Reconciler"](self.home, check, "/fixture/mise", self.cli).reconcile()

    def test_install_preserves_unrelated_state_and_second_run_has_no_changes(self):
        credentials = {name: data for name, data in snapshot(self.home).items()
                       if name.endswith(("auth.json", ".credentials.json"))}
        self.assertTrue(self.reconcile())
        self.assertEqual(json.loads((self.home / ".pi/agent/settings.json").read_text()), {"theme": "custom", "packages": ["npm:other", "npm:mark-pi"]})
        opencode = json.loads((self.home / ".config/opencode/opencode.json").read_text())
        self.assertEqual(opencode["plugins"], ["other", "mark-opencode"])
        self.assertEqual(opencode["mcp"], {"servers": {"other": {"command": ["custom"]}}})
        self.assertEqual(self.cli.codex_plugins[0]["pluginId"], "other@other")
        self.assertFalse(self.cli.codex_plugins[0]["enabled"])
        self.assertFalse(self.cli.claude_plugins[0]["enabled"])
        fx = json.loads((self.home / ".fx/mcp.json").read_text())
        self.assertEqual(fx["custom"], 42)
        self.assertEqual(fx["mcp"]["other"], {"command": "custom"})
        self.assertEqual(fx["mcp"]["mark"]["args"], ["mcp", "--harness", "fx"])
        self.assertTrue((self.home / ".fx/skills/mark/common/bridge.mjs").is_file())
        before = snapshot(self.home)
        writes = len(self.cli.writes)
        self.assertEqual(self.reconcile(), [])
        self.assertEqual(snapshot(self.home), before)
        self.assertEqual(len(self.cli.writes), writes)
        self.assertEqual({name: before[name] for name in credentials}, credentials)

    def test_check_reports_drift_without_native_or_file_writes(self):
        before = snapshot(self.home)
        self.assertTrue(self.reconcile(check=True))
        self.assertEqual(self.cli.writes, [])
        self.assertEqual(snapshot(self.home), before)

    def test_selected_unavailable_tool_fails_check_without_installing_anything(self):
        original = self.cli

        def missing_tool(argv, **kwargs):
            if argv[-2:] == ["claude", "--version"]:
                self.assertEqual(kwargs["env"]["MISE_AUTO_INSTALL"], "false")
                raise RuntimeError("mise tool is not installed")
            return original(argv, **kwargs)

        self.cli = missing_tool
        before = snapshot(self.home)
        with self.assertRaisesRegex(ValueError, "selected claude is unavailable"):
            self.reconcile(check=True)
        self.assertEqual(original.writes, [])
        self.assertEqual(snapshot(self.home), before)

    def test_old_mark_uses_qualified_mise_upgrade_then_fresh_exec(self):
        self.cli.mark = "0.15.1"
        self.reconcile()
        self.assertEqual(self.cli.writes[0], ("upgrade", "github:phongndo/mark"))
        self.assertGreaterEqual(self.cli.calls.count(("mark", "--version")), 2)
        self.assertEqual(self.cli.mark, "0.16.0")

    def test_wrong_equal_version_marketplaces_are_replaced_and_disabled_state_preserved(self):
        self.cli.codex_market(public=False)
        self.cli.install_codex(disabled=True)
        self.cli.claude_markets.append({"name": "mark", "source": "directory", "path": "/old/mark"})
        self.cli.claude_plugins.append({"id": "mark@mark", "scope": "user", "version": "0.16.0", "enabled": False})
        self.reconcile()
        self.assertIn(("codex", "plugin", "remove", "mark@mark", "--json"), self.cli.writes)
        self.assertIn(("claude", "plugin", "uninstall", "mark@mark", "--scope", "user", "--keep-data", "--json"), self.cli.writes)
        config = tomllib.loads((self.home / ".codex/config.toml").read_text())
        self.assertEqual(config["marketplaces"]["mark"]["ref"], "integrations")
        self.assertFalse(config["plugins"]["mark@mark"]["enabled"])
        self.assertFalse(next(x for x in self.cli.claude_plugins if x["id"] == "mark@mark")["enabled"])
        self.assertEqual(self.reconcile(), [])

    def test_legacy_local_plugins_and_package_sources_migrate_without_duplicates(self):
        self.cli.codex_plugins.append({"pluginId": "mark@mark-local", "name": "mark", "marketplaceName": "mark-local", "version": "0.16.0", "enabled": False})
        self.cli.codex_markets.append({"name": "mark-local"})
        self.cli.claude_plugins.append({"id": "mark@mark-local", "scope": "user", "version": "0.16.0", "enabled": False})
        self.cli.claude_markets.append({"name": "mark-local", "source": "directory"})
        write_json(self.home / ".pi/agent/settings.json", {"theme": "custom", "packages": ["npm:other", "/Users/dp/.cache/mark/integrations/0.16.0/pi"]})
        write_json(self.home / ".config/opencode/opencode.json", {"plugins": ["other", "mark-opencode@0.15.0"]})
        self.reconcile()
        self.assertEqual([x["pluginId"] for x in self.cli.codex_plugins if x["name"] == "mark"], ["mark@mark"])
        self.assertEqual([x["id"] for x in self.cli.claude_plugins if x["id"].startswith("mark@")], ["mark@mark"])
        self.assertFalse(any(x["name"] == "mark-local" for x in self.cli.codex_markets + self.cli.claude_markets))
        self.assertEqual(json.loads((self.home / ".pi/agent/settings.json").read_text())["packages"], ["npm:other", "npm:mark-pi"])
        self.assertEqual(json.loads((self.home / ".config/opencode/opencode.json").read_text())["plugins"], ["other", "mark-opencode"])
        self.assertEqual(self.reconcile(), [])

    def test_stale_packages_update_and_native_pi_resource_toggles_survive(self):
        self.reconcile()
        settings = self.home / ".pi/agent/settings.json"
        data = json.loads(settings.read_text())
        data["packages"][-1] = {"source": "npm:mark-pi", "extensions": [], "skills": []}
        write_json(settings, data)
        write_json(self.home / ".pi/agent/npm/node_modules/mark-pi/package.json", {"version": "0.15.1"})
        write_json(self.home / ".cache/opencode/npm/mark-opencode@latest/123/node_modules/mark-opencode/package.json", {"version": "0.15.1"})
        self.reconcile()
        self.assertIn(("pi", "update", "npm:mark-pi"), self.cli.writes)
        self.assertIn(("opencode", "plugin", "update", "mark-opencode"), self.cli.writes)
        self.assertEqual(json.loads(settings.read_text())["packages"][-1], data["packages"][-1])

    def test_opencode_object_package_options_survive_inventory_and_update(self):
        self.reconcile()
        path = self.home / ".config/opencode/opencode.json"
        data = json.loads(path.read_text())
        entry = {"package": "mark-opencode", "options": {"disabled": True, "custom": 42}}
        data["plugins"][-1] = entry
        write_json(path, data)
        before = snapshot(self.home)
        writes = len(self.cli.writes)
        self.assertEqual(self.reconcile(), [])
        self.assertEqual(snapshot(self.home), before)
        self.assertEqual(len(self.cli.writes), writes)
        write_json(self.home / ".cache/opencode/npm/mark-opencode@latest/123/node_modules/mark-opencode/package.json", {"version": "0.15.1"})
        self.reconcile()
        self.assertEqual(json.loads(path.read_text())["plugins"], ["other", entry])

    def test_opencode_mark_jsonc_override_is_preserved_and_reported_before_native_changes(self):
        path = self.home / ".config/opencode/opencode.jsonc"
        for text in ['{"plugins":["mark-opencode@0.15.1"]}',
                     '// local config\n{"plugins":[{"package":"mark-opencode","options":{"disabled":true}}]}']:
            with self.subTest(text=text):
                path.write_text(text)
                before = snapshot(self.home)
                sync = SYNC["Reconciler"](self.home, mise="/fixture/mise", runner=self.cli)
                sync.mark_version = "0.16.0"
                with self.assertRaisesRegex(ValueError, "opencode.jsonc"):
                    sync.opencode()
                self.assertEqual(self.cli.writes, [])
                self.assertEqual(snapshot(self.home), before)

    def test_codex_disabled_toggle_supports_native_and_inline_toml_without_other_changes(self):
        texts = [
            'model="fixture"\n[plugins."mark@mark"]\nenabled=true\noption="keep"\n',
            "model='fixture'\n[plugins.'mark@mark']\nenabled=true\noption='keep'\n",
            '[plugins]\n"mark@mark"={enabled=true, option="keep"}\n"other@other"={enabled=true}\n',
            'plugins={"mark@mark"={enabled=true, option="keep"}, "other@other"={enabled=true}}\n',
        ]
        path = self.home / ".codex/config.toml"
        sync = SYNC["Reconciler"](self.home, mise="/fixture/mise", runner=self.cli)
        for text in texts:
            with self.subTest(text=text):
                path.write_text(text)
                expected = tomllib.loads(text)
                expected["plugins"]["mark@mark"]["enabled"] = False
                sync.codex_disabled()
                self.assertEqual(tomllib.loads(path.read_text()), expected)
                before = path.read_bytes()
                sync.codex_disabled()
                self.assertEqual(path.read_bytes(), before)

    def test_each_native_first_install_rejects_a_package_older_than_mark(self):
        for tool in ["pi", "opencode", "codex", "claude"]:
            with self.subTest(tool=tool):
                case = self.home / tool
                case.mkdir()
                cli = NativeCli(case, fx=False)

                def outdated(argv, **kwargs):
                    result = cli(argv, **kwargs)
                    if tuple(argv[5:]) == ("pi", "install", "npm:mark-pi"):
                        write_json(case / ".pi/agent/npm/node_modules/mark-pi/package.json", {"version": "0.15.1"})
                    elif tuple(argv[5:]) == ("opencode", "plugin", "add", "mark-opencode"):
                        write_json(case / ".cache/opencode/npm/mark-opencode@latest/123/node_modules/mark-opencode/package.json", {"version": "0.15.1"})
                    elif tuple(argv[5:]) == ("codex", "plugin", "add", "mark@mark", "--json"):
                        cli.codex_plugins[-1]["version"] = "0.15.1"
                    elif argv[5:9] == ["claude", "plugin", "install", "mark@mark"]:
                        cli.claude_plugins[-1]["version"] = "0.15.1"
                    return result

                with patch.dict(os.environ, {"XDG_CACHE_HOME": str(case / ".cache")}):
                    sync = SYNC["Reconciler"](case, mise="/fixture/mise", runner=outdated)
                    sync.mark_version = "0.16.0"
                    with contextlib.redirect_stdout(io.StringIO()), self.assertRaisesRegex(ValueError, "older than Mark"):
                        getattr(sync, tool)()

    def test_fx_retirement_is_respected_even_if_an_old_fx_binary_still_exists(self):
        config = self.home / ".config/mise/config.toml"
        config.write_text(config.read_text().replace('"github:vercel-labs/fx" = "latest"\n', ""))
        old = snapshot(self.home)
        self.reconcile()
        self.assertNotIn(("fx", "--version"), self.cli.calls)
        self.assertFalse((self.home / ".fx/skills/mark").exists())
        self.assertEqual((self.home / ".fx/mcp.json").read_bytes(), old[".fx/mcp.json"])

    def test_fx_edits_and_custom_server_collisions_are_preserved(self):
        self.reconcile()
        skill = self.home / ".fx/skills/mark/HOST.md"
        skill.write_text("local edit")
        before = snapshot(self.home)
        with self.assertRaisesRegex(ValueError, "modified or unowned"):
            self.reconcile()
        self.assertEqual(snapshot(self.home), before)
        skill.write_text("official Mark 0.16.0: HOST.md\n")
        write_json(self.home / ".fx/mcp.json", {"mcp": {"mark": {"url": "https://custom.example/mcp"}}})
        before = snapshot(self.home)
        with self.assertRaisesRegex(ValueError, "custom fx server"):
            self.reconcile()
        self.assertEqual(snapshot(self.home), before)


if __name__ == "__main__":
    unittest.main()
