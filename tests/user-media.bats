#!/usr/bin/env bats

setup() {
    ROOT=$(CDPATH='' cd -- "$BATS_TEST_DIRNAME/.." && pwd)
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/minios-user-media-test.XXXXXX")
    # Load the component's functions without its installed config.sh or its
    # entrypoint. Runtime state is a private fixture, never the host's state.
    sed -e '\|^\. /usr/lib/live/config.sh$|d' -e '/^Cmdline$/,$d' \
        "$ROOT/components/0045-user-media" >"$WORK/component"
    . "$WORK/component"
    # The component sets nounset; Bats 0.4 itself reads unset bookkeeping
    # variables after each test. Keep its functions, not its shell flags.
    set +u
    PERSISTENCE_STATE_FILE=$WORK/boot-state
    CRYPT_MAPPER_DIR=$WORK/mapper
    mkdir -p "$CRYPT_MAPPER_DIR"
}

teardown() {
    rm -rf -- "$WORK"
}

@test "an encryption request or failed activation is not mistaken for active encryption" {
    LIVE_CONFIG_CMDLINE='boot=live perchencrypt=luks'
    Cmdline
    run session_is_encrypted
    [ "$status" -ne 0 ]

    printf '%s\n' 'boot_level=failed' 'encryption=luks' >"$PERSISTENCE_STATE_FILE"
    run session_is_encrypted
    [ "$status" -ne 0 ]

    printf '%s\n' 'boot_level=ok' 'encryption=none' >"$PERSISTENCE_STATE_FILE"
    run session_is_encrypted
    [ "$status" -ne 0 ]
}

check_rejected() {
    expected=$1
    link=$2
    state=$3
    case_dir=$WORK/case-$link-$state
    mkdir -p "$case_dir"
    if [ "$state" = present ]; then
        printf '%s\n' 'mode=link' >"$case_dir/user-media.state"
    fi
    output=$(
        STATE_DIR=$case_dir
        STATE_FILE=$case_dir/user-media.state
        STATUS_FILE=$case_dir/user-media.status
        LIVE_LINK_USER_DIRS=$link
        LIVE_BIND_USER_DIRS=false
        TORAM=false
        Config
    )
    printf '%s\n' "$output" | grep -Fqx "user-media: $expected"
    grep -Fqx "failed: $expected" "$case_dir/user-media.status"
}

@test "actual encrypted persistence prevents linking and copying user directories" {
    LIVE_CONFIG_CMDLINE='boot=live'
    Cmdline
    printf '%s\n' 'boot_level=ok' 'encryption=luks' >"$PERSISTENCE_STATE_FILE"
    run session_is_encrypted
    [ "$status" -eq 0 ]
    run check_rejected 'user directories are unavailable with encrypted sessions' true absent
    [ "$status" -eq 0 ]
    run check_rejected 'user directories cannot be copied back while an encrypted session is active' false present
    [ "$status" -eq 0 ]
}
