
setup_file() {
    load 'test_helper/common-setup'
    _common_setup
}

setup() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'

    export INSTALLER_CONFIG_URL="${TEST_SERVER_URL}/${TEST_BASENAME}/projects.json"
    export INSTALLER_SELF_URL="${TEST_SERVER_URL}/${TEST_BASENAME}/installer.sh"
    export INSTALLER_CONFIG_SCM='static'

    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"

    mkdir -p "$TEST_FILE_TMPDIR/$TEST_BASENAME"

    # stage reference installer for testing
    cp "$DIR/conf/$TEST_BASENAME/projects.json" "$TEST_FILE_TMPDIR/projects.json"
}

@test "use local configuration" {
    run installer.sh --use-local-config list

    assert_output --partial "Using local configuration"
    [ "$status" -eq 0 ]
}

@test "use local configuration, but not found" {
    rm projects.json

    run installer.sh --use-local-config list

    assert_output --partial "No local configuration found"
    [ "$status" -eq 1 ]
}


teardown_file() {
    kill "$(< "$TEST_FILE_TMPDIR/.test-server.pid")"
}
