#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
DIST_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$DIST_DIR")"

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

cd "$DIST_DIR"
if ! id="$(docker create llvm-project:dist sh)"; then
    echo "Could not create dist container!"
    exit 2
fi

if ! docker cp "${id}":/opt/dist "$DIST_DIR/packages"; then
    echo "Could not copy release package!"
    exit 2
fi

if ! docker rm -f "${id}"; then
    echo "Could not clean up temp image '${id}'"
    exit 2
fi

exit 0
