#!/usr/bin/env bash
# One-command installer for the dotnet-lean-arch skill.
#
#   curl -fsSL https://raw.githubusercontent.com/jbrambilla/dotnet-lean-arch-skill/main/install.sh | bash
#
# Copies the skill into the skills directories of every supported agent found
# on this machine:
#   ~/.claude/skills/dotnet-lean-arch   (Claude Code)
#   ~/.agents/skills/dotnet-lean-arch   (Codex, Copilot/VS Code, Cursor, Gemini CLI, OpenCode...)
#
# Options (pass after `bash -s --` when piping):
#   --claude-only | --agents-only   install to a single target
#   --uninstall                     remove the skill from both targets
set -euo pipefail

REPO="jbrambilla/dotnet-lean-arch-skill"
SKILL="dotnet-lean-arch"
CLAUDE_DIR="$HOME/.claude/skills"
AGENTS_DIR="$HOME/.agents/skills"

TARGETS=("$CLAUDE_DIR" "$AGENTS_DIR")
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --claude-only) TARGETS=("$CLAUDE_DIR") ;;
    --agents-only) TARGETS=("$AGENTS_DIR") ;;
    --uninstall)   UNINSTALL=1 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [ "$UNINSTALL" -eq 1 ]; then
  for dir in "${TARGETS[@]}"; do
    if [ -e "$dir/$SKILL" ]; then
      rm -rf "${dir:?}/$SKILL"
      echo "removed  $dir/$SKILL"
    else
      echo "not found $dir/$SKILL (skipped)"
    fi
  done
  exit 0
fi

# Resolve the skill source: local clone (script run from the repo) or fresh download.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || echo "")"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/skills/$SKILL/SKILL.md" ]; then
  SRC="$SCRIPT_DIR/skills/$SKILL"
  CLEANUP=""
else
  TMP="$(mktemp -d)"
  CLEANUP="$TMP"
  trap '[ -n "$CLEANUP" ] && rm -rf "$CLEANUP"' EXIT
  echo "downloading $REPO..."
  if command -v git >/dev/null 2>&1; then
    git clone --quiet --depth 1 "https://github.com/$REPO.git" "$TMP/repo"
  else
    curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" \
      | tar -xz -C "$TMP" && mv "$TMP"/*-main "$TMP/repo"
  fi
  SRC="$TMP/repo/skills/$SKILL"
fi

[ -f "$SRC/SKILL.md" ] || { echo "ERROR: SKILL.md not found in $SRC" >&2; exit 1; }

for dir in "${TARGETS[@]}"; do
  mkdir -p "$dir"
  rm -rf "${dir:?}/$SKILL"
  cp -r "$SRC" "$dir/$SKILL"
  rm -rf "$dir/$SKILL/.claude-plugin"   # plugin metadata is not needed for skill installs
  echo "installed $dir/$SKILL"
done

echo
echo "Done. Open a NEW agent session and ask: \"create a .NET API from scratch\"."
echo "Update later by re-running this installer. Uninstall: same command with --uninstall."
