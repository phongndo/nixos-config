#!/usr/bin/env bash
# Claude Code reads skills only from ~/.claude/skills. Link each shared skill
# from ~/.agents/skills there and drop links to removed skills; real folders,
# such as Rex's skill and claude.ai's synced skills, are left alone.
set -euo pipefail
shopt -s nullglob
mkdir -p "$HOME/.claude/skills"
cd "$HOME/.claude/skills"
for link in *; do
  if [[ -L "$link" && ! -e "$link" && "$(readlink "$link")" == ../../.agents/skills/* ]]; then
    rm "$link"
  fi
done
for skill in "$HOME"/.agents/skills/*/; do
  name="${skill%/}"
  name="${name##*/}"
  [[ -e "$name" && ! -L "$name" ]] || ln -sfn "../../.agents/skills/$name" "$name"
done
