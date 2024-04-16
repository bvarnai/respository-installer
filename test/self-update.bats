
setup_file() {
    load 'test_helper/common-setup'
    _common_setup
}

setup() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'

    export INSTALLER_CONFIG_URL="${TEST_SERVER_URL}/${TEST_BASENAME}/projects.json"
    export INSTALLER_SELF_URL="${TEST_SERVER_URL}/${TEST_BASENAME}/installer.sh"
    export INSTALLER_SCM_PLATFORM='static'
}

@test "self update" {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    # stage this version to test
    cp installer.sh "$DIR/conf/${TEST_BASENAME}/installer.sh"

    # set an obsolete version
    sed -i '/declare -r INSTALLER_VERSION=/c\declare -r INSTALLER_VERSION="1.0.0"' installer.sh

    run installer.sh help
    assert_output --partial 'Usdge: installer.sh [options] [<command>] [arguments]'
}

teardown_file() {
    kill "$(< "$TEST_FILE_TMPDIR/.test-server.pid")"
}