#!/bin/sh
# shellcheck disable=SC2034 # Variables are consumed by the sourced component.

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT HUP INT TERM

# Load the component functions without its live-config dependency or entrypoint.
sed \
    -e '\|^\. /usr/lib/live/config.sh$|d' \
    -e '/^Cmdline$/,$d' \
    "${ROOT}/components/0045-user-media" >"${WORK}/component"
. "${WORK}/component"

PERSISTENCE_STATE_FILE=${WORK}/boot-state
CRYPT_MAPPER_DIR=${WORK}/mapper
mkdir -p "${CRYPT_MAPPER_DIR}"

LIVE_CONFIG_CMDLINE='boot=live perchencrypt=luks'
Cmdline
if session_is_encrypted; then
    echo "A kernel encryption request without runtime activation was detected as active." >&2
    exit 1
fi

printf '%s\n' 'boot_level=failed' 'encryption=luks' >"${PERSISTENCE_STATE_FILE}"
if session_is_encrypted; then
    echo "Failed encryption activation was detected as active." >&2
    exit 1
fi

printf '%s\n' 'boot_level=ok' 'encryption=none' >"${PERSISTENCE_STATE_FILE}"
if session_is_encrypted; then
    echo "Unsupported encryption was detected as active." >&2
    exit 1
fi

LIVE_CONFIG_CMDLINE='boot=live'
Cmdline
printf '%s\n' 'boot_level=ok' 'encryption=luks' >"${PERSISTENCE_STATE_FILE}"
session_is_encrypted

check_rejected() {
    expected=$1
    link=$2
    state=$3
    case_dir=${WORK}/case-${link}-${state}
    mkdir -p "${case_dir}"
    if [ "${state}" = present ]; then
        printf '%s\n' 'mode=link' >"${case_dir}/user-media.state"
    fi
    output=$(
        STATE_DIR=${case_dir}
        STATE_FILE=${case_dir}/user-media.state
        STATUS_FILE=${case_dir}/user-media.status
        LIVE_LINK_USER_DIRS=${link}
        LIVE_BIND_USER_DIRS=false
        TORAM=false
        Config
    )
    printf '%s\n' "${output}" | grep -Fqx "user-media: ${expected}"
    grep -Fqx "failed: ${expected}" "${case_dir}/user-media.status"
}

check_rejected 'user directories are unavailable with encrypted sessions' true absent
check_rejected 'user directories cannot be copied back while an encrypted session is active' false present
