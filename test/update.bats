
setup_file() {
    load 'test_helper/common-setup'
    _common_setup
}

setup() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'

    export INSTALLER_CONFIG_URL="${TEST_SERVER_URL}/${TEST_BASENAME}/#branch#/projects.json"
    export INSTALLER_SELF_URL="${TEST_SERVER_URL}/${TEST_BASENAME}/installer.sh"
    export INSTALLER_CONFIG_SCM='plain'
}

@test "update projects in workspace" {

    installer.sh --yes install

    # install again
    run installer.sh --yes update

    assert_output --partial "[installer] Searching for existing projects in the current directory (workspace)"
    assert_output --partial "a279539 Initial commit"
    [ "$status" -eq 0 ]
}

teardown_file() {
    kill "$(< "$TEST_FILE_TMPDIR/.test-server.pid")"
}
