
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

@test "update to latest if update is allowed" {
    # install project as-is
    run installer.sh --yes install project1
    assert_output --partial "a279539 Initial commit"

    # add new changes
    pushd project1

    # just here
    git config --local user.email "you@example.com"
    git config --local user.name "Your Name"

    touch change.txt
    git add .
    git commit -m "Add change"
    popd

    # install again
    run installer.sh --yes install project1

    assert_output --partial "[installer] Resetting to latest revision before updating"
    assert_output --partial "a279539 Initial commit"
    [ "$status" -eq 0 ]
}

@test "do not update to latest if update is not allowed" {
    # install project as-is
    installer.sh --yes install project3

    # add new changes
    pushd project3

    # just here
    git config --local user.email "you@example.com"
    git config --local user.name "Your Name"

    touch change.txt
    git add .
    git commit -m "Add change"
    popd

    # install again
    run installer.sh --yes install project3

    assert_output --partial "[installer] Skipping reset"
    assert_output --partial "Add change"
    [ "$status" -eq 0 ]

}

@test "update to latest if update is allowed from different branch" {
    # install project as-is
    run installer.sh --yes install project4
    assert_output --partial "a279539 Initial commit"

    # add new changes
    pushd project4

    # just here
    git config --local user.email "you@example.com"
    git config --local user.name "Your Name"

    touch change.txt
    git checkout -b change
    git add .

    branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ $branch != "change" ]]; then
        false
    fi
    popd

    # install again
    run installer.sh --yes install project4

    assert_output --partial "[installer] Branch 'master' is selected"
    assert_output --partial "[installer] Resetting to latest revision before updating"
    assert_output --partial "a279539 Initial commit"
    [ "$status" -eq 0 ]

    pushd project4
    branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ $branch != "master" ]]; then
        false
    fi
    popd
}


teardown_file() {
    kill "$(< "$TEST_FILE_TMPDIR/.test-server.pid")"
}
