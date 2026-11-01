#!/bin/sh
set -eu

prepare_directory() {
    directory=$1
    owner=$2

    if [ ! -d "$directory" ] || [ -L "$directory" ]; then
        printf 'Invalid data directory: %s\n' "$directory" >&2
        exit 1
    fi

    # Change only the mount root; preserve existing files and subdirectories.
    chown "$owner" "$directory"
    chmod u+rwx "$directory"
    printf 'Prepared data directory: %s\n' "$directory"
}

prepare_directory /prometheus 65534:65534
prepare_directory /var/lib/grafana 472:0

if [ "${INIT_LOG_STORAGE:-false}" = "true" ]; then
    prepare_directory /loki 10001:0
    prepare_directory /var/lib/alloy/data 0:0
fi
