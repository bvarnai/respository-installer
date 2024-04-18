
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


@test "list projects from default stream" {

    run installer.sh list

    assert_output --partial "Stream branch 'default' is selected"
    assert_output --partial 'Available projects:'
    assert_output --partial 'project1'
    assert_output --partial 'project2'
    assert_output --partial 'project3'
    assert_output --partial 'category: test category'
    assert_output --partial 'path: sub/project3'
}

@test "list projects from non default stream" {

    run installer.sh --stream feature1 list

    assert_output --partial "Stream branch 'feature1' is selected"
    assert_output --partial 'Available projects:'
    assert_output --partial 'project11'
    assert_output --partial 'category: non default stream'
}

teardown_file() {
    kill "$(< "$TEST_FILE_TMPDIR/.test-server.pid")"
}
