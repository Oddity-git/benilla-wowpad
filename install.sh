#!/usr/bin/env bash
# install.sh - put WowPad on top of a benilla checkout, whatever state that checkout is in.
#
#   double-click install.sh (choose Run / Execute), or:
#   bash install.sh [path/to/benilla]      install or update, then build (asks for the folder if not given)
#   bash install.sh --no-build [path]      install or update, skip the build
#   bash install.sh --patches-only [path]  only bring the engine patches in (for update scripts)
#   bash install.sh --remove [path]        take WowPad's engine patches back out and delete the crate
#
# Safe to run again after every benilla update, and on forks of it: it copies
# this folder to crates/benilla-wowpad, then applies the engine patches in patches/ in their
# numbered order, like a load order. A patch already in is skipped; one that no longer fits stops
# the run and names the files, and nothing after it is touched.
# Extra cargo features: WOWPAD_FEATURES="feat1,feat2" bash install.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BUILD=1 PATCHES_ONLY=0 REMOVE=0 ROOT=""
for a in "$@"; do
    case "$a" in
        --no-build) BUILD=0 ;;
        --patches-only) PATCHES_ONLY=1; BUILD=0 ;;
        --remove) REMOVE=1; BUILD=0 ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        -*) echo "unknown option $a (try --help)"; exit 2 ;;
        *) ROOT="$a" ;;
    esac
done

# Double-clicked from a file manager: there is no terminal to show the output in, so open one
# running this script, which stays open at the end.
if [ ! -t 1 ] && [ -z "${WOWPAD_IN_TERMINAL:-}" ] && [ -z "${CI:-}" ] &&
    { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
    export WOWPAD_IN_TERMINAL=1
    run="bash \"$0\" $*; echo; read -r -p 'Press Enter to close.' _"
    for t in konsole gnome-terminal kgx xfce4-terminal kitty alacritty wezterm foot xterm x-terminal-emulator; do
        command -v "$t" >/dev/null || continue
        case "$t" in
            gnome-terminal|kgx) exec "$t" -- bash -c "$run" ;;
            wezterm) exec "$t" start -- bash -c "$run" ;;
            *) exec "$t" -e bash -c "$run" ;;
        esac
    done
fi

is_benilla() { [ -n "$1" ] && [ -f "$1/Cargo.toml" ] && [ -d "$1/crates/benilla-app" ]; }

# No folder given (a double-click): the benilla folder this one sits in (crates/benilla-wowpad),
# the current folder, a single benilla folder next to this one, else ask with a folder picker.
if [ -z "$ROOT" ]; then
    up2="$(dirname "$(dirname "$SRC")")"
    siblings=()
    for d in "$(dirname "$SRC")"/*/; do is_benilla "${d%/}" && siblings+=("${d%/}"); done
    if is_benilla "$up2"; then ROOT="$up2"
    elif is_benilla "$PWD" && [ "$PWD" != "$SRC" ]; then ROOT="$PWD"
    elif [ "${#siblings[@]}" = 1 ]; then ROOT="${siblings[0]}"
    else
        msg="Pick your benilla folder (the one with Cargo.toml and crates in it)"
        if command -v kdialog >/dev/null; then ROOT="$(kdialog --title "$msg" --getexistingdirectory "$HOME" 2>/dev/null)"
        elif command -v zenity >/dev/null; then ROOT="$(zenity --file-selection --directory --title="$msg" 2>/dev/null)"
        else read -r -p "$msg: " ROOT
        fi
        [ -n "$ROOT" ] || { echo "STOPPED: no benilla folder picked. Run again and pick it, or pass its path."; exit 1; }
    fi
    echo "benilla folder: $ROOT"
fi
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "STOPPED: no such folder"; exit 1; }

stop() {
    printf '\nSTOPPED: %s\n' "$1"
    printf 'Nothing after this step was changed.\n'
    exit 1
}
say() { printf '==> %s\n' "$1"; }

is_benilla "$ROOT" ||
    stop "$ROOT is not a benilla checkout (no crates/benilla-app). Pick the benilla folder itself."
command -v git >/dev/null || stop "git is not installed"
DEST="$ROOT/crates/benilla-wowpad"
# WowPad already there as this very folder (cloned or linked into crates/): use it as it is.
[ "$(cd "$DEST" 2>/dev/null && pwd -P)" = "$SRC" ] && DEST="$SRC"
IS_REPO=0
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 && IS_REPO=1

# Whether a patch is already in: it reverses cleanly, or (after benilla moved the lines around it)
# every substantial line it adds is already in its file.
already_in() {
    (cd "$ROOT" && git apply --reverse --check "$1" 2>/dev/null) && return 0
    local file="" line trimmed found=0
    while IFS= read -r line; do
        case "$line" in
            "+++ b/"*) file="$ROOT/${line#+++ b/}" ;;
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

# A patch, in the version for the newest benilla, else (an older benilla) the one before it, kept in
# patches/legacy/. An older version this checkout already carries is taken out first, since the
# newer one is written for the code without it.
apply_patch() {
    local p="$1" name old
    name="$(basename "$p" .patch)"
    old="$(dirname "$p")/legacy/$name.patch"
    if ! (cd "$ROOT" && git apply --reverse --check "$p" 2>/dev/null); then
        for prev in "$(dirname "$p")/legacy/$name"*.patch; do
            [ -f "$prev" ] || continue
            if (cd "$ROOT" && git apply --reverse --check "$prev" 2>/dev/null); then
                (cd "$ROOT" && git apply --reverse "$prev") && echo "  $name: older version taken out"
            fi
        done
    fi
    if already_in "$p"; then
        echo "  $name: already in"
        return 0
    fi
    try_patch "$p" && return 0
    if [ -f "$old" ]; then
        echo "  $name: does not fit this benilla; trying the older version"
        try_patch "$old" && return 0
    fi
    grep '^+++ b/' "$p" | sed 's/^+++ b\//    touches: /'
    stop "patch $name does not fit this benilla version. Update WowPad (git pull in $SRC) and run again; if it still fails, the patch needs refreshing for this benilla"
}

# Applies one patch file by the ways that work, 1 when none does.
try_patch() {
    local p="$1" name
    name="$(basename "$p" .patch)"
    if (cd "$ROOT" && git apply --check "$p" 2>/dev/null); then
        (cd "$ROOT" && git apply "$p") || stop "patch $name failed to apply"
        echo "  $name: applied"
        return 0
    fi
    # Benilla moved on since the patch was made: a three-way merge places it by content. On a
    # conflict the files go back exactly as they were, and the next way gets a try.
    if [ "$IS_REPO" = 1 ]; then
        local files saved
        files="$(grep '^+++ b/' "$p" | sed 's/^+++ b\///')"
        saved="$(mktemp)"
        (cd "$ROOT" && git diff --binary HEAD -- $files) > "$saved"
        if (cd "$ROOT" && git apply -3 "$p" >/dev/null 2>&1) &&
            [ -z "$(git -C "$ROOT" diff --name-only --diff-filter=U)" ]; then
            rm -f "$saved"
            echo "  $name: applied (merged)"
            return 0
        fi
        (cd "$ROOT" && git checkout -q HEAD -- $files 2>/dev/null)
        [ -s "$saved" ] && (cd "$ROOT" && git apply "$saved")
        rm -f "$saved"
    fi
    # A fork that changed the lines next to WowPad's: place each hunk by its nearest context.
    if command -v patch >/dev/null &&
        (cd "$ROOT" && patch --dry-run -p1 -N -F3 -s < "$p" >/dev/null 2>&1); then
        (cd "$ROOT" && patch -p1 -N -F3 -s --no-backup-if-mismatch < "$p") ||
            stop "patch $name failed to apply"
        echo "  $name: applied (placed by nearby lines: build to check it)"
        return 0
    fi
    return 1
}

if [ "$REMOVE" = 1 ]; then
    say "Taking WowPad's engine patches out of $ROOT"
    for p in $(ls -r "$SRC"/patches/[0-9]*.patch); do
        name="$(basename "$p" .patch)"
        if (cd "$ROOT" && git apply --reverse --check "$p" 2>/dev/null); then
            (cd "$ROOT" && git apply --reverse "$p") && echo "  $name: removed"
        elif [ -f "$(dirname "$p")/legacy/$name.patch" ] &&
            (cd "$ROOT" && git apply --reverse --check "$(dirname "$p")/legacy/$name.patch" 2>/dev/null); then
            (cd "$ROOT" && git apply --reverse "$(dirname "$p")/legacy/$name.patch") && echo "  $name: removed (older version)"
        elif command -v patch >/dev/null &&
            (cd "$ROOT" && patch --dry-run -R -p1 -F3 -s < "$p" >/dev/null 2>&1); then
            (cd "$ROOT" && patch -R -p1 -F3 -s --no-backup-if-mismatch < "$p") &&
                echo "  $name: removed (placed by nearby lines)"
        else
            echo "  $name: not in cleanly, left alone (git checkout the files it touches to undo)"
        fi
    done
    if [ "$DEST" != "$SRC" ] && [ -f "$DEST/Cargo.toml" ] && grep -q 'name = "benilla-wowpad"' "$DEST/Cargo.toml"; then
        rm -rf "$DEST" && echo "  crates/benilla-wowpad: deleted"
    fi
    exit 0
fi

if [ "$PATCHES_ONLY" = 0 ]; then
    say "WowPad crate"
    if [ "$DEST" = "$SRC" ]; then
        echo "  already in place ($DEST)"
    else
        if [ -e "$DEST" ] && ! grep -qs 'name = "benilla-wowpad"' "$DEST/Cargo.toml"; then
            stop "$DEST exists and is not WowPad; move it away first"
        fi
        rm -rf "$DEST"
        mkdir -p "$DEST"
        tar -C "$SRC" --exclude=.git --exclude=target -cf - . | tar -C "$DEST" -xf - ||
            stop "could not copy WowPad into $DEST"
        echo "  copied to crates/benilla-wowpad"
    fi
fi

say "Engine patches (in order)"
for p in "$SRC"/patches/[0-9]*.patch; do
    [ -f "$p" ] || continue
    apply_patch "$p"
done

[ "$BUILD" = 1 ] || { echo; echo "Done (no build)."; exit 0; }

command -v cargo >/dev/null || stop "cargo is not installed (https://rustup.rs), so WowPad can't be built"
FEATURES="${WOWPAD_FEATURES:-}"
# Build what the checkout's own game builds by default: every feature the benilla launcher turns on
# by default (a fork's extras included) that reaches benilla-app goes on here too.
launcher="$ROOT/crates/benilla/Cargo.toml"
if [ -f "$launcher" ]; then
    defaults="$(sed -n 's/^default[[:space:]]*=[[:space:]]*\[\(.*\)\].*/\1/p' "$launcher" | tr -d '" ' | tr ',' ' ')"
    for f in $defaults; do
        [ "$f" = dev ] && continue   # WowPad's own default already carries it
        for app in $(grep -E "^$f[[:space:]]*=" "$launcher" | grep -oE '"benilla-app/[A-Za-z0-9_-]+"' | tr -d '"'); do
            case ",$FEATURES," in *",$app,"*) ;; *) FEATURES="${FEATURES:+$FEATURES,}$app" ;; esac
        done
    done
fi
say "Building (cargo build --release -p benilla-wowpad${FEATURES:+ --features $FEATURES})"
(cd "$ROOT" && cargo build --release -p benilla-wowpad ${FEATURES:+--features "$FEATURES"}) ||
    stop "the build failed (the errors are above)"

cat <<EOF

Done. Start the game with:
  cd "$ROOT"
  WOW_HOST=your.server ./target/release/benilla-wowpad

Run this script again after updating benilla or WowPad.
EOF
