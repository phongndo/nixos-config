"""Regression checks for Claude Code's chezmoi settings modifier."""
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "chezmoi"
TEMPLATE = SOURCE / "dot_claude/modify_private_settings.json"


def render(settings):
    result = subprocess.run(
        ["chezmoi", "--source", str(SOURCE), "execute-template", "--with-stdin", "--file", str(TEMPLATE)],
        input=json.dumps(settings), text=True, capture_output=True, check=True,
    )
    return json.loads(result.stdout)


class ClaudeSettingsTest(unittest.TestCase):
    def test_defaults_and_idempotence(self):
        expected = {
            "effortLevel": "high", "theme": "dark",
            "permissions": {"defaultMode": "bypassPermissions"},
            "skipDangerousModePermissionPrompt": True,
            "autoMemoryEnabled": False,
            "attribution": {"commit": "", "pr": ""},
        }
        self.assertEqual(render({}), expected)
        self.assertEqual(render(expected), expected)

    def test_local_preferences_preserved(self):
        local = {"model": "local", "permissions": {"defaultMode": "ask"},
                 "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo keep"}]}]}}
        updated = render(local)
        for key in local:
            self.assertEqual(updated[key], local[key])
        self.assertEqual(render(updated), updated)

    def test_attribution_disabled_over_local_value(self):
        updated = render({"attribution": {"commit": "Co-Authored-By: Claude", "pr": "Generated"}})
        self.assertEqual(updated["attribution"], {"commit": "", "pr": ""})


if __name__ == "__main__":
    unittest.main()
