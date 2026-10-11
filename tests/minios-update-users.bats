#!/usr/bin/env bats

setup() {
    [ "$(id -u)" = 0 ] || skip "account merge integration requires root"
    WORK=$(mktemp -d)
    ROOT="$WORK/root"
    mkdir -p "$ROOT/usr/bin" "$ROOT/usr/lib/live" "$ROOT/etc" "$ROOT/tmp" "$ROOT/dev" "$ROOT/bundles/00-core.sb/etc" "$ROOT/bundles/04-desktop.sb/etc"
    # Only shell redirection uses this path; /tmp may be mounted nodev.
    : >"$ROOT/dev/null"
    mkdir "$ROOT/proc"
    mount -t proc proc "$ROOT/proc"
    ln -s /proc/self/fd "$ROOT/dev/fd"
    ln -s usr/bin "$ROOT/bin"
    for COMMAND in bash id ls head mktemp rm cp find sort awk mv basename touch; do
        PROGRAM=$(command -v "$COMMAND")
        cp -L --parents "$PROGRAM" "$ROOT"
        while read -r LIBRARY; do
            cp -L --parents "$LIBRARY" "$ROOT"
        done < <(ldd "$PROGRAM" | awk '{for (i=1; i<=NF; i++) if ($i ~ /^\//) print $i}')
    done
    cp "$BATS_TEST_DIRNAME/../frontend/minios-update-users" "$ROOT/merge-users"
    printf 'minios_debug_enabled() { return 1; }\n' >"$ROOT/usr/lib/live/config.sh"
}

teardown() {
    if [ -n "${ROOT:-}" ] && mountpoint -q "$ROOT/proc"; then
        umount "$ROOT/proc" || return 1
    fi
    [ -z "${WORK:-}" ] || rm -rf "$WORK"
}

@test "account merge retains the live user from direct AUFS and standard OverlayFS layout" {
    for LAYOUT in aufs workdir; do
        UPPER="$ROOT/upper"
        rm -rf "$UPPER"
        if [ "$LAYOUT" != aufs ]; then
            mkdir -p "$UPPER/changes/etc" "$UPPER/$LAYOUT"
            UPPER="$UPPER/changes"
        else
            mkdir -p "$UPPER/etc"
        fi
        for FILE in passwd shadow group gshadow; do
            printf 'root:core\n' >"$ROOT/bundles/00-core.sb/etc/$FILE"
            printf 'desktop:module\n' >"$ROOT/bundles/04-desktop.sb/etc/$FILE"
            printf 'live:retained\nroot:changed\n' >"$UPPER/etc/$FILE"
        done
        run chroot "$ROOT" /bin/bash /merge-users /bundles /upper
        [ "$status" = 0 ] || printf '%s\n' "$output" >&2
        [ "$status" = 0 ]
        for FILE in passwd shadow group gshadow; do
            grep -qx live:retained "$ROOT/etc/$FILE"
            grep -qx root:changed "$ROOT/etc/$FILE"
            grep -qx desktop:module "$ROOT/etc/$FILE"
        done
    done
}
