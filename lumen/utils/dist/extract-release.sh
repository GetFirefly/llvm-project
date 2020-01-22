#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PACKAGES_DIR="$(cd "$SCRIPT_DIR"/../../build/packages && pwd -P)"

release=""

while [ $# -gt 0 ]; do
    case $1 in
        -release | --release )
            shift
            release="$1"
            ;;
        *)
            echo "unknown option: $1"
            exit 2
            ;;
    esac
done

if [ -z "$release" ]; then
    echo "error: no release specified"
    exit 2
fi

cd "$PACKAGES_DIR"
if ! id="$(docker create llvm-project:dist sh)"; then
    echo "Could not create dist container!"
    exit 2
fi

if ! docker cp "${id}":/opt/dist "$PACKAGES_DIR"; then
    echo "Could not copy release package!"
    exit 2
fi

if ! docker rm -f "${id}"; then
    echo "Could not clean up temp image '${id}'"
    exit 2
fi

exit 0
