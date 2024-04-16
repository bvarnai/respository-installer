
setup_file() {
    load 'test_helper/common-setup'
    _common_setup
}

setup() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'

    export INSTALLER_CONFIG_URL="${TEST_SERVER_URL}/${TEST_BASENAME}/projects.json"
    export INSTALLER_SCM_PLATFORM='static'

    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"

    mkdir -p "$TEST_FILE_TMPDIR/$TEST_BASENAME"

    # start a second server
    "$DIR/$TEST_SERVER_EXECUTABLE" --directory-listing --port 8788 --root "$TEST_FILE_TMPDIR" &
    echo $! > "$TEST_FILE_TMPDIR/.test-server-2.pid"

    # stage reference installer for testing
    cp "$DIR/../src/installer.sh" "$TEST_FILE_TMPDIR/$TEST_BASENAME/installer.sh"

    export TEST_SERVER_URL_2="http://localhost:8788"

    # change to test server
    export INSTALLER_SELF_URL="${TEST_SERVER_URL_2}/${TEST_BASENAME}/installer.sh"
}

@test "self update" {
    # set an obsolete version in the currect version
    sed -i '/INSTALLER_VERSION=/c\declare -r INSTALLER_VERSION="1.0.0"' installer.sh

    run installer.sh help

    assert_output --partial "[installer] [updater] Updatingd"
    assert_output --partial "[installer] [updater] Re-running updated script"
    [ "$status" -eq 0 ]
}

teardown() {
    kill "$(< "$TEST_FILE_TMPDIR/.test-server-2.pid")"
}

teardown_file() {
    kill "$(< "$TEST_FILE_TMPDIR/.test-server.pid")"
}