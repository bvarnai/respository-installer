
setup_file() {
    load 'test_helper/common-setup'
    _common_setup
}

setup() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'

    export INSTALLER_CONFIG_URL="${TEST_SERVER_URL}/${TEST_BASENAME}/#branch#/projects.json"
    export INSTALLER_CONFIG_SCM='plain'

    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"

    mkdir -p "$TEST_FILE_TMPDIR/$TEST_BASENAME/main"

    # start a second server
    "$DIR/$TEST_SERVER_EXECUTABLE" --directory-listing --port 8788 --root "$TEST_FILE_TMPDIR" &
    echo $! > "$TEST_FILE_TMPDIR/.test-server-2.pid"

    # stage reference installer for testing
    cp "$DIR/../src/installer.sh" "$TEST_FILE_TMPDIR/$TEST_BASENAME/main/installer.sh"

    export TEST_SERVER_URL_2="http://localhost:8788"

    # change to test server
    export INSTALLER_SELF_URL="${TEST_SERVER_URL_2}/${TEST_BASENAME}/#branch#/installer.sh"

    # this is need to verify if the actual update failed
    export INSTALLER_GET_SELF_STRICT=true
}

@test "update to higher version" {
    # set a lower version, expecting to update
    sed -i '/INSTALLER_VERSION=/c\INSTALLER_VERSION="1.0.0"' installer.sh

    run installer.sh help

    assert_output --partial "[installer] [updater] Updating"
    assert_output --partial "[installer] [updater] Updating 1.0.0 ->"
    assert_output --partial "[installer] [updater] Re-running updated script"
    [ "$status" -eq 0 ]
}

@test "no update when same versions" {
    run installer.sh help

    assert_output --partial "[installer] [updater] Checking for updates"
    assert_output --partial "[installer] [updater] No update available"
    [ "$status" -eq 0 ]
}

@test "no update to lower versions" {
    # set a higher version, no update is expected
    sed -i '/INSTALLER_VERSION=/c\INSTALLER_VERSION="9.9.9"' installer.sh

    run installer.sh help

    assert_output --partial "[installer] [updater] Checking for updates"
    assert_output --partial "[installer] [updater] No update available"
    [ "$status" -eq 0 ]
}

@test "no update if skipped" {
    # set a lower version, expecting to update, but skipped
    sed -i '/INSTALLER_VERSION=/c\INSTALLER_VERSION="9.9.9"' installer.sh

    run installer.sh --skip-self-update help

    refute_output --partial "[installer] [updater] Checking for updates"
    [ "$status" -eq 0 ]
}

@test "bad update url" {
    # set a lower version, expecting to update
    sed -i '/INSTALLER_VERSION=/c\INSTALLER_VERSION="1.0.0"' installer.sh

    export INSTALLER_SELF_URL="http://xyz/installer.sh"

    run installer.sh help

    refute_output --partial "[installer] [updater] Updating"
    [ "$status" -eq 1 ]
}

teardown() {
    kill "$(< "$TEST_FILE_TMPDIR/.test-server-2.pid")"
}

teardown_file() {
    kill "$(< "$TEST_FILE_TMPDIR/.test-server.pid")"
}
