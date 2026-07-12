#!/bin/sh
# Installs this repo's tracked git hooks (.githooks/*) into .git/hooks.
#
# Git hooks aren't versioned by git itself, so .githooks/ holds the tracked
# source and this script copies it into the real hooks dir. The hooks dir is
# shared across all worktrees of a clone, so run this once per clone (no need
# to re-run it after `git worktree add`).
set -eu

repo_root=$(git rev-parse --show-toplevel)
hooks_dir=$(git rev-parse --git-common-dir)/hooks

mkdir -p "$hooks_dir"

for hook in "$repo_root"/.githooks/*; do
    name=$(basename "$hook")
    cp "$hook" "$hooks_dir/$name"
    chmod +x "$hooks_dir/$name"
    echo "Installed $name -> $hooks_dir/$name"
done
