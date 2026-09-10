#!/bin/bash
# Exercise the frontend with private fake cache writers, never system caches.
set -eu
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/minios-cache-test.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT HUP INT TERM
export TEST_CACHE_OUT="$TMP/output"
mkdir -p "$TEST_CACHE_OUT"
for bundle in 03-gui.sb 04-apps.sb; do
    mkdir -p "$TMP/bundles/$bundle/usr/share/"{mime,icons/hicolor,glib-2.0/schemas,applications}
    mkdir -p "$TMP/bundles/$bundle/usr/lib/gdk-pixbuf-2.0"
done
# Redirect only the trace directory; all writers below are test functions.
source_text=$(cat "$ROOT/frontend/minios-update-cache")
printf '%s\n' "${source_text//\/var\/log\/minios/$TMP/log}" >"$TMP/frontend"
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

# pkexec may start sb with a private umask. Public caches still need mode 644.
umask 077
bash "$TMP/frontend" "$TMP/bundles"
for cache in mime pixbuf icons schemas applications; do
    [ -s "$TEST_CACHE_OUT/$cache" ] || {
        echo "Cache writer has not finished: $cache" >&2; exit 1;
    }
    [ "$(stat -c %a "$TEST_CACHE_OUT/$cache")" = 644 ] || {
        echo "Cache is not world-readable: $cache" >&2; exit 1;
    }
    [ "$(grep -cx "$cache" "$TEST_CACHE_OUT/calls")" = 1 ] || {
        echo "Cache was updated more than once: $cache" >&2; exit 1;
    }
done
printf '%s\n' 'PASS: cache writers finish once each and ignore a private caller umask'
