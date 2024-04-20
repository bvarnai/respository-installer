
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

@test "install project (including bootstrap)" {
    run installer.sh --yes install project2

    assert_output --partial "[installer] Now at commit"
    # check if bootstrap is added
    assert_output --partial "[installer] Adding bootstrap project 'project3' implicitly"
    [ "$status" -eq 0 ]
}

@test "install default project" {
    run installer.sh --yes --prune install

    assert_output --partial "[installer] Now at commit"
    [ "$status" -eq 0 ]
}

@test "install project, but unable to clone due to missing branch on origin" {
    run installer.sh --yes install project1

    assert_output --partial "[installer] ! Unable to clone repository"
    [ "$status" -eq 1 ]
}

@test "install project with doLast" {
    run installer.sh --yes install project4

    assert_output --partial "project4 running doLast"
    [ "$status" -eq 0 ]
}

@test "install project with doLast error" {
    run installer.sh --yes install project6

    assert_output --partial "project6 running doLast"
    [ "$status" -eq 1 ]
}

@test "install projects with sorting" {
    run installer.sh --yes install project5 project4

    assert_output --partial "[installer] Sorting projects based on configuration index"
    # project5 doLast should run after project4
    assert_line --index 41 "project4 running doLast"
    assert_line --index 60 "project5 running doLast"
    [ "$status" -eq 0 ]
}

@test "install existing project" {
    # this test has dependency on previous test case
    run installer.sh --yes --fetch-all install project2

    assert_output --partial "[installer] Existing repository found, updating"
    assert_output --partial "[installer] Now at commit"
    # check if bootstrap is added
    assert_output --partial "[installer] Adding bootstrap project 'project3' implicitly"
    [ "$status" -eq 0 ]
}

@test "intall project with quite git" {
    # this test has dependency on previous test case
    run installer.sh --yes --git-quiet install project7

    refute_output --partial "HEAD is now at"
    [ "$status" -eq 0 ]
}

@test "install project with doLast skipped" {
    run installer.sh --yes --skip-dolast install project8

    assert_output --partial "Skipping doLast commands"
    [ "$status" -eq 0 ]
}


teardown_file() {
    kill "$(< "$TEST_FILE_TMPDIR/.test-server.pid")"
}
