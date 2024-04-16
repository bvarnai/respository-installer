
setup_file() {
    load 'test_helper/common-setup'
    _common_setup
}

setup() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'

    export INSTALLER_CONFIG_URL="${TEST_SERVER_URL}/${BATS_TEST_BASENAME}"
    export INSTALLER_SCM_PLATFORM='static'
}

@test "display help" {
    run installer.sh help
    assert_output --partial 'Usage: installer.sh [options] [<command>] [arguments]'
}

teardown_file() {
    kill "$(< "$GITHUB_WORKSPACE/../tmp/.test-server.pid")"
}