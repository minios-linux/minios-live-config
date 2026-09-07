#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MERGER="$ROOT/scripts/minios-update-dpkg-merge"
FRONTEND="$ROOT/frontend/minios-update-dpkg"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/minios-dpkg-merge-test.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/info"
: >"$TMP/empty"

# Invalid invocations must stop before the frontend can touch the dpkg database.
"$FRONTEND" --help >/dev/null
if "$FRONTEND" "$TMP/missing-bundles" 2>"$TMP/frontend-error"; then
    echo "frontend accepted a missing bundles directory" >&2
    exit 1
fi
grep -q '^Bundles directory not found:' "$TMP/frontend-error"

cat >"$TMP/base.status" <<'STATUS'
Package: corepkg
Status: install ok installed
Architecture: amd64
Version: 1.0

Package: shared
Status: install ok installed
Architecture: amd64
Version: 1.0

STATUS
cat >"$TMP/extra.status" <<'STATUS'
Package: shared
Status: install ok installed
Architecture: amd64
Version: 2.0

Package: vlc-bin
Status: install ok installed
Architecture: amd64
Version: 3.0

STATUS
cat "$TMP/base.status" "$TMP/extra.status" >"$TMP/modules-old"

# Malformed writable status must fail before producing either output.
cat >"$TMP/malformed-current.status" <<'STATUS'
Status: install ok installed
Architecture: amd64
Version: 1.0

STATUS
if "$MERGER" "$TMP/modules-old" "$TMP/malformed-current.status" "$TMP/empty" \
    "$TMP/info" "$TMP/rejected-current-base" "$TMP/rejected-current-final" \
    2>"$TMP/malformed-current-error"; then
    echo "merger accepted current status without Package" >&2
    exit 1
fi
grep -Fq "Malformed status paragraph 1 in $TMP/malformed-current.status: missing or empty Package field" \
    "$TMP/malformed-current-error"
[ ! -e "$TMP/rejected-current-base" ]
[ ! -e "$TMP/rejected-current-final" ]

# Every mounted-module paragraph must include both Package and Version.
cat >"$TMP/malformed-module.status" <<'STATUS'
Package: broken-module-package
Status: install ok installed
Architecture: amd64

STATUS
if "$MERGER" "$TMP/malformed-module.status" "$TMP/empty" "$TMP/empty" \
    "$TMP/info" "$TMP/rejected-module-base" "$TMP/rejected-module-final" \
    2>"$TMP/malformed-module-error"; then
    echo "merger accepted module status without Version" >&2
    exit 1
fi
grep -Fq "Malformed status paragraph 1 in $TMP/malformed-module.status: missing or empty Version field" \
    "$TMP/malformed-module-error"
[ ! -e "$TMP/rejected-module-base" ]
[ ! -e "$TMP/rejected-module-final" ]

# Initial synthesis records the mounted-module baseline.
"$MERGER" "$TMP/modules-old" "$TMP/empty" "$TMP/empty" "$TMP/info" \
    "$TMP/base-old" "$TMP/final-old"
grep -q '^Package: vlc-bin$' "$TMP/final-old"
grep -A3 '^Package: shared$' "$TMP/final-old" | grep -q 'Version: 2.0'

# Removing the module must remove its packages and roll shared packages back.
"$MERGER" "$TMP/base.status" "$TMP/final-old" "$TMP/base-old" "$TMP/info" \
    "$TMP/base-new" "$TMP/final-new"
! grep -q '^Package: vlc-bin$' "$TMP/final-new"
grep -A3 '^Package: shared$' "$TMP/final-new" | grep -q 'Version: 1.0'

# A package installed in the writable session remains across later rebuilds.
cp "$TMP/final-new" "$TMP/current-local"
cat >>"$TMP/current-local" <<'STATUS'
Package: localpkg
Status: install ok installed
Architecture: amd64
Version: 9.0

STATUS
touch "$TMP/info/localpkg.list"
"$MERGER" "$TMP/base.status" "$TMP/current-local" "$TMP/base-new" "$TMP/info" \
    "$TMP/base-next" "$TMP/final-local"
grep -q '^Package: localpkg$' "$TMP/final-local"

# A synthesized package without writable metadata is not a local install.
rm -f "$TMP/info/localpkg.list"
"$MERGER" "$TMP/base.status" "$TMP/current-local" "$TMP/base-new" "$TMP/info" \
    "$TMP/base-stale" "$TMP/final-stale"
! grep -q '^Package: localpkg$' "$TMP/final-stale"

# Same-version package state changes do not require writable info files.
sed '0,/Status: install ok installed/s//Status: hold ok installed/' \
    "$TMP/base.status" >"$TMP/current-baseline-hold"
"$MERGER" "$TMP/base.status" "$TMP/current-baseline-hold" "$TMP/base-new" "$TMP/info" \
    "$TMP/base-baseline-hold" "$TMP/final-baseline-hold"
grep -A2 '^Package: corepkg$' "$TMP/final-baseline-hold" | grep -q 'Status: hold ok installed'

# Migration cleans databases polluted by older self-feeding merge behavior.
"$MERGER" "$TMP/base.status" "$TMP/final-old" "$TMP/empty" "$TMP/info" \
    "$TMP/base-migrate" "$TMP/final-migrate"
! grep -q '^Package: vlc-bin$' "$TMP/final-migrate"
grep -A3 '^Package: shared$' "$TMP/final-migrate" | grep -q 'Version: 1.0'

# Migration still preserves real local package metadata and same-version state changes.
touch "$TMP/info/localpkg.list"
cp "$TMP/final-old" "$TMP/current-migrate-local"
cat >>"$TMP/current-migrate-local" <<'STATUS'
Package: localpkg
Status: install ok installed
Architecture: amd64
Version: 9.0

STATUS
"$MERGER" "$TMP/base.status" "$TMP/current-migrate-local" "$TMP/empty" "$TMP/info" \
    "$TMP/base-migrate2" "$TMP/final-migrate2"
grep -q '^Package: localpkg$' "$TMP/final-migrate2"
! grep -q '^Package: vlc-bin$' "$TMP/final-migrate2"

rm -f "$TMP/info/localpkg.list"
sed '0,/Status: install ok installed/s//Status: hold ok installed/' \
    "$TMP/base.status" >"$TMP/current-hold"
"$MERGER" "$TMP/base.status" "$TMP/current-hold" "$TMP/empty" "$TMP/info" \
    "$TMP/base-hold" "$TMP/final-hold"
grep -A2 '^Package: corepkg$' "$TMP/final-hold" | grep -q 'Status: hold ok installed'

echo "minios-update-dpkg merge tests: OK"
