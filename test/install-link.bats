
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

@test "install with link" {

    mkdir shared

    run installer.sh --yes --link shared install project1
    assert_output --partial "a279539 Initial commit"
    [ "$status" -eq 0 ]

    # check if symlink is created
    if [[ -L "project1" && -d "project1" ]]; then
        true
    else
        false
    fi
}

teardown_file() {
    kill "$(< "$TEST_FILE_TMPDIR/.test-server.pid")"
}
