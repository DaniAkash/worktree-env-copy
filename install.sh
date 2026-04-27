#!/usr/bin/env bash
# Installer for the worktree-env-copy global git hook.
# Idempotent — safe to re-run.
#
# https://github.com/DaniAkash/worktree-env-copy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_HOOK="$SCRIPT_DIR/post-checkout"

if [ ! -f "$SOURCE_HOOK" ]; then
    echo "✗ Source hook not found at: $SOURCE_HOOK" >&2
    echo "  Run this script from inside a checkout of worktree-env-copy." >&2
    exit 1
fi

echo "→ worktree-env-copy installer"
echo

# ---------------------------------------------------------------------------
# Step 1 — Resolve the target hooks directory.
# If the user already has core.hooksPath set, respect it; otherwise default
# to ~/.git-hooks.
# ---------------------------------------------------------------------------
EXISTING_HOOKS_PATH="$(git config --global core.hooksPath 2>/dev/null || true)"

if [ -n "$EXISTING_HOOKS_PATH" ]; then
    # Expand ~ if the user stored it that way.
    EXISTING_HOOKS_PATH="${EXISTING_HOOKS_PATH/#\~/$HOME}"
    TARGET_DIR="$EXISTING_HOOKS_PATH"
    SET_HOOKS_PATH=0
    echo "  ℹ Using existing core.hooksPath: $TARGET_DIR"
else
    TARGET_DIR="$HOME/.git-hooks"
    SET_HOOKS_PATH=1
    echo "  ℹ No core.hooksPath set globally. Will use: $TARGET_DIR"
fi

mkdir -p "$TARGET_DIR"
TARGET_HOOK="$TARGET_DIR/post-checkout"

# ---------------------------------------------------------------------------
# Step 2 — Handle existing hook collision.
# ---------------------------------------------------------------------------
if [ -f "$TARGET_HOOK" ]; then
    if cmp -s "$SOURCE_HOOK" "$TARGET_HOOK"; then
        echo "  ✓ Hook already up-to-date at $TARGET_HOOK"
    else
        BACKUP="$TARGET_HOOK.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$TARGET_HOOK" "$BACKUP"
        echo "  ⚠ Existing post-checkout hook differs — backed up to:"
        echo "    $BACKUP"
        cp "$SOURCE_HOOK" "$TARGET_HOOK"
        chmod +x "$TARGET_HOOK"
        echo "  ✓ Installed new hook (overwriting previous)"
    fi
else
    cp "$SOURCE_HOOK" "$TARGET_HOOK"
    chmod +x "$TARGET_HOOK"
    echo "  ✓ Installed hook at $TARGET_HOOK"
fi

# ---------------------------------------------------------------------------
# Step 3 — Configure core.hooksPath if we're the ones setting it.
# ---------------------------------------------------------------------------
if [ "$SET_HOOKS_PATH" = "1" ]; then
    git config --global core.hooksPath "$TARGET_DIR"
    echo "  ✓ Set core.hooksPath = $TARGET_DIR"
fi

# ---------------------------------------------------------------------------
# Step 4 — Detect per-repo hooks that will now be shadowed.
# These will still be chained from our hook (see post-checkout for details),
# so this is informational — not a blocker.
# ---------------------------------------------------------------------------
echo
echo "→ Scanning for existing per-repo post-checkout hooks (informational)…"

PER_REPO_HOOKS_FOUND=0
SEARCH_ROOTS=()
[ -d "$HOME/workbench" ]   && SEARCH_ROOTS+=("$HOME/workbench")
[ -d "$HOME/projects" ]    && SEARCH_ROOTS+=("$HOME/projects")
[ -d "$HOME/code" ]        && SEARCH_ROOTS+=("$HOME/code")
[ -d "$HOME/dev" ]         && SEARCH_ROOTS+=("$HOME/dev")
[ -d "$HOME/Documents/GitHub" ] && SEARCH_ROOTS+=("$HOME/Documents/GitHub")

if [ ${#SEARCH_ROOTS[@]} -gt 0 ]; then
    while IFS= read -r hook; do
        echo "  • $hook"
        PER_REPO_HOOKS_FOUND=$((PER_REPO_HOOKS_FOUND + 1))
    done < <(find "${SEARCH_ROOTS[@]}" -path "*/.git/hooks/post-checkout" -not -name "*.sample" 2>/dev/null)

    if [ "$PER_REPO_HOOKS_FOUND" -eq 0 ]; then
        echo "  (none found in ${SEARCH_ROOTS[*]})"
    else
        echo
        echo "  ✓ These per-repo hooks will continue to work — the global hook"
        echo "    chains to them automatically (see post-checkout source)."
    fi
else
    echo "  (skipped — no common code dirs found under \$HOME)"
fi

# ---------------------------------------------------------------------------
# Done.
# ---------------------------------------------------------------------------
echo
echo "✅ Install complete."
echo
echo "Next steps:"
echo "  • Test:      git worktree add /tmp/wt-test -b chore/test-worktree-env-copy"
echo "               (in any repo with .env files — should print '📋 Worktree detected')"
echo "  • Cleanup:   cd <that-repo> && git worktree remove /tmp/wt-test && git branch -D chore/test-worktree-env-copy"
echo "  • Uninstall: $SCRIPT_DIR/uninstall.sh"
