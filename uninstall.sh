#!/usr/bin/env bash
# Uninstaller for the worktree-env-copy global git hook.
#
# https://github.com/DaniAkash/worktree-env-copy
#
# Standalone — runnable on its own without a checkout of the repo. Detects
# our hook by looking for the project URL marker inside the installed hook
# rather than byte-comparing against a source file. This keeps uninstall
# working across hook versions.
#
# Conservative: refuses to remove a hook that doesn't carry our marker.
# Pass --force to remove anyway (only if you're sure what you're doing).

set -euo pipefail

# Marker string the installed hook contains. Used to identify "this is our
# hook" without needing the source file alongside.
MARKER="https://github.com/DaniAkash/worktree-env-copy"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE=1
            ;;
        --help|-h)
            cat <<EOF
worktree-env-copy uninstaller

Usage:
  ./uninstall.sh           remove our hook (refuses if not recognized)
  ./uninstall.sh --force   remove the post-checkout hook even if it doesn't
                           carry our marker (use only if you know what you're doing)
  ./uninstall.sh --help    show this message

Source: $MARKER
EOF
            exit 0
            ;;
        *)
            echo "✗ Unknown argument: $arg" >&2
            echo "  Try --help" >&2
            exit 2
            ;;
    esac
done

echo "→ worktree-env-copy uninstaller"
echo

# ---------------------------------------------------------------------------
# Step 1 — Locate the installed hook via core.hooksPath.
# ---------------------------------------------------------------------------
EXISTING_HOOKS_PATH="$(git config --global core.hooksPath 2>/dev/null || true)"
EXISTING_HOOKS_PATH="${EXISTING_HOOKS_PATH/#\~/$HOME}"

if [ -z "$EXISTING_HOOKS_PATH" ]; then
    echo "  ℹ No global core.hooksPath set."
    echo "  ℹ Nothing to uninstall — exiting."
    exit 0
fi

TARGET_HOOK="$EXISTING_HOOKS_PATH/post-checkout"

if [ ! -f "$TARGET_HOOK" ]; then
    echo "  ℹ core.hooksPath = $EXISTING_HOOKS_PATH"
    echo "  ℹ No post-checkout hook at $TARGET_HOOK — nothing to remove."
else
    echo "  ℹ Found hook at: $TARGET_HOOK"

    # -----------------------------------------------------------------------
    # Step 2 — Identify the hook via marker.
    # -----------------------------------------------------------------------
    REMOVE=0
    if grep -q -F "$MARKER" "$TARGET_HOOK" 2>/dev/null; then
        echo "  ✓ Recognized as worktree-env-copy hook (marker found)."
        REMOVE=1
    elif [ "$FORCE" = "1" ]; then
        echo "  ⚠ Hook does NOT contain our marker — but --force was passed."
        echo "    Proceeding with removal as instructed."
        REMOVE=1
    else
        echo "  ⚠ Hook does NOT contain our marker — refusing to remove."
        echo
        echo "    If this is our hook in some modified form and you want to"
        echo "    remove it anyway, re-run with: ./uninstall.sh --force"
        echo
        echo "    Otherwise, leave it in place."
    fi

    # -----------------------------------------------------------------------
    # Step 3 — Remove the hook.
    # -----------------------------------------------------------------------
    if [ "$REMOVE" = "1" ]; then
        rm "$TARGET_HOOK"
        echo "  ✓ Removed $TARGET_HOOK"
    fi
fi

# ---------------------------------------------------------------------------
# Step 4 — Unset core.hooksPath if it points at our default location AND
# the directory is now empty. Conservative: never unset a path the user
# might be using for other hooks, never delete a non-empty directory.
# ---------------------------------------------------------------------------
echo
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
        echo "  ℹ $DEFAULT_DIR is not empty — leaving core.hooksPath set."
        echo "    Other files present:"
        ls -1 "$DEFAULT_DIR" | sed 's/^/      • /'
        echo
        echo "    To unset core.hooksPath manually:"
        echo "      git config --global --unset core.hooksPath"
    fi
else
    echo "  ℹ core.hooksPath = $EXISTING_HOOKS_PATH"
    echo "    (not our default $DEFAULT_DIR — leaving it alone)"
    echo
    echo "    To unset it manually:"
    echo "      git config --global --unset core.hooksPath"
fi

echo
echo "✅ Uninstall complete."
echo
echo "Verify nothing's left:"
echo "  git config --global core.hooksPath   # should print nothing"
echo "  ls ~/.git-hooks 2>/dev/null          # should not exist or be empty"
