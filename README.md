# installer - a configuration based repository installer

**drs** is a small set of shell scripts that allows you to store directory revisions (snapshots if you like) remotely. Revision metadata is stored in a *Git* repository while the directory contents are stored on a remote host using *SSH* and *rsync*. Metadata repository can be kept small since it's completely independent of the directory contents.

It's really easy to setup, depends on only standard tools and easy to extend.

**Where does it fit?**

I needed to store large builds (>5GB) and distribute them efficiently to testers. The actual differences between builds were quite small, a few changed jars along with 100s of other jars that rarely changing. In such case, rsync does a spectacular jobs to speed things up. *Git* is great to keep track of everything else, branches, build information etc.

**Relation to Git**

**drs** uses *Git* as a minimalistic database. Commands like `drs-put`, `drs-get` are integrated as *Git* aliases and organized around producer/customer concept. Producer is usually a build job on CI, the consumer can be a human tester or a regression test job for example. Most workflow tasks (except `git init, tag`) are covered with `drs` commands, therefore users don't have to know *Git* much. For more details see [Differences to *Git*](#differences-to-*Git*)

## Table of contents

- [installer - a configuration based repository installer](#installer---a-configuration-based-repository-installer)
  - [Table of contents](#table-of-contents)
  - [Demo](#demo)
  - [Installation](#installation)
    - [Using sources](#using-sources)
    - [Using releases](#using-releases)
    - [Install prerequisites](#install-prerequisites)
      - [Install *client* prerequisites on Ubuntu](#install-client-prerequisites-on-ubuntu)
      - [Install *client* prerequisites on Git for Windows (Git-Bash/MinGW/MSYS2)](#install-client-prerequisites-on-git-for-windows-git-bashmingwmsys2)
      - [Final *client* check](#final-client-check)
      - [Install *server* prerequisites](#install-server-prerequisites)
  - [Configuration](#configuration)
    - [SSH configuration](#ssh-configuration)
      - [SSH client setup](#ssh-client-setup)
      - [SSH server setup](#ssh-server-setup)
      - [How to set up SSH keys](#how-to-set-up-ssh-keys)
    - [Metadata repository setup](#metadata-repository-setup)
    - [Configuration file](#configuration-file)
    - [Working directory explained](#working-directory-explained)
    - [Hooks](#hooks)
      - [Jenkins example](#jenkins-example)
    - [Putting your initial directory revision](#putting-your-initial-directory-revision)
  - [Usage](#usage)
    - [A simple example](#a-simple-example)
      - [Producer](#producer)
      - [Consumer](#consumer)
    - [Command reference](#command-reference)
      - [info](#info)
      - [name](#name)
      - [select](#select)
      - [update](#update)
      - [get](#get)
      - [create](#create)
      - [put](#put)
  - [Differences to Git](#differences-to-git)
  - [Retention](#retention)
  - [Development notes](#development-notes)
    - [Shell vs. python, groovy etc.](#shell-vs-python-groovy-etc)

---

## Demo

![drs demo](docs/demo.gif)

:tada: For a complete dockerized example see [drs demo](demo)

It's fully functional, you can play with `put` and `get` commands.

---

## Installation

### Using sources
  1. Clone this repository to a suitable directory on your computer
  2. Add this directory plus `src` to the `DRS_HOME` environment variable
  ```bash
  export DRS_HOME=~/drs/src
  ```

### Using releases
  1. Download `drs.tar.gz` from the [latest release](https://github.com/bvarnai/drs/releases/latest)
```bash
curl -o drs.tar.gz -L https://github.com/bvarnai/drs/releases/latest/download/drs.tar.gz
```
  3. Extract archive (to a directory of your choosing)
```bash
tar -zxvf drs.tar.gz
```
  4. Add this directory to the `DRS_HOME` environment variable
```bash
export DRS_HOME=~/drs
 ```

:memo: You can set `DRS_HOME` in `~/.profile` or `~/.bashrc` to make it permanent

### Install prerequisites
#### Install *client* prerequisites on Ubuntu
```bash
sudo apt install openssh-client git rsync uuid-runtime jq
```

#### Install *client* prerequisites on Git for Windows (Git-Bash/MinGW/MSYS2)

Unfortunately `Git-Bash` doesn't have a default package manager, so installing additional tools is a manual process.

`Git-Bash` leverages MSYS2 and ships with a subset of its files. To go deeper on MSYS2 architecture see [Environment](https://www.msys2.org/docs/environments/)

Good news is that there are pre-compiled packages available, you just have download, extract the archives and add them to your existing `Git-Bash` installation.

:warning: The next steps are platform specific. I assume you are on Windows x86_64 with `Git for Windows` 64 bit version

Tested with `Git for Windows` versions:
- 2.43.0
- 2.41.0

To extract the archives you need the `zstd` tool, this needs to be installed first.

Make sure your `Git-Bash` installation directory is correct.

```bash
mkdir tmp
cd tmp
curl -L https://github.com/facebook/zstd/releases/download/v1.5.5/zstd-v1.5.5-win64.zip -o zstd-v1.5.5-win64.zip
unzip zstd-v1.5.5-win64.zip
gsudo cp zstd-v1.5.5-win64/zstd.exe 'C:\Program Files\Git\usr\bin'
```

The last `cp` command requires elevation. If don't have [gsudo](https://github.com/gerardog/gsudo) installed,
than copy `zstd-v1.5.5-win64/zstd.exe` to `C:\Program Files\Git\usr\bin` directory manually.


Once the `zstd` is working, download the following packages:

- [libxxhash-0.8.1-1-x86_64.pkg.tar.zst](http://repo.msys2.org/msys/x86_64/libxxhash-0.8.1-1-x86_64.pkg.tar.zst)
- [xxhash-0.8.1-1-x86_64.pkg.tar.zst](http://repo.msys2.org/msys/x86_64/xxhash-0.8.1-1-x86_64.pkg.tar.zst)
- [libzstd-1.5.5-1-x86_64.pkg.tar.zst](http://repo.msys2.org/msys/x86_64/libzstd-1.5.5-1-x86_64.pkg.tar.zst)
- [liblz4-1.9.4-1-x86_64.pkg.tar.zst ](https://mirror.msys2.org/msys/x86_64/liblz4-1.9.4-1-x86_64.pkg.tar.zst)
- [libopenssl-3.2.0-1-x86_64.pkg.tar.zst](https://mirror.msys2.org/msys/x86_64/libopenssl-3.2.0-1-x86_64.pkg.tar.zst)
- [rsync-3.2.7-2-x86_64.pkg.tar.zst](http://repo.msys2.org/msys/x86_64/rsync-3.2.7-2-x86_64.pkg.tar.zst)
- [util-linux-2.35.2-1-x86_64.pkg.tar.zst](http://repo.msys2.org/msys/x86_64/util-linux-2.35.2-1-x86_64.pkg.tar.zst)

You can use `get-git-bash-packages.sh` script to automate this step. Run it from the `tmp` directory.
```bash
cd tmp
. $DRS_HOME/get-git-bash-packages.sh
gsudo cp -r usr/ 'C:\Program Files\Git'
```

The last `cp` command requires elevation. If don't have [gsudo](https://github.com/gerardog/gsudo) installed,
than copy `usr/` to `C:\Program Files\Git` directory manually.

:bulb: If don't want to pollute your vanilla `Git-Bash` installation, move these packages to any directory and add it to the `PATH` variable.

#### Final *client* check
There is a script `check-client-prerequisites.sh` to check if your installation is ready:
```bash
$DRS_HOME/check-client-prerequisites.sh
```
It should print all OK.

#### Install *server* prerequisites

You will need an SSH server, pick your own favorite. For basic setup instruction see [SSH server setup](#ssh-server-setup)
or check out the demo server [Dockerfile](demo/server/Dockerfile)

:warning: No *rsync* daemon is needed, *SSH* only

## Configuration

### SSH configuration
#### SSH client setup

**drs** uses `ssh` to connect to the remote host. SSH configuration should be added to `~/.ssh/config` file. This must be done on every client.

```bash
Host <drs-host-name>
    HostName <drs-real-host-name>
    User <drs-user>
    IdentityFile <drs-user-key>
    IdentitiesOnly yes
    Port <drs-server-port>
    ForwardX11 no
    Ciphers ^aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,chacha20-poly1305@openssh.com,aes128-ctr
```
- `<drs-host-name>`: a name that used to identify host. I recommend to use something simple like `drs-server`, this allows you to change the real host name without changing the configuration in the repository
- `<drs-user-key>`: ssh private key
- `<drs-real-host-name>`: the real host name, for example drs.mycompany.com
- `<drs-user-name>`: ssh user name to login
- `<drs-host-port>`: ssh port of the host

:bulb: Cipher list is optional, based on post [Benchmark SSH Ciphers](https://gbe0.com/posts/linux/server/benchmark-ssh-ciphers/)

An example configuration
```
Host drs-server
    HostName drs.mycompany.com
    IdentityFile id_rsa
    IdentitiesOnly yes
    User drs
    Port 2222
    ForwardX11 no
    Ciphers ^aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,chacha20-poly1305@openssh.com,aes128-ctr
```
:memo: Note SSH configuration is an extensive topic, endless options to choose from. You can find out more about option here [How to Use The SSH Config File](https://phoenixnap.com/kb/ssh-config)

:bulb: If you are working in secure, trusted environment, for example a company intranet you can use a shared user for `drs`. It greatly simplifies client setup.

#### SSH server setup

If you don't have an SSH server, please follow the guide [Initial Server Setup](https://www.digitalocean.com/community/tutorials/initial-server-setup-with-ubuntu-22-04)

#### How to set up SSH keys

If you don't have SSH keys, please follow the guide [How to Set Up SSH Keys](https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-on-ubuntu-22-04)

### Metadata repository setup

This section explains how to setup the **drs** metadata repository, it's nothing more than a normal *Git* repository.

1. Create an empty *Git* repository (or use an existing one)
   ```bash
   mkdir myrepo
   git init
   ```
2. Copy the configuration template file from `$DRS_HOME/drs.json`
3. Add your project directory ("name" property in `drs.json`) to your .gitignore file. It's `myproject` in the template
4. Install *Git* aliases
    ```bash
    . $DRS_HOME/install.sh
    ```
5. Add and commit configuration
    ```bash
    git add .
    git commit -m "Add initial drs configuration"
    ```
6. Set remote
    ```bash
     git remote add origin git@myrepo.git
     ```
7. Push
    ```bash
    git push -u origin master
    ```

### Configuration file

The configuration file is called `drs.json` and it's located in the root of metadata repository.

```json
{
    "name": "<project-name>",
    "defaultBranch": "<default-branch>",
    "remote": {
        "host": "<drs-host-name>",
        "directory": "<remote-directory>",
        "rsyncOptions": {
            "get":"<rsync-options>",
            "put":"<rsync-options>"
        }
    }
}
```
- `name` - project name, defines the project directory on remote as `$remote.directory/$name` and the working directory locally as `$name`
- `defaultBranch` - commands will fall back to this default branch is nothing is specified
  - `remote` configuration section for remote
    - `host` - host name as specified in `~/.ssh/config` (see drs-host-name)
    - `directory` - base directory on the remote
    - `rsyncOptions` configuration section for rsync
      - `get` - options passed to *rsync* for `get` command
      - `put` - options passed to *rsync* for `put` command

:warning: Property `directory` will expand on client side, using an absolute path is highly recommended

For all available *rysnc* options see [rsync docs](https://download.samba.org/pub/rsync/rsync.html). The following *rsync* options added implicitly:
- `-v` , `--info=progress2` and `--itemize-changes` if `-v|--verbose` is set
- `--quiet` if `-q|--quiet` is set

:warning: These should not be added to `rsyncOptions` by default

Example configuration
```json
{
    "name": "myproject",
    "defaultBranch": "main",
    "remote": {
        "host": "drs-server",
        "directory": "/var/drs",
        "rsyncOptions": {
            "get":"-az --delete-during --stats",
            "put":"-az --delete-during --whole-file --stats"
        }
    }
}
```
This will store data on `drs-server` in `/var/drs/myproject` directory.

:memo: For my projects, the repository called `myapp-builds` and working directory called `myapp`, this will give `myapp-builds/myapp` local directory.
But nothing wrong with have `myapp/myapp` structure.

### Working directory explained

The actual contents/files are not stored in the **drs** metadata repository, but there is a dedicated directory called the working directory (a working copy if you please). For convenience this is placed under a sub directory in **drs** repository and it's ignored by *Git*.

Example structure
```bash
myrepo
  myproject
  .gitignore
  drs.json
```
- `myproject` is your working directory
- `.gitignore` contains `myproject` entry
   ```bash
   myproject
   ```

:warning: The working directory is ignored, it's not visible to *Git*. This means you won't see any change/diff in *Git* when changing the working directory contents

Otherwise there is no limitation on what you put in the metadata repository. For example you can store build information, logs, anything really. I like to think of it as where you keep your complete build history. It should be provide enough information to reproduce a specific build.

### Hooks

Hooks are shell scripts to allow project specific extensions. They are committed to the metadata repository with a predefined name and function to implement.

- `drs-info-hook.sh` is called by the `info` command. It can be used to print out user friendly information such links to Jenkins builds, source references etc.
    ```bash
    function info_hook()
    {
        # your hook implementation
        :
    }
    ```
- `drs-put-hook.sh` is called by the `put` command before commit. It can be used to collect all necessary information about a revision (a build). Such can be used by `info` command for example
     ```bash
    function put_hook()
    {
        # your hook implementation
        :
    }
    ```

#### Jenkins example

Given you have a Jenkins job which is producing your builds. `drs-put-hook.sh` will dump `env` to a file `env.json`. Than it will committed and pushed to the metadata repository.

`drs-put-hook.sh`
```bash
function put_hook()
{
  jq -n env > env.json
}
```

Clients consuming these builds will use `info` can get valuable information.

`drs-info-hook.sh`
```bash
function info_hook()
{
  change_branch=$(jq -r '.CHANGE_BRANCH' env.json)
  if [[ "${change_branch}" != "null" ]]; then
    branch="${change_branch}"
    pr="true"
  else
    branch=$(jq -r '.BRANCH_NAME' env.json)
  fi

  echo "branch: ${branch}"
  if [[ -n "${pr}" ]]; then
    echo "PR: $(jq -r '.BRANCH_NAME' env.json)"
    echo "PR link: $(jq -r '.CHANGE_URL' env.json)"
  fi

  build_url=$(jq -r '.BUILD_URL' env.json)
  echo "build link: ${build_url}"

  job_url=$(jq -r '.JOB_URL' env.json)
  echo "job link: ${job_url}"
}
```

:memo: Jenkins adds many environment variables to builds implicitly. The actual availability depends on your job setup.

### Putting your initial directory revision

1. Make sure your pushed your configuration files `drs.json` and `.gitignore`
2. Copy your initial content to the working directory
3. Put your directory to remote
    ```bash
    git drs-put
    ```

## Usage

### A simple example

#### Producer

```bash
# create a new branch (based on the source branch)
git drs-create myFeature
# put new build artifacts to remote
git drs-put
```

#### Consumer

```bash
# select the branch you need a build from
git drs-select myFeature
# update to the latest available build
git drs-update
# get the build
git drs-get
```

### Command reference

Command syntax is the following:

```bash
git drs-<command> [options] [arguments]
```

Optional elements are shown in brackets [ ]. For example, many commands take a branch name as an argument.

To get some information about a command and a link to it's reference documentation use `command` with `help`:

```bash
git drs-<command> help
```

:bulb: You can also use commands without *Git* alias, this is recommended for scripts. Refer to the command name
when calling

```bash
$DRS_HOME/<command>.sh
```

---
#### info

The commit message is not very informative. To get more user friendly information use `info`:

```bash
git drs-info
```

The `info` command implementation is project specific, see section [Hooks](#hooks)

---
#### name

To get the current branch name use `name`:

```bash
git drs-name
```

---
#### select

To select and switch to an existing branch use `select`:

```bash
git drs-select [<branch>|<tag>|<uuid>]
```

Arguments:

- `branch, tag` - the branch, tag to select, if not specified the `defaultBranch` property will be used (optional)
- `uuid` - the uuid to select, alternatively this searches the log for a specific uuid (optional)

:memo: `uuid` based selection is useful is to identify builds for example, Jenkins can post the `uuid` for each build and users can use this directly

![jenkins uuid](docs/jenkins-uuid.png)

---
#### update

To get to the latest revision use `update`:

```bash
git drs-update
```

:memo: If you are in detached HEAD state (not on any branch), `update` will fail. You need to select a branch than update it

---
#### get

To get the directory revision specified by the current commit. The working directory content will be synchronized with this revision.

```bash
git drs-get [-v,--verbose] [-q,--quiet] [--stats] [--latest] [<target_directory>]
```

Options:

- `verbose` - sets *rsync* verbose mode (optional)
- `quite` - sets *rsync* quiet mode (optional)
- `stats` - enables *rsync* statistics (optional)
- `latest` - combines `update` and `get` to get the latest version

Arguments:

- `target_directory` – the directory to get content to, if not specified set the `name` property will be used (optional)

:bulb: Usually you are only interested in the latest version, this can be done with a one-liner:

```bash
git drs-get --latest
```

---
#### create

To create a new branch use `create`:

```bash
git drs-create [<branch>]
```

Arguments:

- `branch` - the branch to create (mandatory)

---
#### put

To put revision to remote host use `put`:

```bash
git drs-put [-v,--verbose] [--no-sequence-check] [-s,--sequence <sequence_number>] [<source_directory>]
```

Options:

- `verbose` - sets *rsync* verbose mode (optional)
- `quite` - sets *rsync* quiet mode (optional)
- `stats` - enables *rsync* statistics (optional)
- `no-sequence-check` - disables sequence number checking
- `sequence_number` - the sequence number, must be a comparable decimal (optional)

Arguments:

- `source_directory` – the directory to put content from (optional)

Simple Jenkins example for using `--sequence`

```bash
$DRS_HOME/create.sh $BRANCH_NAME
$DRS_HOME/update.sh
$DRS_HOME/put.sh --sequence $BUILD_ID my_build_dir
```

:memo: `BRANCH_NAME` and `BUILD_ID` are Jenkins job variables

`source_directory` allows you to use a source directory eliminating the need to stage (copy) content to the working directory

## Differences to Git

Since **drs** is uses *Git* more like a database, therefore not all *Git* concepts apply. Especially collaboration is completely different in a **drs** metadata repository.

:warning: In case you want to work with *native* *Git* commands, the following notes are important to understand

- **Origin has precedence**

    To keep the workflow simple and robust, origin has precedence. Commands will force you to be up-to-date with origin and `drs-put` will implicitly try to push the new revision. This ensures whatever happens users will be fall back to a public *last known* version. Origin is the single source of truth, which must less error prune in single producer, multiple consumer context.
- **No merging**

    Revisions are not stored in *Git*, they are simple directories somewhere. As you cannot merge a directory on a filesystem, you cannot merge in **drs** either.

- **Commit message format**

  Commit message has a strict format. You should not create them manually.

:memo: **No merging** implies that branches are not merged. They are created than deleted if not needed. It's possible to keep all branches if you want to keep all history.

## Retention

Deleting revisions is done by deleting directories on the remote host. **drs** will try to locate a revision, if not found, it's assumed to be deleted. This part of the normal
workflow and will not be treated as error. To implement a simple retention policy, you can setup a cron job or Jenkins job to delete directories older than 2 weeks for example.

## Development notes

*Git* was a convenient choice to make something distributed and transactional. Directory metadata is published as a *Git* commit message in `json` format. :cold_sweat: ugh, you might say, and you are probably right. I abused the commit message, but in a good way, embracing the tremendous flexibility *Git* offers. I didn't use *Git* notes because I don't have anything to annotate, I just want to record something.

So a typical **drs** commit message looks like this:

```json
{"uuid":"c1ca82b1-7f34-4f4c-9a76-05e3297b2a23","seq":"1622824489"}
```

The `uuid` is used to identify the directory on the remote host. The sequence number helps to drop outdated builds.

*rsync* is a great tool when your have a small deltas to deal with. Initially I wanted to use a "trendy" S3 ([minIO](https://min.io/) for example) based solution, but I realized not much is gained there. I think for a small development team, these are just adding an unnecessary overhead.

### Shell vs. python, groovy etc.

Obviously this is very subjective topic. I wanted to rely on external tools and keep it simple as possible. No advanced logic and the seamless integration with *Git* aliases pushed me in the direction to use shell only.

I used Google's [Shell Style Guide](https://google.github.io/styleguide/shellguide.html) with the help of [ShellCheck](https://www.shellcheck.net/)
