#!/usr/bin/env bats

setup() {
    ROOT=$(CDPATH= cd -- "$BATS_TEST_DIRNAME/.." && pwd)
    MERGER=$ROOT/scripts/minios-update-dpkg-merge
    FRONTEND=$ROOT/frontend/minios-update-dpkg
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/minios-dpkg-merge-test.XXXXXX")
    mkdir -p "$WORK/info"
    : >"$WORK/empty"
    cat >"$WORK/base.status" <<'STATUS'
Package: corepkg
Status: install ok installed
Architecture: amd64
Version: 1.0

Package: shared
Status: install ok installed
Architecture: amd64
Version: 1.0

STATUS
    cat >"$WORK/extra.status" <<'STATUS'
Package: shared
Status: install ok installed
Architecture: amd64
Version: 2.0

Package: vlc-bin
Status: install ok installed
Architecture: amd64
Version: 3.0

STATUS
    cat "$WORK/base.status" "$WORK/extra.status" >"$WORK/modules-old"
}

teardown() {
    rm -rf -- "$WORK"
}

@test "frontend and merger reject missing or malformed input before publishing" {
    run "$FRONTEND" --help
    [ "$status" -eq 0 ]
    run "$FRONTEND" "$WORK/missing-bundles"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Bundles directory not found:'* ]]

    cat >"$WORK/malformed-current.status" <<'STATUS'
Status: install ok installed
Architecture: amd64
Version: 1.0

STATUS
    run "$MERGER" "$WORK/modules-old" "$WORK/malformed-current.status" \
        "$WORK/empty" "$WORK/info" "$WORK/rejected-current-base" \
        "$WORK/rejected-current-final"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Malformed status paragraph 1 in $WORK/malformed-current.status: missing or empty Package field"* ]]
    [ ! -e "$WORK/rejected-current-base" ]
    [ ! -e "$WORK/rejected-current-final" ]

    cat >"$WORK/malformed-module.status" <<'STATUS'
Package: broken-module-package
Status: install ok installed
Architecture: amd64

STATUS
    run "$MERGER" "$WORK/malformed-module.status" "$WORK/empty" \
        "$WORK/empty" "$WORK/info" "$WORK/rejected-module-base" \
        "$WORK/rejected-module-final"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Malformed status paragraph 1 in $WORK/malformed-module.status: missing or empty Version field"* ]]
    [ ! -e "$WORK/rejected-module-base" ]
    [ ! -e "$WORK/rejected-module-final" ]
}

prepare_removed_modules() {
    "$MERGER" "$WORK/modules-old" "$WORK/empty" "$WORK/empty" \
        "$WORK/info" "$WORK/base-old" "$WORK/final-old"
    "$MERGER" "$WORK/base.status" "$WORK/final-old" "$WORK/base-old" \
        "$WORK/info" "$WORK/base-new" "$WORK/final-new"
}

@test "removed modules disappear and shared package versions roll back" {
    prepare_removed_modules
    grep -q '^Package: vlc-bin$' "$WORK/final-old"
    grep -A3 '^Package: shared$' "$WORK/final-old" | grep -q 'Version: 2.0'
    ! grep -q '^Package: vlc-bin$' "$WORK/final-new"
    grep -A3 '^Package: shared$' "$WORK/final-new" | grep -q 'Version: 1.0'
}

@test "writable installs survive later refresh; stale synthetic packages do not" {
    prepare_removed_modules
    cp "$WORK/final-new" "$WORK/current-local"
    cat >>"$WORK/current-local" <<'STATUS'
Package: localpkg
Status: install ok installed
Architecture: amd64
Version: 9.0

STATUS
    touch "$WORK/info/localpkg.list"
    "$MERGER" "$WORK/base.status" "$WORK/current-local" "$WORK/base-new" \
        "$WORK/info" "$WORK/base-next" "$WORK/final-local"
    grep -q '^Package: localpkg$' "$WORK/final-local"
    rm -f "$WORK/info/localpkg.list"
    "$MERGER" "$WORK/base.status" "$WORK/current-local" "$WORK/base-new" \
        "$WORK/info" "$WORK/base-stale" "$WORK/final-stale"
    ! grep -q '^Package: localpkg$' "$WORK/final-stale"

    sed '0,/Status: install ok installed/s//Status: hold ok installed/' \
        "$WORK/base.status" >"$WORK/current-baseline-hold"
    "$MERGER" "$WORK/base.status" "$WORK/current-baseline-hold" \
        "$WORK/base-new" "$WORK/info" "$WORK/base-baseline-hold" \
        "$WORK/final-baseline-hold"
    grep -A2 '^Package: corepkg$' "$WORK/final-baseline-hold" | grep -q 'Status: hold ok installed'
}

@test "migration removes self-fed module entries but preserves genuine local state" {
    "$MERGER" "$WORK/modules-old" "$WORK/empty" "$WORK/empty" \
        "$WORK/info" "$WORK/base-old" "$WORK/final-old"
    "$MERGER" "$WORK/base.status" "$WORK/final-old" "$WORK/empty" \
        "$WORK/info" "$WORK/base-migrate" "$WORK/final-migrate"
    ! grep -q '^Package: vlc-bin$' "$WORK/final-migrate"
    grep -A3 '^Package: shared$' "$WORK/final-migrate" | grep -q 'Version: 1.0'

    touch "$WORK/info/localpkg.list"
    cp "$WORK/final-old" "$WORK/current-migrate-local"
    cat >>"$WORK/current-migrate-local" <<'STATUS'
Package: localpkg
Status: install ok installed
Architecture: amd64
Version: 9.0

STATUS
    "$MERGER" "$WORK/base.status" "$WORK/current-migrate-local" \
        "$WORK/empty" "$WORK/info" "$WORK/base-migrate2" "$WORK/final-migrate2"
    grep -q '^Package: localpkg$' "$WORK/final-migrate2"
    ! grep -q '^Package: vlc-bin$' "$WORK/final-migrate2"

    rm -f "$WORK/info/localpkg.list"
    sed '0,/Status: install ok installed/s//Status: hold ok installed/' \
        "$WORK/base.status" >"$WORK/current-hold"
    "$MERGER" "$WORK/base.status" "$WORK/current-hold" "$WORK/empty" \
        "$WORK/info" "$WORK/base-hold" "$WORK/final-hold"
    grep -A2 '^Package: corepkg$' "$WORK/final-hold" | grep -q 'Status: hold ok installed'
}
