---
name: rebase-on-upstream-latest
description: Review upstream Dinky releases, trial-rebase this fork, test compatibility, and propose dotfiles config updates.
---

# rebase on upstream latest

1. Record branch, HEAD, and working-tree status. Preserve unrelated changes.
2. Verify remotes: `upstream` = `mikker/Dinky`, `origin` = `gshahbazian/Dinky`.
   Fetch upstream and tags. Target the requested release or latest stable tag.
3. Find the fork's upstream base. Read the target changelog, intervening commits,
   and relevant diffs. Summarize features, breaking changes, and overlapping fixes.
4. Read `../dotfiles/dinky/dinky.toml` (or resolve the active config symlink).
   Check existing bindings and settings against upstream changes.
5. Create `gabe/check-upstream-<version>` from the fork tip. Do not overwrite an
   existing branch without inspecting it. Rebase onto the release tag.
6. Record conflicts before resolving them. Preserve upstream fixes and our custom
   behavior. Stop at ambiguous decisions. Keep logical, lowercase commit messages.
7. Review `git range-diff <old-base>..<old-tip> <release-tag>..<trial-tip>`.
8. Run `git diff --check`, `swift test`, then:
   ```bash
   IDENTITY='<available signing identity>' VERSION='<release>' scripts/bundle.sh
   build/dinky.app/Contents/MacOS/dinky doctor
   ```
9. Report conflict files/resolutions, test totals, build/config results, and trial
   branch/commit. Distinguish automated checks from live testing. Return to the
   original branch unless requested otherwise.
10. Ask which suggested dotfiles changes the user wants. Separate compatibility
    fixes from optional features. Keep the app-name floating rule unless asked.

Preserve our custom changes from our fork. If they are in direct conflict with
latest Dinky, ask how to resolve.

Only when requested:
- Config edits: validate; reload only if the installed version supports them.
- Live test: check out trial; run `IDENTITY=... scripts/install-local.sh` without
  app backups. Check version, doctor, Spaces, focus/toggling, and sizing. Restore
  test-only layout changes; do not close user windows to make test cases.
- Promote: make `main` match the tested branch; push with explicit
  `--force-with-lease=refs/heads/main:<fetched-remote-sha>`. Verify matching tips.

Assessment alone does not install, promote, or push. Follow existing authorization
without asking for it again.
