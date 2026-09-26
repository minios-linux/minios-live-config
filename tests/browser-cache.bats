#!/usr/bin/env bats

setup() {
    ROOT=$(CDPATH= cd -- "$BATS_TEST_DIRNAME/.." && pwd)
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/minios-browser-test.XXXXXX")
    export WORK LIVE_USERNAME=tester
    export MINIOS_BROWSER_POLICY_FILE="$WORK/policy"
    export MINIOS_BROWSER_CACHE_ROOT="$WORK/runtime"
    export MINIOS_BROWSER_SWAPS_FILE="$WORK/swaps"
    export MINIOS_BROWSER_MEMINFO_FILE="$WORK/meminfo"
    export MINIOS_FIREFOX_POLICY_FILE="$WORK/firefox/policies.json"
    mkdir -p "$WORK/home/.cache" "$WORK/home/.mozilla/firefox/profile"
    printf 'user data\n' >"$WORK/home/.mozilla/firefox/profile/places.sqlite"
    printf 'do not touch\n' >"$WORK/home/.cache/other-program"
    printf 'volatile\n' >"$MINIOS_BROWSER_POLICY_FILE"
    printf 'Filename Type Size Used Priority\n/dev/zram0 partition 1024 0 100\n' >"$MINIOS_BROWSER_SWAPS_FILE"
    printf 'MemAvailable: 2097152 kB\n' >"$MINIOS_BROWSER_MEMINFO_FILE"
    getent() { printf 'tester:x:1000:1000::%s:/bin/sh\n' "$WORK/home"; }
    mount() { printf '%s\n' "$*" >>"$WORK/mounts"; }
    chown() { :; }
    export -f getent mount chown
}

teardown() {
    rm -rf -- "$WORK"
}

@test "only browser cache directories move to RAM; profiles and other app caches remain" {
    run bash "$ROOT/components/1240-browser-cache"
    [ "$status" -eq 0 ]
    [ "$(<"$WORK/home/.mozilla/firefox/profile/places.sqlite")" = 'user data' ]
    [ "$(<"$WORK/home/.cache/other-program")" = 'do not touch' ]
    [ -f "$MINIOS_FIREFOX_POLICY_FILE" ]
    grep -Fq -- "--bind $WORK/runtime/1000/chromium $WORK/home/.cache/chromium" "$WORK/mounts"
    grep -Fq -- "--bind $WORK/runtime/1000/BraveSoftware $WORK/home/.cache/BraveSoftware" "$WORK/mounts"
    grep -Fq -- "--bind $WORK/runtime/1000/yandex-browser $WORK/home/.cache/yandex-browser" "$WORK/mounts"
}

@test "switching back removes only the owned Firefox policy" {
    run bash "$ROOT/components/1240-browser-cache"
    [ "$status" -eq 0 ]
    [ -e "${MINIOS_FIREFOX_POLICY_FILE}.minios-managed" ]
    printf 'persistent\n' >"$MINIOS_BROWSER_POLICY_FILE"
    run bash "$ROOT/components/1240-browser-cache"
    [ "$status" -eq 0 ]
    [ ! -e "$MINIOS_FIREFOX_POLICY_FILE" ]
    [ ! -e "${MINIOS_FIREFOX_POLICY_FILE}.minios-managed" ]
}

@test "an administrator Firefox policy is neither replaced nor removed" {
    mkdir -p "${MINIOS_FIREFOX_POLICY_FILE%/*}"
    printf '{"policies":{"Homepage":{"URL":"https://example.org"}}}\n' >"$MINIOS_FIREFOX_POLICY_FILE"
    run bash "$ROOT/components/1240-browser-cache"
    [ "$status" -eq 0 ]
    grep -Fq 'https://example.org' "$MINIOS_FIREFOX_POLICY_FILE"
    printf 'persistent\n' >"$MINIOS_BROWSER_POLICY_FILE"
    run bash "$ROOT/components/1240-browser-cache"
    [ "$status" -eq 0 ]
    grep -Fq 'https://example.org' "$MINIOS_FIREFOX_POLICY_FILE"
}

@test "disk-backed swap prevents redirecting a RAM cache onto the same device" {
    printf 'Filename Type Size Used Priority\n/dev/sda2 partition 2048 0 -2\n' >"$MINIOS_BROWSER_SWAPS_FILE"
    run bash "$ROOT/components/1240-browser-cache"
    [ "$status" -eq 0 ]
    [[ "$output" == *'non-zRAM swap'* ]]
    [ ! -e "$WORK/mounts" ]
    [ ! -e "$MINIOS_FIREFOX_POLICY_FILE" ]
}
