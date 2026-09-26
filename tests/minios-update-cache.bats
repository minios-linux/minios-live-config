#!/usr/bin/env bats

setup() {
    ROOT=$(CDPATH= cd -- "$BATS_TEST_DIRNAME/.." && pwd)
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/minios-cache-test.XXXXXX")
    export TEST_CACHE_OUT="$WORK/output"
    export MINIOS_DEBUG_CMDLINE_FILE="$WORK/cmdline"
    : >"$MINIOS_DEBUG_CMDLINE_FILE"
    mkdir -p "$TEST_CACHE_OUT"
    for bundle in 03-gui.sb 04-apps.sb; do
        mkdir -p "$WORK/bundles/$bundle/usr/share/"{mime,icons/hicolor,glib-2.0/schemas,applications}
        mkdir -p "$WORK/bundles/$bundle/usr/lib/gdk-pixbuf-2.0"
    done
    # Replace only the installed library and trace paths. Cache commands are
    # exported test doubles, so nothing can update host-wide caches.
    source_text=$(<"$ROOT/frontend/minios-update-cache")
    source_text=${source_text//\/usr\/lib\/live\/config.sh/$ROOT\/frontend\/config.sh}
    printf '%s\n' "${source_text//\/var\/log\/minios/$WORK/log}" >"$WORK/frontend"
    id() { printf '0\n'; }
    ldconfig() { :; }
    touch() { :; }
    write_cache() {
        printf '%s\n' "$1" >>"$TEST_CACHE_OUT/calls"
        sleep 0.1
        printf '%s\n' complete >"$TEST_CACHE_OUT/$1"
    }
    update-mime-database() { write_cache mime; }
    gdk-pixbuf-query-loaders() { write_cache pixbuf; }
    gtk-update-icon-cache() { write_cache icons; }
    glib-compile-schemas() { write_cache schemas; }
    update-desktop-database() { write_cache applications; }
    export -f id ldconfig touch write_cache update-mime-database
    export -f gdk-pixbuf-query-loaders gtk-update-icon-cache glib-compile-schemas
    export -f update-desktop-database
}

teardown() {
    rm -rf -- "$WORK"
}

@test "cache writers finish once and publish world-readable results despite a private umask" {
    umask 077
    run env LIVE_CONFIG_DEBUG=false bash "$WORK/frontend" "$WORK/bundles"
    [ "$status" -eq 0 ]
    [ ! -e "$WORK/log/minios-update-cache.trace.log" ]
    for cache in mime pixbuf icons schemas applications; do
        [ -s "$TEST_CACHE_OUT/$cache" ]
        [ "$(stat -c %a "$TEST_CACHE_OUT/$cache")" = 644 ]
        [ "$(grep -cx "$cache" "$TEST_CACHE_OUT/calls")" -eq 1 ]
    done
}

@test "debug capture writes a private trace only when enabled" {
    run env LIVE_CONFIG_DEBUG=true bash "$WORK/frontend" "$WORK/bundles"
    [ "$status" -eq 0 ]
    [ -s "$WORK/log/minios-update-cache.trace.log" ]
    [ "$(stat -c %a "$WORK/log/minios-update-cache.trace.log")" = 600 ]
}
