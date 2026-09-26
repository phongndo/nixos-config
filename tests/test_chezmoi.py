"""Check both hosts' agent configuration and safe retirement of managed files."""
import json
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "chezmoi"


class ChezmoiTest(unittest.TestCase):
    def test_retirement_and_tool_policy_on_both_hosts(self):
        for platform in ("darwin", "linux"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                home = root / "home"
                home.mkdir()
                preserved = {
                    ".dsh/.credentials.yaml": "test credential\n",
                    ".dsh/settings.yaml": "local preference\n",
                    ".dsh/profiles/personal/config.yaml": "local profile\n",
                    ".ssh/id_ed25519_y": "test private key\n",
                }
                retired = (".dsh/cordis.patch.yml", ".ssh/executor_mac_known_hosts")
                for name, content in {
                    **preserved, **dict.fromkeys(retired, "old managed config\n")
                }.items():
                    path = home / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(content)
                config = root / "empty.toml"
                config.touch()
                command = [
                    "chezmoi", "--source", str(SOURCE), "--destination", str(home),
                    "--config", str(config), "--persistent-state", str(root / "state.db"),
                    "--override-data", json.dumps({"chezmoi": {
                        "os": platform, "homeDir": str(home),
                    }}),
                    "apply", "--exclude", "scripts", "--force", "--no-tty",
                ]
                # A repeated apply must preserve unrelated state too.
                for _ in range(2):
                    subprocess.run(command, check=True, capture_output=True, text=True)
                    for name in retired:
                        self.assertFalse((home / name).exists(), name)
                    for name, content in preserved.items():
                        self.assertEqual((home / name).read_text(), content)
                    tools = tomllib.loads((home / ".config/mise/config.toml").read_text())["tools"]
                    for name in ("codex", "claude", "pi", "opencode", "herdr"):
                        self.assertEqual(tools[name], "latest")
                    self.assertNotIn("npm:@deepseek-ai/dsh", tools)
                    self.assertNotIn("pnpm", tools)
                    self.assertEqual("npm:executor" in tools, platform == "linux")
                    self.assertEqual((home / ".local/bin/executor-mcp").exists(), platform == "linux")


if __name__ == "__main__":
    unittest.main()
