#!/bin/bash
# update-benilla-personal: pull the newest physics fork (upstream benilla rides in it) and WowPad into
# ~/Games/benilla-personal, then build. Stops at the first problem and changes nothing after it.
# Double-click "Update Benilla Personal" on the desktop, or run: bash ~/Games/update-benilla-personal.sh

GAME="$HOME/Games/benilla-personal"
PAD="$HOME/Games/benilla-wowpad"

stop() {
    printf '\nSTOPPED: %s\n' "$1"
    printf 'Nothing after this step was changed. Paste this window into Claude if you need help.\n'
    exit 1
}

# Merge $1 (named $2 in messages). A conflict only in test, capture or doc files is settled
# automatically by taking the incoming side for those lines; anything in game code stops the update.
merge() {
    git merge --no-edit "$1" && return 0
    conflicted=$(git diff --name-only --diff-filter=U)
    git merge --abort
    if [ -n "$conflicted" ] && ! echo "$conflicted" | grep -qvE '(_tests?\.rs$|/tests?/|/capture/|\.md$)'; then
        echo "Only test/capture/doc files conflicted; taking $2's side for those lines:"
        echo "$conflicted" | sed 's/^/  /'
        git merge --no-edit -X theirs "$1" && return 0
        git merge --abort
    fi
    echo "Conflicts in:"
    echo "$conflicted" | sed 's/^/  /'
    stop "the $2 merge has conflicts in game code; nothing was merged"
}

cd "$GAME" || stop "no folder $GAME"
# Remember how a conflict was settled, so the same one settles itself next time.
git config rerere.enabled true

# A merge an earlier run left half-done, and leftovers from a build: never real work.
[ -f .git/MERGE_HEAD ] && git merge --abort
git checkout -- Cargo.lock 2>/dev/null
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    git status --short --untracked-files=no
    stop "benilla-personal has uncommitted changes (listed above)"
fi
[ "$(git branch --show-current)" = personal ] ||
    stop "benilla-personal is on branch $(git branch --show-current), not personal"

echo "==> Physics fork"
git fetch origin || stop "could not download the physics fork"
merge origin/ragdoll "physics fork"

echo
echo "==> WowPad"
# Pull from GitHub when it can; otherwise use what's committed locally in the WowPad folder.
git -C "$PAD" pull --ff-only ||
    echo "(could not pull WowPad from GitHub; using what is committed in $PAD)"
# This script's newest version ships with WowPad: take it and start again with it.
SELF="$HOME/Games/update-benilla-personal.sh"
if [ -f "$PAD/tools/update-benilla-personal.sh" ] && ! cmp -s "$PAD/tools/update-benilla-personal.sh" "$SELF"; then
    cp "$PAD/tools/update-benilla-personal.sh" "$SELF" || stop "could not update this script"
    echo "(this update script was updated; running the new one)"
    exec bash "$SELF"
fi
rm -rf crates/benilla-wowpad
mkdir -p crates/benilla-wowpad
git -C "$PAD" archive HEAD | tar -x -C crates/benilla-wowpad || stop "could not copy WowPad"
git add crates/benilla-wowpad
rev=$(git -C "$PAD" rev-parse --short HEAD)
if git diff --cached --quiet; then
    echo "WowPad already up to date ($rev)"
else
    git commit -q -m "WowPad: update to benilla-wowpad $rev" || stop "could not commit WowPad"
    echo "WowPad updated to $rev"
fi

# WowPad's engine changes outside its own folder: each patch once, in order, skipped once it is in.
# In: it reverses cleanly, or every substantial line it adds is already in its file (a later patch
# can change the lines around an earlier one, which then no longer reverses).
already_in() {
    git apply --reverse --check "$1" 2>/dev/null && return 0
    local file="" line trimmed found=0
    while IFS= read -r line; do
        case "$line" in
            "+++ b/"*) file="${line#+++ b/}" ;;
            "+++ "*) file="" ;;
            "+"*)
                [ -n "$file" ] || continue
                trimmed="$(printf '%s' "${line#+}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                [ "${#trimmed}" -ge 12 ] || continue
                [ -f "$file" ] && grep -qF -- "$trimmed" "$file" || return 1
                found=1
                ;;
        esac
    done < "$1"
    [ "$found" = 1 ]
}
# The files a patch touches, new ones included (git add -u alone misses a file a patch creates).
patch_files() { grep '^+++ b/' "$1" | sed 's/^+++ b\///'; }

for patch in crates/benilla-wowpad/patches/updates/*.patch; do
    [ -f "$patch" ] || continue
    name=$(basename "$patch" .patch)
    if ! already_in "$patch"; then
        git apply "$patch" || stop "WowPad's engine patch $name does not fit this build"
        echo "Applied WowPad engine patch $name"
    fi
    # Commit what the patch touched, also when an earlier run applied it and left a file out.
    git add -- $(patch_files "$patch")
    if ! git diff --cached --quiet; then
        git commit -q -m "WowPad engine patch: $name" || stop "could not commit $name"
    fi
done

echo
echo "==> Building (this can take a few minutes)"
cargo build --release -p benilla-wowpad --features benilla-app/ragdoll || stop "the build failed"

printf '\nDone. Your shortcut now runs the updated build. You can close this window.\n'
