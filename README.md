# installer - a configuration based repository installer

![CI badge](https://github.com/bvarnai/respository-installer/actions/workflows/ci.yml/badge.svg)

**installer** is a tool to help users to work with multiple *Git* repositories from the initial clone to getting updates.

:bulb: I use the word *project* interchangeably with *repository*

**Where does it fit?**

I worked in a Java development team, we had about 15 repositories. I needed a simple tool which is

- Self-contained, no-deps
- *Git* only (minimal platform specific code)
- Configuration based
- Upgradeable
- Supports development `streams` (for example parallel tooling for java17, java21 etc.)

and **nothing** more.

I looked at existing tools such as Google's [repo](https://github.com/GerritCodeReview/git-repo), but they are much more complicated and usually mixing development workflow tasks which I wanted to keep separately.

## Table of contents

- [installer - a configuration based repository installer](#installer---a-configuration-based-repository-installer)
  - [Table of contents](#table-of-contents)
  - [Demo](#demo)
  - [Installation](#installation)
    - [Install prerequisites](#install-prerequisites)
  - [Configuration](#configuration)
    - [Workspace explained](#workspace-explained)
    - [Configuration file](#configuration-file)
  - [Usage](#usage)
    - [Command reference](#command-reference)
      - [Options](#options)
      - [Options for development/testing](#options-for-developmenttesting)
        - [Link mode](#link-mode)
        - [Stream explained](#stream-explained)
      - [help](#help)
      - [list](#list)
      - [install](#install)
      - [update](#update)
  - [FAQ](#faq)
  - [Development notes](#development-notes)

---

## Demo

![installer demo](docs/demo.gif)

---

## Installation

First, the following environment variables must be set

- `INSTALLER_SELF_URL` the URL of `installer.sh` script. By default, it should be set to *https://raw.githubusercontent.com/bvarnai/respository-installer/readme/src/installer.sh*
- `INSTALLER_CONFIG_URL` the URL of `projects.json` configuration file

:memo: You can set these variables in `~/.profile` or `~/.bashrc` to make them permanent

Next get the **installer** with `curl` for the first time

```bash
curl -o installer.sh -L $INSTALLER_SELF_URL && chmod +x installer.sh
```

Finally run **installer** in the current working directory.

```bash
./installer.sh
```
:tada: Once downloaded **installer** will upgrade itself, no need to run `curl` again.

### Install prerequisites

Following tools are required and must be installed
  - `git`
  - `curl`
  - `bash` >= 4.0.0

:warning: [jq](https://jqlang.github.io/jq/) is downloaded by **installer** to bootstrap itself and it's platform specific

Supported platforms
- Linux amd64
- Windows amd64
  - [Git for Windows](https://gitforwindows.org/) 64 bit version
    - Tested with 2.41.0+

## Configuration

### Workspace explained

Workspace is the directory where your repositories/projects are installed. **installer** runs from the workspace root and projects in the configuration
are specified *relative* to this directory.

Example layout with `installer.sh` present
```
workspace-root
  .installer
  project1
  project2
  subfolder/project3
  installer.sh
```

:memo: `.installer` directory is a "temp" directory used to store the configuration and other dependencies such as `jq`

### Configuration file

The configuration file is called `projects.json` and it's downloaded using the `INSTALLER_CONFIG_URL` environment variable. It contains information about all your projects, including setup instructions.

```json
{
  "bootstrap": "myproject",
  "projects": [
    {
      "name": "myproject",
      "category": "generic",
      "default": "true",
      "urls": {
        "fetch": "https://github.com/johndoe/myproject.git",
        "push": "git@github.com:johndoe/myproject.git"
      },
      "options": {
        "clone": "--depth 1"
      },
      "configuration": [
        "core.autocrlf false",
        "core.safecrlf false"
      ],
      "branch": "master",
      "update": "true",
      "doLast": [
        "./do_something.sh"
      ]
    }
  ]
}
```

| Elements       |                          |       | Description |
| -------------- | ------------------------ | ----  | ----------- |
| bootstrap      |                          |       | Bootstrap project is always added. For example it can be used for user-defined `doLast` scripts used during installation. Referenced by `name` in `projects`          |
| projects       |                          |       | Array of projects |
|                | name                     |       | Project name |
|                | path                     |       | Project path. Relative to workspace root. If not specified `name` will be used as path *[Optional]* |
|                | category                 |       | Project category. Informal tagging of projects. Displayed during project listing |
|                | default                  |       | Whether to install the project if no project set is specified |
|                | urls                     |       | *Git* repository URLs |
|                |                          | fetch | URL used for `fetch` |
|                |                          | push  | URL used for `push`. If not specified `fetch` URL will be used *[Optional]* |
|                | options                  |       | *Git* command options |
|                |                          | clone | Options for `clone` command. For example `--depth 1`" would result in a shallow clone *[Optional]* |
|                | configuration            |       | Array of *Git* configuration `config` options, repository scope. Add `--global` for global scope *[Optional]* |
|                | branch                   |       | Default branch |
|                | update                   |       | Whether to force update the repository. This should be set to `true` for *tooling* related projects |
|                | doLast                   |       | Array of shell commands to execute after repository update *[Optional]* |


:memo: Additional notes
- A bootstrap project is simply a project that is always installed and updated. This is where I keep all DevOps related scripts
- :warning: A bootstrap project must be set to default `default==true` as well
- Different `fetch` and `push` URLs can be used to reduce load in *Git* hosting server, for example use `https` for `fetch` and `ssh` for `push`
- Setting `update==false` means repositories are fetched but not updated. This is desirable for development projects, so working branches are felt unchanged
- :warning: Setting `update==true` means repositories are fetched, reset and updated. This helps avoid clients get into an inconsistent state

## Usage

### Command reference

Command syntax is the following:

```bash
./installer.sh [options] [<command>] [arguments]
```

Optional elements are shown in brackets []. For example, command may take a list of projects as an argument.

#### Options

- `-y, --yes` - skip user prompts
- `--link` - use symlinks to target directory
- `--branch` - overrides `branch` setting in configuration
- `--stream` - specifies the `stream` of the configuration

#### Options for development/testing

- `--skip-self-update` - skip the script update step
- `--use-local-config` - use a local configuration file


##### Link mode

In some cases, you don't want to have a fresh clone of a project to save some time. For example *Jenkins* multibanch pipeline would create a new workspace and make a fresh clone in using **installer**. This is where `link` mode can help.

Let see an example *Jenkinsfile*

```groovy
pipeline {

    environment {

        // installer configuration
        INSTALLER_SELF_URL = 'https://raw.githubusercontent.com/bvarnai/respository-installer/main/src/installer.sh'
        INSTALLER_CONFIG_URL = 'https://raw.githubusercontent.com/johndoe/myproject/main/cfg/projects.json'

        // use a directory outside of job's workspace
        SHARED_WORKSPACE = "${WORKSPACE}/../shared_workspace"
    }

    stages {
        stage('Prepare workspace') {
            steps {
                // install dependencies
                sh '''
                mkdir -p ${SHARED_WORKSPACE}

                curl -s -o installer.sh -L ${INSTALLER_SELF_URL} && chmod +x installer.sh
                ./installer.sh --yes --link ${SHARED_WORKSPACE} myproject1 myproject2
                '''
            }
        }
        stage ('Next') {
            steps {
              ...
            }
        }
    }
}
```

This will create symlinks `myproject1` and `myproject2` in the job's workspace, pointing to `../shared_workspace/myproject1` and `../shared_workspace/myproject2` directories respectively.

:warning: If you have multiple executors, parallel jobs might be running on the same shared workspace directory. This can be prevented by using the `EXECUTOR_NUMBER` variable

```groovy
SHARED_WORKSPACE = "${WORKSPACE}/../shared_workspace/${EXECUTOR_NUMBER}"
```

![Shared executor layout](docs/shared-executor.png)

##### Stream explained

da,djaldka

---
#### help

```bash
./installer.sh help
```

Displays the help.

---
#### list

```bash
./installer.sh list
```

Lists available projects.

---
#### install

```bash
./installer.sh install [project...]
```

Installs a project. This is the default command, if nothing else is specified.

Arguments:

- `project` - the list of projects to install separated by a whitespace

:memo: If you run `install` without any arguments, all projects marked `default==true` will be installed

---
#### update

```bash
./installer.sh update
```

Updates existing projects in your workspace.

---

## FAQ

## Development notes

I used Google's [Shell Style Guide](https://google.github.io/styleguide/shellguide.html) with the help of [ShellCheck](https://www.shellcheck.net/)
