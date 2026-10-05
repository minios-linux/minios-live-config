#!/bin/bash
# Run the real frontend with a read-only upper alias and a writable merged root.
set -euo pipefail
[ "$(id -u)" = 0 ] || exit 77
ROOT=$(dirname "$(dirname "$(readlink -f "$0")")")
ARCHIVE=$1
PARENT=$2
FRONTEND=${3:-$ROOT/frontend/minios-update-dpkg}
[ -f "$ARCHIVE" ] && [ -d "$PARENT" ] && [ -f "$FRONTEND" ] || exit 1
mount --make-rprivate /
WORK=$(mktemp -d "$PARENT/dpkg-overlay.XXXXXX")
cleanup() {
    mountpoint -q "$WORK/merged/run/session-upper" && umount "$WORK/merged/run/session-upper" || :
    mountpoint -q "$WORK/merged" && umount "$WORK/merged" || :
    rm -rf "$WORK"
}
trap cleanup EXIT
mkdir "$WORK/lower" "$WORK/upper" "$WORK/work" "$WORK/merged"
tar -xzf "$ARCHIVE" -C "$WORK/lower"
mkdir -p "$WORK/lower/dev"
rm -f "$WORK/lower/dev/null"
mknod -m666 "$WORK/lower/dev/null" c 1 3
mkdir -p "$WORK/lower/usr/lib/live" "$WORK/lower/run/session-upper" \
    "$WORK/lower/modules/core/var/lib/dpkg" "$WORK/lower/modules/extra/var/lib/dpkg"
install -m755 "$FRONTEND" "$WORK/lower/usr/bin/minios-update-dpkg"
install -m755 "$ROOT/scripts/minios-update-dpkg-merge" "$WORK/lower/usr/lib/live/minios-update-dpkg-merge"
printf 'minios_debug_enabled() { return 1; }\n' >"$WORK/lower/usr/lib/live/config.sh"
printf 'Package: corepkg\nStatus: install ok installed\nArchitecture: amd64\nVersion: 1.0\n\n' \
    >"$WORK/lower/modules/core/var/lib/dpkg/status"
printf 'Package: removedpkg\nStatus: install ok installed\nArchitecture: amd64\nVersion: 2.0\n\n' \
    >"$WORK/lower/modules/extra/var/lib/dpkg/status"
cp "$WORK/lower/modules/core/var/lib/dpkg/status" "$WORK/lower/var/lib/dpkg/status"
mount -t overlay -o "lowerdir=$WORK/lower,upperdir=$WORK/upper,workdir=$WORK/work" \
    overlay "$WORK/merged"
mount --bind "$WORK/upper" "$WORK/merged/run/session-upper"
mount -o remount,bind,ro "$WORK/merged/run/session-upper"
chroot "$WORK/merged" /usr/bin/minios-update-dpkg /modules /run/session-upper
grep -q '^Package: removedpkg$' "$WORK/merged/var/lib/dpkg/status"
[ "$(stat -c %a "$WORK/upper/var/lib/dpkg/.minios-merge/status.base")" = 600 ]
[ "$(stat -c %a "$WORK/upper/var/lib/dpkg")" = 755 ]
chroot "$WORK/merged" /bin/bash -c '
    exec 8<>/var/lib/dpkg/lock-frontend
    printf "Package: localpkg\nStatus: install ok installed\nArchitecture: amd64\nVersion: 9.0\n\n" >>/var/lib/dpkg/status
    touch /var/lib/dpkg/info/localpkg.list
    rm /modules/extra/var/lib/dpkg/status
'
chroot "$WORK/merged" /usr/bin/minios-update-dpkg /modules /run/session-upper
grep -q '^Package: corepkg$' "$WORK/merged/var/lib/dpkg/status"
grep -q '^Package: localpkg$' "$WORK/merged/var/lib/dpkg/status"
! grep -q '^Package: removedpkg$' "$WORK/merged/var/lib/dpkg/status"
! grep -q '^Package: localpkg$' "$WORK/upper/var/lib/dpkg/.minios-merge/status.base"
printf 'PASS: merged-only writes, upper-only delta, removed modules and frontend lock\n'
