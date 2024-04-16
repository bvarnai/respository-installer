#!/usr/bin/env bash

_common_setup() {
    if [[ $(uname -s) == "Linux" ]]; then
        SERVER_EXECUTABLE=static-web-server
    else
        SERVER_EXECUTABLE=static-web-server.exe
    fi

    # get the containing directory of this file
    # use $BATS_TEST_FILENAME instead of ${BASH_SOURCE[0]} or $0,
    # as those will point to the bats executable's location or the preprocessed file respectively
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"

    TEST_FILE_TMPDIR="$BATS_FILE_TMPDIR"

    # redirect on GitHub
    if [[ -n "$GITHUB_WORKSPACE" ]]; then
        export TEST_FILE_TMPDIR="$GITHUB_WORKSPACE/../tmp"
        mkdir -p "$TEST_FILE_TMPDIR"
    fi

    export TEST_FILE_TMPDIR

    # start configuration server
    static-web-server/$SERVER_EXECUTABLE --directory-listing --port 8787 --root ./conf &
    echo $! > "$TEST_FILE_TMPDIR/.test-server.pid"

    # change working directory to staging
    cd "$TEST_FILE_TMPDIR" || exit

    # stage installer to tmp (so we run on a copy!)
    cp "$DIR/../src/installer.sh" installer.sh

    # make executables visible to PATH
    PATH="$TEST_FILE_TMPDIR:$PATH"

    # helper to get the test name directory
    TEST_BASENAME="$( basename "$BATS_TEST_FILENAME" )"
    export TEST_BASENAME

    export TEST_SERVER_URL="http://localhost:8787"
}