# Release process

SFTransitWatch uses automated semver releases driven by PR titles.

## How it works

1. Every PR title must follow [Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>)?!?: <subject>`. The `validate-pr-title` check blocks merges when it doesn't.
2. Merge the PR into `main` via squash merge. GitHub writes the PR title as the squash-commit subject.
3. `.github/workflows/version-bump.yml` reads that subject, decides the bump, edits `Config.xcconfig`, commits, tags `vX.Y.Z`, pushes, and creates a GitHub Release with auto-generated notes.
4. The next Xcode Cloud build picks up the new `MARKETING_VERSION` and combines it with a fresh `$CI_BUILD_NUMBER` (injected by `ci_scripts/ci_pre_xcodebuild.sh`).

## Prefix → bump mapping

| PR title prefix | MARKETING_VERSION bump |
|---|---|
| `feat!:` / any with `BREAKING CHANGE:` in body | major (1.2.3 → 2.0.0) |
| `feat:` | minor (1.2.3 → 1.3.0) |
| `fix:` / `perf:` | patch (1.2.3 → 1.2.4) |
| `docs:` / `chore:` / `ci:` / `test:` / `refactor:` / `style:` / `build:` | none |

Scope is optional and doesn't affect the bump (e.g. `fix(siri): typo` still patches).

## Required setup (one-time)

- Repo secret `VERSION_BUMP_TOKEN`: fine-grained PAT, `contents: write` on this repo. Needed because the default `GITHUB_TOKEN` cannot bypass branch protection on `main`. Rotate yearly.
- Branch protection on `main`: enable "Require status checks to pass before merging" with `Validate PR title follows Conventional Commits` as a required check.
- Repo merge settings: allow squash-merge only.

## Emergency manual bump

If the Action is down and you need to ship:

```sh
# Edit Config.xcconfig, change MARKETING_VERSION to the new value.
git add Config.xcconfig
git commit -m "chore: release vX.Y.Z [skip ci]"
git push origin main
git tag vX.Y.Z
git push origin vX.Y.Z
gh release create vX.Y.Z --title "vX.Y.Z" --generate-notes
```

The `[skip ci]` in the commit message prevents the bump workflow from running on your manual commit.

## Troubleshooting

- **Two PRs merged but only one bump landed:** the workflow includes a 3-attempt rebase/retry loop, so this shouldn't happen. If it does, manually re-run the workflow on the later commit via the Actions tab.
- **Bump ran on a docs-only PR:** it shouldn't — `docs:` is in the "none" bucket. If it did, check whether the PR title actually started with `feat`/`fix`/`perf` or whether a body line contained `BREAKING CHANGE:`.
- **Xcode Cloud build number didn't increment:** check Xcode Cloud's build log for the `ci_pre_xcodebuild.sh` output. Confirm `CI_BUILD_NUMBER` was set.
- **Workflow pushed the commit and tag but `gh release create` failed:** the release step runs last; a failure here leaves the tag on the remote without a matching GitHub Release. Recover with `gh release create vX.Y.Z --title "vX.Y.Z" --generate-notes` from a local clone.

## What's explicitly out of scope

- Local `commit-msg` hook enforcement. Squash merges mean only the PR title matters; per-commit linting is noise.
- `CHANGELOG.md`. GitHub Releases with auto-generated notes cover the same ground.
- Pre-release labels (`-beta.1`). Add if/when we need a beta track.
