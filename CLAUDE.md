# CLAUDE.md

Project-specific guidance for Claude working on SFTransitWatch.

## Never run remote git or `gh` network commands

The sandbox this repo runs in has **no SSH credentials** for GitHub. Any command that talks to the remote will fail with `Permission denied (publickey)`. The user has to run these themselves.

Do not run:
- `git push`, `git push -u origin …`, `git push --tags`, `git push origin <tag>`
- `git fetch`, `git fetch origin`, `git pull`, `git pull --rebase origin …`
- `gh pr create`, `gh pr merge`, `gh pr checkout`, `gh pr list` or any other `gh` subcommand that hits the API
- `gh release create`, `gh release list`
- `gh secret …`, `gh api …`

What to do instead:
- **Preparing a PR:** make the commit(s) locally, then print the exact `git push` and `gh pr create` commands for the user to copy-paste. Use a HEREDOC body so the formatting survives copy-paste.
- **Checking remote state:** ask the user to run `git log --oneline -N` / `git status` / `gh pr view` and paste output. Don't retry the remote command.
- **After the user pushes:** they'll confirm; then you can resume local work (new branch, local commits).

### PR titles must follow Conventional Commits

`.github/workflows/validate-pr-title.yml` rejects any PR title that does not match the Conventional Commits format. **Every suggested `gh pr create --title` must already conform** — do not hand the user a title that will fail the check.

Required shape: `<type>(<optional scope>)<optional !>: <lowercase subject>`
- type ∈ `feat | fix | docs | chore | refactor | test | build | ci | perf | style`
- subject starts lowercase, no trailing period
- `!` or `BREAKING CHANGE:` only when it's actually a breaking change

Examples that pass: `fix: surface 511.org API errors`, `feat(watch): persist pinned stops`, `chore: bump xcode project version`.
Examples that fail: `Watch app quick-wins: ...` (no type, capitalized), `Fix: something` (capitalized type), `feat: Add X` (capitalized subject).

When bundling several unrelated fixes on one branch, pick the single type that best describes the headline change — or, if nothing dominates, use `chore:` and list the individual commits (which each already have their own conventional prefix) in the PR body.

Local, non-network git commands are fine: `git status`, `git log`, `git diff`, `git show`, `git branch`, `git checkout <existing-branch>`, `git commit`, `git tag` (without push), `git reset`, `git restore`, etc.

## Apple Developer Portal / Xcode Cloud gotchas

### Xcode Cloud cannot auto-register new bundle IDs

Automatic signing in Xcode Cloud can only USE bundle IDs that already exist on the team. It cannot CREATE new ones from CI. The exact error when it tries:

```
error: exportArchive Automatic signing cannot register bundle identifier "<id>".
error: exportArchive No profiles for '<id>' were found
```

**Never tell the user to delete a bundle ID on the assumption that "Xcode Cloud will recreate it on next build."** It won't. That advice was given once on `org.larner.SFTransitWatch.watchkitapp`, the user followed it, and the build has been broken since because re-creation requires a human in App Store Connect.

If a bundle ID needs to be (re)registered, the fix is always a manual step at https://developer.apple.com/account/resources/identifiers/list — there is no repo-side workaround.

### Bundle IDs in use

- iOS companion: `org.larner.SFTransitWatch`
- Watch app: `org.larner.SFTransitWatch.watchkitapp` (convention: `<iOS-bundle-id>.watchkitapp`)
- Old template leftover still registered on the portal: `com.example.SFTransitWatch.watchkitapp` (unused; safe to ignore unless cleaning up)

### Team ID lives in `Developer.xcconfig`

`Config.xcconfig` does `#include? "Developer.xcconfig"` (note the `?` — optional). `Developer.xcconfig` is gitignored and sets `DEVELOPMENT_TEAM`. Cloud builds work without it; local builds that need signing need the file. See README for setup.

## Version automation (once PR 3 merges)

- `MARKETING_VERSION` lives in `Config.xcconfig`, bumped by `.github/workflows/version-bump.yml` based on Conventional Commits PR titles.
- `CURRENT_PROJECT_VERSION` is overwritten per-build by `ci_scripts/ci_pre_xcodebuild.sh` from `$CI_BUILD_NUMBER`.
- PR titles are validated by `.github/workflows/validate-pr-title.yml` — `feat|fix|docs|chore|refactor|test|build|ci|perf|style` prefixes, optional `(scope)`, optional `!` for breaking, lowercase subject.
- Bump mapping: `feat!`/`BREAKING CHANGE:` → major, `feat` → minor, `fix`/`perf` → patch, everything else → no bump. Full docs in `docs/release-process.md`.

## Running tests

### Phone unit tests

Use the `SFTransitWatch` scheme on an iPhone 17 simulator (requires iOS 26.4 — the `SFTransitWatchPhoneTests` deployment target). Via the localdev MCP tool:

```
scheme: SFTransitWatch
destination: platform=iOS Simulator,id=BD6ECC50-723A-494E-8705-CC0C5913322F  # iPhone 17, iOS 26.4.1
code_signing_allowed_no: true
```

Or raw xcodebuild:
```bash
xcodebuild test -scheme SFTransitWatch \
  -destination 'platform=iOS Simulator,id=BD6ECC50-723A-494E-8705-CC0C5913322F' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
```

### Watch unit tests

Use the `SFTransitWatch Watch App` scheme with an Apple Watch SE 3 (44mm) watchOS 26.4 simulator. **The MCP `xcodebuild_test` tool rejects `name=` destinations for watchOS — always use `id=` instead.**

```
scheme: SFTransitWatch Watch App
destination: platform=watchOS Simulator,id=BE4F30CB-89F7-45F5-A868-A250522FB4E0
code_signing_allowed_no: true
```

Or raw xcodebuild:
```bash
xcodebuild test -scheme 'SFTransitWatch Watch App' \
  -destination 'platform=watchOS Simulator,id=BE4F30CB-89F7-45F5-A868-A250522FB4E0' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
```

No special signing setup required — all tests pass with default simulator signing.

### Snapshot tests

See the README for snapshot test instructions — they use the wrapper scripts `bin/run-watch-snapshot-tests.sh` and `bin/run-phone-snapshot-tests.sh`.

## Planning/spec docs

`docs/superpowers/` is gitignored on purpose — specs and plans stay local. Don't try to `git add` anything under that path.
