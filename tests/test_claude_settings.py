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
        }
        self.assertEqual(render({}), expected)
        self.assertEqual(render(expected), expected)

    def test_superset_removed_other_hooks_and_preferences_preserved(self):
        local = {"model": "local", "permissions": {"defaultMode": "ask"}, "hooks": {
            "Stop": [{"hooks": [
                {"type": "command", "command": "echo keep"},
                {"type": "command", "command": 'SUPERSET_HOME_DIR=1 SUPERSET_AGENT_ID=claude echo old'},
            ]}],
            "SessionEnd": [{"hooks": [
                {"type": "command", "command": 'SUPERSET_HOME_DIR=1 SUPERSET_AGENT_ID=claude echo old'},
            ]}],
        }}
        updated = render(local)
        self.assertEqual(updated["model"], "local")
        self.assertEqual(updated["permissions"], local["permissions"])
        self.assertEqual(updated["hooks"], {"Stop": [{"hooks": [{"type": "command", "command": "echo keep"}]}]})
        self.assertEqual(render(updated), updated)


if __name__ == "__main__":
    unittest.main()
