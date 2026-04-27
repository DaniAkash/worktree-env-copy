#!/usr/bin/env bash
# Uninstaller for the worktree-env-copy global git hook.
# Conservative: never deletes hooks/dirs/config we didn't recognize as ours.
#
# https://github.com/DaniAkash/worktree-env-copy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_HOOK="$SCRIPT_DIR/post-checkout"

if [ ! -f "$SOURCE_HOOK" ]; then
    echo "✗ Source hook not found at: $SOURCE_HOOK" >&2
    echo "  Run this script from inside a checkout of worktree-env-copy" >&2
    echo "  so it can verify the installed hook matches before removing." >&2
    exit 1
fi

echo "→ worktree-env-copy uninstaller"
echo

EXISTING_HOOKS_PATH="$(git config --global core.hooksPath 2>/dev/null || true)"
EXISTING_HOOKS_PATH="${EXISTING_HOOKS_PATH/#\~/$HOME}"

if [ -z "$EXISTING_HOOKS_PATH" ]; then
    echo "  ℹ No core.hooksPath set globally — nothing to uninstall."
    exit 0
fi

TARGET_HOOK="$EXISTING_HOOKS_PATH/post-checkout"

# ---------------------------------------------------------------------------
# Step 1 — Remove the hook only if it matches our source.
# ---------------------------------------------------------------------------
if [ -f "$TARGET_HOOK" ]; then
    if cmp -s "$SOURCE_HOOK" "$TARGET_HOOK"; then
        rm "$TARGET_HOOK"
        echo "  ✓ Removed $TARGET_HOOK"
    else
        echo "  ⚠ $TARGET_HOOK exists but does NOT match our hook."
        echo "    Leaving it in place. If you want to remove it, do so manually."
    fi
else
    echo "  ℹ No hook at $TARGET_HOOK"
fi

# ---------------------------------------------------------------------------
# Step 2 — Only unset core.hooksPath if it points at ~/.git-hooks
# (the default we set during install) AND that dir is now empty.
# ---------------------------------------------------------------------------
DEFAULT_DIR="$HOME/.git-hooks"

if [ "$EXISTING_HOOKS_PATH" = "$DEFAULT_DIR" ]; then
    if [ -d "$DEFAULT_DIR" ] && [ -z "$(ls -A "$DEFAULT_DIR" 2>/dev/null)" ]; then
        rmdir "$DEFAULT_DIR"
        echo "  ✓ Removed empty $DEFAULT_DIR"
    fi
    if [ ! -d "$DEFAULT_DIR" ]; then
        git config --global --unset core.hooksPath
        echo "  ✓ Unset global core.hooksPath"
    else
        echo "  ℹ $DEFAULT_DIR not empty — leaving core.hooksPath set."
        echo "    Other hooks are present:"
        ls -1 "$DEFAULT_DIR" | sed 's/^/      • /'
    fi
else
    echo "  ℹ core.hooksPath points at $EXISTING_HOOKS_PATH (not the default"
    echo "    $DEFAULT_DIR), so it was not unset. If you want to unset it,"
    echo "    run: git config --global --unset core.hooksPath"
fi

echo
echo "✅ Uninstall complete."
