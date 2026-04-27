# worktree-env-copy

**Auto-copy `.env*` files to new git worktrees.** A one-script global git hook that runs every time you (or your AI coding agent) creates a worktree.

```text
$ git worktree add ../wt-feature-x -b feature-x
Preparing worktree (new branch 'feature-x')
HEAD is now at 1302744 chore: update readme
📋 Worktree detected: /Users/you/repo/wt-feature-x
  ✓ Copied .env
  ✓ Copied apps/api/.env.local
  ⊘ Skipped .env.example (already exists)
✅ Environment files synced!
```

---

## Why this exists

`git worktree add` doesn't copy untracked files. `.env*` files are untracked by design — they hold secrets — so every new worktree is **dead on arrival** until you manually copy them over. This is annoying when you do it by hand. It becomes a real bottleneck when **AI coding agents spin up worktrees on demand**: Claude Code, Codex, Cursor's agent mode, Aider, and others routinely create worktrees, and every one of them lands without env files.

This repo is a single global `post-checkout` hook that fixes it. Set it up once. Works for every repo on your machine. Works no matter who creates the worktree — you, an agent, an IDE, a CI script.

## What it does

On every `git worktree add`:

- **Copies** every `.env*` file from the main repo into the new worktree, preserving directory structure (so `apps/api/.env.local` lands at `apps/api/.env.local` in the worktree, not at the root).
- **Respects `.gitignore`** — skips dependency directories like `node_modules/`, `dist/`, `.venv/` so you never copy `.env` files belonging to third-party packages.
- **Never overwrites** an existing file in the worktree. Re-runs are safe.
- **Chains to per-repo hooks** — if a repo has its own `.git/hooks/post-checkout` (e.g. git-lfs's hook), it still runs. We don't break LFS, husky, or anything else.

## Quick start

```bash
git clone https://github.com/DaniAkash/worktree-env-copy.git
cd worktree-env-copy
./install.sh
```

That's it. The installer is idempotent — re-running won't hurt anything.

### Verify it works

Pick any repo that has a `.env` file:

```bash
cd ~/path/to/some-repo
git worktree add /tmp/wt-test -b chore/test-env-copy
```

You should see:

```text
📋 Worktree detected: /tmp/wt-test
  ✓ Copied .env
✅ Environment files synced!
```

Cleanup:

```bash
git worktree remove /tmp/wt-test
git branch -D chore/test-env-copy
```

## Why this matters for AI coding agents

Modern coding agents (Claude Code, Codex, Cursor agent mode, Aider, etc.) often work in **isolated git worktrees** so multiple tasks can run in parallel without stepping on each other. But the moment that worktree is missing your `.env`:

- The agent can't run your dev server
- The agent can't run your tests
- The agent gets confused-looking errors and starts guessing
- You end up babysitting it

With this hook installed, every agent-spawned worktree comes up with the env it needs. The agent never has to know the hook exists.

## Manual install (if you want to read the script first)

The hook is a single bash script in this repo: [`post-checkout`](./post-checkout). It's ~80 lines, mostly comments. Read it before installing globally if you're cautious — that's a sensible thing to do.

If you'd rather install by hand instead of running `install.sh`:

```bash
mkdir -p ~/.git-hooks
cp post-checkout ~/.git-hooks/post-checkout
chmod +x ~/.git-hooks/post-checkout
git config --global core.hooksPath ~/.git-hooks
```

If you already have `core.hooksPath` set somewhere else, copy `post-checkout` there instead. Don't change `core.hooksPath` — the hook respects whatever you've already configured.

## Per-repo hook chaining (the important detail)

`git config --global core.hooksPath ~/.git-hooks` **replaces** per-repo hooks — it does not stack with them. If a repo had `.git/hooks/post-checkout` before, that hook stops running once `core.hooksPath` is set globally.

This would silently break **git-lfs**, which installs a per-repo `post-checkout` hook on every LFS-enabled repo. After the env-copy logic finishes, our hook does this:

```bash
PER_REPO_HOOK="$GIT_COMMON_DIR/hooks/post-checkout"
if [ -x "$PER_REPO_HOOK" ] && [ "$PER_REPO_HOOK" != "$0" ]; then
    exec "$PER_REPO_HOOK" "$@"
fi
```

So per-repo hooks **always run**, regardless of whether the env-copy block succeeded, was skipped, or errored out. The env-copy block is wrapped in `{ ...; } || true` for that exact reason — its failure can never block the chain.

This means **husky, lefthook, custom team hooks, LFS — they all keep working**.

## Uninstall

```bash
cd worktree-env-copy
./uninstall.sh
```

The uninstaller is conservative:

- Only removes the `post-checkout` hook if it byte-for-byte matches our version
- Only unsets `core.hooksPath` if it points at `~/.git-hooks` and that directory is empty afterwards
- Refuses to delete anything it doesn't recognize

If something looks unexpected, it tells you what to do manually rather than guessing.

## Troubleshooting

### "Hook doesn't run when I create a worktree"

Check `core.hooksPath` is configured:

```bash
git config --global core.hooksPath
# Should output something like /Users/you/.git-hooks
```

If empty, re-run `./install.sh`.

Check the hook is executable:

```bash
ls -la ~/.git-hooks/post-checkout
# Should show -rwxr-xr-x (note the 'x' for executable)
```

If not, `chmod +x ~/.git-hooks/post-checkout`.

### "Hook runs but no `.env*` files appear"

Confirm the source repo actually has `.env*` files outside `node_modules`:

```bash
cd /path/to/main-repo
find . -name ".env*" -not -path "./.git/*" -not -path "./node_modules/*"
```

If the only matches are inside gitignored directories, the hook (correctly) skips them.

### "I want to debug the hook"

Run it manually inside a worktree with bash trace:

```bash
cd /path/to/worktree
bash -x ~/.git-hooks/post-checkout 0 0 1
```

The third arg (`1`) tells the hook this is a branch checkout, which is what `git worktree add` triggers.

### "It's copying `.env.example` and that bothers me"

`.env.example` is usually tracked, so when the worktree is created it already exists from the index, and the hook skips it (you'll see `⊘ Skipped .env.example (already exists)`). If you have an *untracked* `.env.example` and want to exclude it, edit your local copy of `~/.git-hooks/post-checkout` and add `! -name ".env.example"` to the `find` predicate.

## How it works (under the hood)

### `--git-common-dir`, not `--git-dir`

Inside a worktree, `git rev-parse --git-dir` returns `.git/worktrees/<name>`. Its parent is the wrong thing — that's `.git/worktrees/`, not the repo root. `--git-common-dir` always points to the *main* `.git` directory, so `dirname` of that gives the actual main repo. This is the only reliable way to find the source repo from inside a worktree.

### `$3 == 1` branch flag

`post-checkout` receives three args: `prev_head new_head branch_flag`. The flag is `1` for branch checkouts and `0` for file checkouts (`git checkout -- some-file`). We gate the env-copy on `$3 == 1` so we don't run on every file checkout, but we still chain to per-repo hooks unconditionally because LFS cares about both kinds of checkout.

### Pruning gitignored dirs via `git check-ignore`

Instead of finding all `.env*` and then filtering, the hook walks two levels deep, asks git which of those directories are ignored, and adds them as `find` `-prune` arguments upfront. This is faster (no traversing `node_modules/` with thousands of files) and uses each repo's actual `.gitignore` instead of a hardcoded blocklist.

### Self-reference guard

The chain check is `[ "$PER_REPO_HOOK" != "$0" ]` — paranoia for the case where someone symlinks a per-repo hook to the global one. Without the guard, the hook would call itself forever.

## Caveats

- **Machine-global**. This sets `core.hooksPath` for your entire git installation, not per-repo. That's intentional — it's what makes the hook fire for tools that bypass your shell. But you should know.
- **Bash 3.2 compatible**. Tested on the macOS system bash. No bash 4+ features used.
- **`maxdepth 3` for prune discovery**. Gitignored directories deeper than 3 levels won't be pruned and `find` will descend into them. In practice this only matters for unusual nested monorepos and the cost is small.
- **No Windows support**. Bash hook + POSIX paths. PRs welcome.

## Credits

Adapted from [therohitdas/copy-env](https://github.com/therohitdas/copy-env) — original idea and bulk of the env-copy logic. Modified to:

- Always chain to per-repo hooks (so git-lfs, husky, and friends keep working)
- Wrap the env-copy block in `{ ...; } || true` so its failure can't break the chain
- Add an idempotent installer with collision detection and a conservative uninstaller

## License

MIT — see [LICENSE](./LICENSE).
