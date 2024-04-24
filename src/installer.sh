#!/bin/bash
{

# Constants
# Important: only single digits are supported due to lexical comparsion
# shellcheck disable=SC2034
INSTALLER_VERSION="2.7.9"

declare -r INSTALLER_SELF_URL=${INSTALLER_SELF_URL:-'https://#token#@raw.githubusercontent.com/bvarnai/respository-installer/#branch#/src/installer.sh'}
declare -r INSTALLER_CONFIG_URL=${INSTALLER_CONFIG_URL:-'https://#token#@raw.githubusercontent.com/bvarnai/respository-installer/#branch#/src/projects.json'}
declare -r INSTALLER_CONFIG_TOKEN=${INSTALLER_CONFIG_TOKEN:-''}
declare -r INSTALLER_DEFAULT_BRANCH=${INSTALLER_DEFAULT_BRANCH:-'main'}
declare -r INSTALLER_CONFIG_SCM=${INSTALLER_CONFIG_SCM:-'github'}
declare -r INSTALLER_GET_STREAM_CONFIGURATION=${INSTALLER_GET_STREAM_CONFIGURATION:-"get_stream_configuration_${INSTALLER_CONFIG_SCM}"}
declare -r INSTALLER_GET_SELF=${INSTALLER_GET_SELF:-"get_self_${INSTALLER_CONFIG_SCM}"}
declare -r INSTALLER_GET_SELF_STRICT=${INSTALLER_GET_SELF_STRICT:-'false'}

# User specific funtions
declare -r INSTALLER_GET_DEPENDENCIES=${INSTALLER_GET_DEPENDENCIES:-'user_get_depedencies'}
declare -r INSTALLER_LINK=${INSTALLER_LINK:-'user_link'}
declare -r INSTALLER_UNLINK=${INSTALLER_UNLINK:-'user_unlink'}

# shellcheck disable=SC2317
function user_get_depedencies()
{
  # jq
  # check if jq is available on the path
  if jq --version >/dev/null 2>&1; then
    JQ='jq'
  else
    # get source location for download
    if [[ $(uname -s) == "Linux" ]]; then
        JQSourceURL='https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64'
    else
        JQSourceURL='https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-windows-amd64.exe'
    fi
    JQ='.installer/jq'
  fi

  # if not available then try to download
  if [[ -n ${JQSourceURL} ]]; then
    log "Getting jq..."
    if ! curl -s -L "${JQSourceURL}" -o "${JQ}" --create-dirs; then
      err "Failed to download jq binary"
      exit 1
    fi
    # set executable permission (it's curled)
    chmod +x "${JQ}" > /dev/null 2>&1;
  fi
}

#######################################
# Creates folder links, platform specific.
# Arguments:
#   TBD
# Returns:
#   TBD
#######################################
function user_link()
{
  log "Creating link $1 to $2"
  if [[ $(uname -s) == "Linux" ]]; then
    ln -s "${2}" "${1}"
  else
    cmd <<< "mklink /j \"$1\" \"${2//\//\\}\"" > /dev/null
  fi
}

function user_unlink() {
  :
}

#######################################
# Displays help.
# Arguments:
#   None
# Returns:
#   None
#######################################
function help()
{
  local filename
  filename=$(basename "$0")
  echo "Usage: ${filename} [options] [<command>] [arguments]"; \
  echo "Install project repositories."; \
  echo "Commands:"; \
  echo "  install [project...]  install a project(s) - default -"; \
  echo "  list                  list available projects"; \
  echo "  update                update existing projects"; \
  echo "  help                  print help - this -"; \
  echo "Options:"; \
  echo "      --use-local-config          use the local the configuration file"; \
  echo "      --skip-self-update          do not update the script itself"; \
  echo "  -y, --yes                       say 'yes' to user questions"; \
  echo "      --link <target>             linked mode"; \
  echo "      --branch <branch>           project branch, if it exits on remote (defaults to 'branch' in configuration)"; \
  echo "      --stream <branch>           development stream (defaults to master)"; \
  echo "      --clone-options <branch>    clone options (defaults to 'cloneOptions' in configuration)"; \
  echo "      --fetch-all                 fetch all remotes"; \
  echo "      --prune                     prune during fetch"; \
  echo "      --git-quiet                 run git commands with '--quite' option"; \
  echo "      --skip-dolast               do not run doLast commands"; \
  echo ""; \
  echo "More information visit https://github.com/bvarnai/respository-installer" 1>&2; exit 0;
}

#######################################
# Creates folder links, platform specific.
# Arguments:
#   TBD
# Returns:
#   TBD
#######################################
function link()
{
  log "Creating link $1 to $2"
  if [[ $(uname -s) == "Linux" ]]; then
    ln -s "${2}" "${1}"
  else
    cmd <<< "mklink /j \"$1\" \"${2//\//\\}\"" > /dev/null
  fi
}


#######################################
# Installs a project.
# Arguments:
#   $1 - the project configuration
#   $2 - the project branch set/unset
#   $3 - the project branch
#   $4 - the clone options set/unset
#   $5 - the clone options
#   $6 - fetch --all option
#   $7 - git --quite option
#   $8 - git --prune option
#   $9 - skip doLast
# Returns:
#   None
#######################################
function install_project()
{
  local configuration="$1"
  local projectBranchSet="$2"
  local projectBranch="$3"
  local cloneOptionsSet="$4"
  local cloneOptions="$5"
  local fetchAll="$6"
  local gitQuiet="$7"
  local gitPrune="$8"
  local skipDoLast="$9"

  local project
  project=$(echo "${configuration}" | "${JQ}" -r '.name')
  log "Installing project '${project}'"

  local clone=1
  local fetchURL
  local pushURL

  fetchURL=$(echo "${configuration}" | "${JQ}" -r ".urls.fetch?")
  if [[ "${fetchURL}" == "null" ]]; then
    err "Project fetch URL is not configured"
    exit 1
  fi
  log "Repository fetch URL '${fetchURL}'"

  pushURL=$(echo "${configuration}" | "${JQ}" -r ".urls.push?")
  if [[ "${pushURL}" == "null" ]]; then
    # fallback to use the same url
    pushURL="${fetchURL}"
  fi
  log "Repository push URL '${pushURL}'"

  local branch
  branch=$(echo "${configuration}" | "${JQ}" -r ".branch")

  local update
  update=$(echo "${configuration}" | "${JQ}" -r ".update")

  local rebase
  rebase=$(echo "${configuration}" | "${JQ}" -r ".rebase?")
  if [[ "${rebase}" == "null" ]]; then
    rebase="false"
  fi

  local path
  path=$(echo "${configuration}" | "${JQ}" -r ".path?")
  if [[ "${path}" == "null" ]]; then
    path="${project}"
  fi

  local quite
  if [[ "${gitQuiet}" == 1 ]]; then
    quite="--quiet"
  else
    quite=""
  fi

  # in link mode, create symbolic links first
  if [[ $link == 1 ]]; then
    # target directory exists?
    if [[ -d "${linkTarget}/${path}" ]]; then
      log "Existing target directory found"
    else
      # create target directory
      if ! mkdir -p "${linkTarget}/${path}"; then
        err "Unable to create directory"
        exit 1
      fi
    fi

    # link directory exists?
    if [[ -d "${path}" ]]; then
      log "Existing link directory found, removing"
      # if target is a link, unlink first
      if [[ $(uname -s) == "Linux" ]]; then
        # no need to unlink
        :
      else
        fsutil reparsepoint delete "${path}" > /dev/null 2>&1;
      fi
      if ! rm -r "${path}"; then
        err "Unable to remove directory"
        exit 1
      fi
    fi
    $INSTALLER_LINK "${path}" "${linkTarget}/${path}"
  fi

  if [[ -d "${path}" ]]; then
    # project directory exists
    if git -C "${path}" rev-parse > /dev/null 2>&1; then
      log "Existing repository found, updating"
      pushd "${path}" > /dev/null || exit
      # set remote url
      if ! git remote set-url origin "${fetchURL}" > /dev/null; then
        err "Unable to set remote URL"
        exit 1
      fi
      # it's a git repo
      # check current remote refs and delete them if not they don't exist on remote.
      check_remote_refs
      # first check if project branch exists on remote?
      if [[ "${projectBranchSet}" == 1 ]]; then
        if git ls-remote --exit-code origin "refs/heads/${projectBranch}" > /dev/null 2>&1; then
          branch="${projectBranch}"
        else
          log "Warning: specified project branch doesn't exists, using configured default branch"
        fi
      fi
      # check if fetch configuration contains our refspec for the current branch

      configRefs=$(git config  --local --get-all remote.origin.fetch)
      # shellcheck disable=SC2206
      refsArray=($configRefs)
      if [[ "${refsArray[*]}" =~ "*" ]]; then
        git config --unset-all "remote.origin.fetch" > /dev/null
        git config --add remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*" > /dev/null
      else
        if ! git config --get-regex remote.origin.fetch "refs/heads/${branch}" > /dev/null 2>&1; then
          if ! git config --add remote.origin.fetch "+refs/heads/${branch}:refs/remotes/origin/${branch}" > /dev/null 2>&1; then
            err "Unable to add fetch refspec entry"
            exit 1
          fi
        fi
      fi

      local prune
      if [[ "${gitPrune}" == 1 ]]; then
        prune="--prune"
      else
        prune=""
      fi

      log "Branch '${branch}' is selected"
      if [[ "${fetchAll}" == 1 ]]; then
        if ! git fetch --all $prune $quite; then
          err "Unable to fetch remote"
          exit 1
        fi
      else
        if ! git fetch origin "${branch}" $prune $quite; then
          err "Unable to fetch remote"
          exit 1
        fi
      fi

      if ! git checkout "${branch}" $quite; then
        err "Unable to checkout branch"
        exit 1
      fi

      if [[ "${update}" == "true" ]]; then
        log "Resetting to latest revision before updating"
        if ! git reset --hard "origin/${branch}" $quite; then
          err "Unable to reset branch"
          exit 1
        fi
      fi

      if [[ "${update}" == "true" ]]; then
        if ! git pull origin "${branch}" --rebase="${rebase}" $quite; then
          err "Unable to pull updates"
          exit 1
        fi
      else
        log "Skipping reset"
      fi
      clone=0
      popd > /dev/null || exit
    else
      if [[ ! $link == 1 ]]; then
        log "Existing directory found, removing"
        if ! rm -r "${path}"; then
          err "Unable to remove directory"
          exit 1
        fi
      fi
    fi
  fi

  if [[ ${clone} == 1 ]]; then
    log "Cloning repository"

    # check if there is global override
    if [[ "${cloneOptionsSet}" == 0 ]]; then
      # use the configuration otherwise
      cloneOptions=$(echo "${configuration}" | "${JQ}" -r ".cloneOptions?")
      if [[ "${cloneOptions}" == "null" ]]; then
        cloneOptions=""
      fi
    fi

    # first check if project branch exists on remote?
    if [[ "${projectBranchSet}" == 1 ]]; then
      if git ls-remote --exit-code "${fetchURL}" "refs/heads/${projectBranch}" > /dev/null 2>&1; then
        branch="${projectBranch}"
      else
        log "Warning: specified project branch doesn't exists, using configured default branch"
      fi
    fi
    log "Branch '${branch}' is selected"
    # shellcheck disable=SC2086
    if ! git clone $cloneOptions --branch "${branch}" "${fetchURL}" "${path}" $quite; then
      err "Unable to clone repository"
      exit 1
    fi
  fi

  if [[ -d "${path}" ]]; then

    pushd "${path}" > /dev/null || exit

    # set remote push url
    if ! git remote set-url --push origin "${pushURL}"; then
      err "Unable to set remote push URL"
      exit 1
    fi

    # display where we are now
    log "Now at commit"
    git log -1 --oneline

    popd > /dev/null || exit
  fi

  gitConfig "${configuration}"
  doLast "${configuration}" "${skipDoLast}"
}

#######################################
# Sets git configuration setting from the configuration.
# Arguments:
#   TBD
# Returns:
#   TBD
#######################################
function gitConfig()
{
  local configuration="$1"

  local project
  project=$(echo "${configuration}" | "${JQ}" -r '.name')

  local path
  path=$(echo "${configuration}" | "${JQ}" -r ".path?")
  if [[ "${path}" == "null" ]]; then
    path="${project}"
  fi

  local gitConfigs
  gitConfigs=$(echo "${configuration}" | "${JQ}" -r ".configuration[]?")
  if [[ -n "$gitConfigs" ]]; then
    log "Setting git config(s)"
    pushd "${path}" > /dev/null || exit
    while IFS= read -r gitConfig; do
      # split string by whitespace to key-value pairs
      local keyValue
      # shellcheck disable=SC2206
      keyValue=($gitConfig)
      if ! git config --local "${keyValue[0]}" "${keyValue[1]}" > /dev/null; then
        err "Unable to set local git configuration"
        popd > /dev/null || exit
        exit 1
      fi
    done <<< "${gitConfigs}"
    popd > /dev/null || exit
  fi
}

#######################################
# Executes doLast commands from the configuration.
# Arguments:
#   TBD
# Returns:
#   TBD
#######################################
function doLast()
{
  local configuration="$1"
  local skipDoLast="$2"

  if [[ ${skipDoLast} == 1 ]]; then
    log "Skipping doLast commands"
  else
    local project
    project=$(echo "${configuration}" | "${JQ}" -r '.name')

    local path
    path=$(echo "${configuration}" | "${JQ}" -r ".path?")
    if [[ "${path}" == "null" ]]; then
      path="${project}"
    fi

    local commands
    commands=$(echo "${configuration}" | "${JQ}" -r ".doLast[]?")
    if [[ -n "$commands" ]]; then
      log "Running doLast command(s)"
      pushd "${path}" > /dev/null || exit
      while IFS= read -r command; do
        local trimmedCommand
        trimmedCommand=$(echo "${command}" | xargs)
        if ! $trimmedCommand; then
          err "Failed to execute doLast command"
          popd > /dev/null || exit
          exit 1
        fi
      done <<< "${commands}"
      popd > /dev/null || exit
    fi
  fi
}

#######################################
# Gets consent from the user that changes at risk.
# Arguments:
#   TBD
# Returns:
#   TBD
#######################################
function precondition_user_confirm_uncommited()
{
  # user already said yes?
  if [[ $1 == 0 ]]; then
    log "Existing project repositories might be reset depending on the configuration"
    while true; do
      read -r -p "Uncommited changes maybe at risk, do you want to continue? (y/n)" yn
      case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit 1;;
        * ) echo "Please answer Yy or Nn.";;
      esac
    done
  fi
}

#######################################
# Encodes strings for cURL compatibility.
# Arguments:
#   TBD
# Returns:
#   TBD
#######################################
# shellcheck disable=SC2317
function urlencode() {
  oldLC_COLLATE=$LC_COLLATE
  LC_COLLATE=C

  local length="${#1}"
  for (( i = 0; i < length; i++ )); do
      local c="${1:i:1}"
      case $c in
          [a-zA-Z0-9.~_-]) printf "$c" ;;
          ' ') printf "%%20" ;;
          *) printf '%%%02X' "'$c" ;;
      esac
  done

  LC_COLLATE=$oldLC_COLLATE
}

#######################################
# Downloads the stream configuration from
# Bitbucket Enterprise SCM.
# credits https://gist.github.com/cdown/1163649
# Arguments:
#   TBD
# Returns:
#   TBD
#######################################
# shellcheck disable=SC2317
function get_stream_configuration_bitbucket_server()
{
  local streamBranchSet="$1"
  local streamBranch="$2"
  local configurationURL="${INSTALLER_CONFIG_URL}"
  local defaultBranch="${INSTALLER_DEFAULT_BRANCH}"
  local token="${INSTALLER_CONFIG_TOKEN}"

  local bearerToken
  if [[ -z $token ]]; then
    bearerToken=""
  else
    bearerToken="Authorization: Bearer ${token}"
  fi

  log "Getting stream configuration..."
  if [[ "${streamBranchSet}" == 1 ]]; then
    # shellcheck disable=2162
    { read -d '' streamRefSpec; }< <(urlencode "refs/heads/${streamBranch}")
    # it's not possible to check remote branch here
    # as no git reposiory available yet, just try to fetch the file
    local httpCode
    httpCode=$(curl_scm "${configurationURL}?at=${streamRefSpec}" "${bearerToken}" 'projects.json')
    if [[ ${httpCode} -ne 200 ]] ; then
      err "Stream branch doesn't exists"
      exit 1
    else
      # success
      log "Stream branch '${streamBranch}' is selected"
      return
    fi
  else
    # shellcheck disable=2162
    { read -d '' streamRefSpec; }< <(urlencode "refs/heads/${defaultBranch}")
    httpCode=$(curl_scm "${configurationURL}?at=${streamRefSpec}" "${bearerToken}" 'projects.json')
    if [[ ${httpCode} -ne 200 ]] ; then
      err "Failed to download stream configuration"
      exit 1
    else
      log "Stream branch '${defaultBranch}' is selected (default)"
    fi
  fi
}

#######################################
# Downloads the stream configuration from web server with static content.
# Arguments:
#   TDB
# Returns:
#   TBD
#######################################
# shellcheck disable=SC2317
function get_stream_configuration_plain()
{
  get_stream_configuration_github "$1" "$2"
}

#######################################
# Downloads the stream configuration from
# GitHub SCM.
# Arguments:
#   TBD
# Returns:
#   TBD
#######################################
# shellcheck disable=SC2317
function get_stream_configuration_github()
{
  local streamBranchSet="$1"
  local streamBranch="$2"
  local configurationURL="${INSTALLER_CONFIG_URL}"
  local defaultBranch="${INSTALLER_DEFAULT_BRANCH}"
  local token="${INSTALLER_CONFIG_TOKEN}"

  log "Getting stream configuration..."

  # shellcheck disable=SC2001
  configurationURL=$(echo "$configurationURL" | sed "s/#token#/$token/")
  if [[ "${streamBranchSet}" == 1 ]]; then
    # shellcheck disable=2162
    { read -d '' streamRefSpec; }< <(urlencode "${streamBranch}")
    # it's not possible to check remote branch here
    # as no git reposiory available yet, just try to fetch the file
    local httpCode
    # shellcheck disable=SC2001
    configurationURL=$(echo "$configurationURL" | sed "s/#branch#/$streamRefSpec/")
    httpCode=$(curl_scm "${configurationURL}" '' 'projects.json')
    if [[ ${httpCode} -ne 200 ]] ; then
      err "Stream branch '${streamRefSpec}' doesn't exists"
      exit 1
    else
      # success
      log "Stream branch '${streamBranch}' is selected"
      return
    fi
  else
    local httpCode
    # shellcheck disable=SC2001
    configurationURL=$(echo "$configurationURL" | sed "s/#branch#/$defaultBranch/")
    httpCode=$(curl_scm "${configurationURL}" '' 'projects.json')
    if [[ ${httpCode} -ne 200 ]] ; then
      err "Failed to get stream configuration on branch '${defaultBranch}' (default)"
      exit 1
    else
      log "Stream branch '${defaultBranch}' is selected (default)"
    fi
  fi
}

#######################################
# Checks if we are inside another Git repository which can cause all kinds of
# nasty issues.
# Arguments:
#   None
# Returns:
#   None
#######################################
function precondition_nested_repository()
{
  if git rev-parse > /dev/null 2>&1; then
    err "It seems you running inside of a git repository..."
    err "Due to compatibility reasons, nested repository structures are not supported."
    exit 1
  fi
}

#######################################
# Set JQ and download URL depending on OS type.
# Arguments:
#   None
# Returns:
#   JQSourceURL - platfrom specific download location
#   JQ - the executable
#######################################
function set_jq()
{
  # check if jq is available on the path
  if jq --version >/dev/null 2>&1; then
    JQ='jq'
  else
    # get source location for download
    if [[ $(uname -s) == "Linux" ]]; then
        JQSourceURL='https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64'
    else
        JQSourceURL='https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-windows-amd64.exe'
    fi
    JQ='.installer/jq'
  fi
}

#######################################
# Downloads the JQ tool binary from local SCM.
# Arguments:
#   None
# Returns:
#   None
#######################################
function get_jq()
{
  # if source is set then try to download
  if [[ -n ${JQSourceURL} ]]; then
    log "Getting jq..."
    if ! curl -k -s -L -# "${JQSourceURL}" -o "${JQ}" --create-dirs; then
      err "Failed to download jq binary"
      exit 1
    fi
    # set executable permission (it's curled)
    chmod +x "${JQ}" > /dev/null 2>&1;
  fi
}

#######################################
# Call curl with optional authentication.
# Arguments:
#   TBD
# Returns:
#   TBD
#######################################
# shellcheck disable=SC2317
function curl_scm()
{
  local url="$1"
  local token="$2"
  local output="$3"

  local httpCode
  httpCode=$(curl -s -k --write-out "%{http_code}" -H "'${token}'" -L "${url}" -o "${output}")
  # shellcheck disable=SC2086
  echo $httpCode
}

declare -r LOG_PREFIX="[installer]"

#######################################
# Logs a message to stdout.
# Arguments:
#   $@ - anything to log
# Returns:
#   None
#######################################
function log()
{
  echo "${LOG_PREFIX} $*"
}

#######################################
# Logs a message to stderr.
# Arguments:
#   $@ - anything to log
# Returns:
#   None
#######################################
function err()
{
  # quick sleep to get all responses from the remote ops
  sleep 1s > /dev/null 2>&1;
  echo -e "${LOG_PREFIX} ! $*" >&2
}

#######################################
# Check if remote refspec exists? and delete them if not.
# Arguments:
#   None
# Returns:
#   None
#######################################
function check_remote_refs()
{
  # retrieve all remote refs from local git config file
  configRefs=$(git config  --local --get-all remote.origin.fetch)
  # remove all remote refs from local git config file
  git config --unset-all "remote.origin.fetch" > /dev/null
  # shellcheck disable=SC2206
  refsArray=($configRefs)
  for ref in "${refsArray[@]}"; do
    remoteBranchName=${ref#*+refs/heads/}
    remoteBranchName=${remoteBranchName%:*}
    # # first check if remote branch exists on remote?
    if git ls-remote --exit-code origin "refs/heads/${remoteBranchName}" > /dev/null 2>&1; then
        if [[ $remoteBranchName == "*" ]]; then
            git config --add remote.origin.fetch "+refs/heads/${remoteBranchName}:refs/remotes/origin/${remoteBranchName}"
        fi
        # Add a ref to existing remote branch
        if ! git config --get-regex remote.origin.fetch "refs/heads/${remoteBranchName}" > /dev/null 2>&1; then
          git config --add remote.origin.fetch "+refs/heads/${remoteBranchName}:refs/remotes/origin/${remoteBranchName}"
        fi
      else
        err "Warning: branch ${remoteBranchName} doesn't exist on remote!"
    fi
  done
}

function main()
{
  # process arguments
  local params
  local yes
  local list
  local update
  local link
  local linkTarget
  local projectBranchSet
  local projectBranch
  local streamBranchSet
  local streamBranch
  local cloneOptionsSet
  local cloneOptions
  local useLocalConfiguration
  local fetchAll
  local gitQuiet
  local gitPrune
  local skipDoLast
  yes=0
  list=0
  update=0
  link=0
  projectBranchSet=0
  projectBranch="unset"
  streamBranchSet=0
  streamBranch="unset"
  cloneOptionsSet=0
  cloneOptions="unset"
  useLocalConfiguration=0
  fetchAll=0
  gitQuiet=0
  gitPrune=0
  skipDoLast=0
  params=
  while (( "$#" )); do
    case "$1" in
      help) # print usage
        help
        ;;
      list) # list projects
        list=1
        shift
        ;;
      update) # update projects
        update=1
        shift
        ;;
      install) # do nothing it's the default command
        shift
        ;;
      --link)
        link=1
        shift
        linkTarget="$1"
        shift
        ;;
      --branch)
        projectBranchSet=1
        shift
        projectBranch="$1"
        shift
        ;;
      --stream)
        streamBranchSet=1
        shift
        streamBranch="$1"
        shift
        ;;
      --clone-options)
        cloneOptionsSet=1
        shift
        cloneOptions="$1"
        shift
        ;;
      --use-local-config)
        useLocalConfiguration=1
        shift
        ;;
      --skip-self-update)
        shift
        ;;
      --fetch-all)
        fetchAll=1
        shift
        ;;
      -y|--yes)
        yes=1
        shift
        ;;
      --git-quiet)
        gitQuiet=1
        shift
        ;;
      --prune)
        gitPrune=1
        shift
        ;;
      --skip-dolast)
        skipDoLast=1
        shift
        ;;
      --) # end argument parsing
        shift
        break
        ;;
      -*|--*=) # unsupported options
        echo "Unsupported option '$1'" >&2
        exit 1
        ;;
      *) # preserve positional arguments
        params="${params} $1"
        shift
        ;;
    esac
  done
  # set positional arguments in their proper place
  eval set -- "${params}"

  # check preconditions
  precondition_nested_repository

  if [[ -n ${INSTALLER_GET_DEPENDENCIES} ]]; then
    # get user specific dependencies
    $INSTALLER_GET_DEPENDENCIES
  fi

  if [[ "${useLocalConfiguration}" == "0" ]]; then
    # get/update stream configuration
    $INSTALLER_GET_STREAM_CONFIGURATION "${streamBranchSet}" "${streamBranch}"
  else
    if [[ ! -f "projects.json" ]]; then
      err "No local configuration found"
      exit 1
    else
      log "Using local configuration"
    fi
  fi

  # list projects
  if [[ ${list} == 1 ]]; then
    log "Available projects:"
    list_projects
    exit 0
  fi

  # getting dangerous from here
  precondition_user_confirm_uncommited "${yes}"

  # TODO handle SSL verification aka http.sslVerify

  if [[ ${link} == 1 ]]; then
    log "Using linked mode"
    if [[ ! -d "${linkTarget}" ]]; then
      err "Link target directory does not exists"
      exit 1
    fi
  fi

  local projectNamesArray
  if [[ ${update} == 0 ]]; then
    # projects specified by user
    local projectNames
    projectNames=$( echo "${params}" | xargs echo )

    # shellcheck disable=SC2206
    projectNamesArray=($projectNames)
  else
    log "Searching for existing projects in the current directory (workspace)"

    local workspace
    workspace=$(pwd)

    projectNames=()
    local projectNamePredicates
    projectNamePredicates=$( find "$workspace" -maxdepth 1 -type d -printf '%P '  | xargs echo )
    # shellcheck disable=SC2206
    local projectNamePredicatesArray=($projectNamePredicates)
    for projectNamePredicate in "${projectNamePredicatesArray[@]}"
    do
      # add only valid projects
      project_exists "${projectNamePredicate}"
      if [[ ! "${LAST_RETURN}" == "0" ]]; then
        projectNames+=("${projectNamePredicate}")
      fi
    done
    projectNamesArray=("${projectNames[@]}")
  fi

  local bootstrapProject
  bootstrapProject=$("${JQ}" -r '.bootstrap' projects.json)

  local bootstrapProjectAdded=0
  # project order can affect doLast scripts
  local orderedProjects=false
  # is there a user project selection?
  if [[ "${#projectNamesArray[@]}" != "0" ]]; then
    for projectName in "${projectNamesArray[@]}"
    do
      project_exists "${projectName}"
      if [[ "${INSTALLER_LAST_RETURN}" == "0" ]]; then
          # user selected project is not found
          err "Project '${projectName}' is undefined"
          log "Hint: Check your project(s) configuration"
          exit 1
      fi
      if [[ "${projectName}" == "${bootstrapProject}" ]]; then
        bootstrapProjectAdded=1
      fi
    done

    # make sure mandatory 'tools' project is added
    if [[ ${bootstrapProjectAdded} == 0 ]]; then
      log "Adding bootstrap project '$bootstrapProject' implicitly"
      # add to the beginning of the array
      projectNamesArray=("${bootstrapProject}" "${projectNamesArray[@]}")
    fi
  else
    log "No projects were specified by the user, adding default projects"
    # no user project selection, add all 'default' projects from the configuration
    readarray -t projectNamesArray < <("${JQ}" -r '.projects[] | select(.default=="true") | .name' projects.json)

    # project order retained from the configuration file
    orderedProjects=true
  fi

  # sort projects
  if [[ $orderedProjects = false ]]; then
    log "Sorting projects based on configuration index"
    local orderedProjectNamesArray
    orderedProjectNamesArray=()
    # load the projects from the configuration
    local configurationProjectNamesArray
    readarray -t configurationProjectNamesArray < <("${JQ}" -r '.projects[] | .name' projects.json)
    for configurationProjectName in "${configurationProjectNamesArray[@]}"
    do
      # trim name
      configurationProjectName=$(echo "${configurationProjectName}" | xargs)
      for projectName in "${projectNamesArray[@]}"
      do
        if [[ "${projectName}" = "${configurationProjectName}" ]]; then
          orderedProjectNamesArray+=("${projectName}")
        fi
      done
    done
    # overwrite with sorted array
    projectNamesArray=("${orderedProjectNamesArray[@]}")
  fi

  # allow remote branch refs
  projectBranch=${projectBranch/"remotes/origin/"/""}

  # install projects
  for projectName in "${projectNamesArray[@]}"
  do
    # trim name
    projectName=$(echo "${projectName}" | xargs)
    find_project_by_name "${projectName}"
    install_project "${INSTALLER_LAST_RETURN}" "${projectBranchSet}" "${projectBranch}" "${cloneOptionsSet}" "${cloneOptions}" "${fetchAll}" "${gitQuiet}" "${gitPrune}" "${skipDoLast}"
  done
}

#######################################
# Lists projects.
# Globals:
#  None
# Arguments:
#  None
#######################################
function list_projects()
{
  local length
  length=$("${JQ}" -r '.projects | length' projects.json)
  for ((i = 0 ; i < "${length}" ; i++)); do
    # to impove performance read all values once
    local currentProjectConfiguration
    currentProjectConfiguration=$("${JQ}" -r ".projects[${i}] | [.name, .category, .default, .path?] | join(\",\")" projects.json)
    local currentProjectConfigurationArray
    IFS=',' read -r -a currentProjectConfigurationArray <<< "${currentProjectConfiguration}"

    local currentProjectPath
    if [[ -z "${currentProjectConfigurationArray[3]}" ]]; then
      currentProjectPath="${currentProjectConfigurationArray[0]}"
    else
      currentProjectPath="${currentProjectConfigurationArray[3]}"
    fi

    local currentProjectCategory
    if [[ -z "${currentProjectConfigurationArray[1]}" ]]; then
      currentProjectCategory="unset"
    else
      currentProjectCategory="${currentProjectConfigurationArray[1]}"
    fi

    printf "%-20s (category: %-11s, default: %-5s, path: %s)\n" "${currentProjectConfigurationArray[0]}" "${currentProjectCategory}" "${currentProjectConfigurationArray[2]}" "${currentProjectPath}"
  done
}

#######################################
# Find project in configuration file by name;
# Globals:
#  LAST_RETURN - the project configuration JSON object
# Arguments:
#  $1 - project name
#######################################
function find_project_by_name()
{
  INSTALLER_LAST_RETURN=0
  local projectName="$1"

  local projectConfiguration
  projectConfiguration=$("${JQ}" -r ".projects[] | select(.name == \"${projectName}\")" projects.json)
  if [[ ! -z "${projectConfiguration}" ]]; then
    INSTALLER_LAST_RETURN="${projectConfiguration}"
  fi
}

#######################################
# Checks project in configuration file by name;
# Globals:
#  INSTALLER_LAST_RETURN - "1" if project exsits, "0" otherwise
# Arguments:
#  $1 - project name
#######################################
function project_exists()
{
  INSTALLER_LAST_RETURN=0
  local projectName="$1"

  local projectConfiguration
  projectConfiguration=$("${JQ}" -r ".projects[] | select(.name == \"${projectName}\")" projects.json)
  if [[ ! -z "${projectConfiguration}" ]]; then
    INSTALLER_LAST_RETURN=1
  fi
}

#######################################
# Self-update; credits https://gist.github.com/cubedtear/54434fc66439fc4e04e28bd658189701
# Globals:
#  INSTALLER_LATEST - returns 1 if the script is at the lastest version; 0 otherwise
# Arguments:
#  None
#######################################
function update()
{
  log "[updater] Checking for updates..."
  local temporaryFile
  temporaryFile=$(mktemp -p "" "XXXXX.sh")

  # call SCM specific getter
  $INSTALLER_GET_SELF "${temporaryFile}"

  local nextVersion
  nextVersion=$(grep "^INSTALLER_VERSION" "${temporaryFile}" | awk -F'[="]' '{print $3}')
  local absScriptPath
  absScriptPath=$(readlink -f "${INSTALLER_SELF}")
  if [[ "$INSTALLER_VERSION" < "${nextVersion}" ]]; then
    printf "${LOG_PREFIX} [updater] Updating %s -> %s\n" "${INSTALLER_VERSION}" "${nextVersion}"

    {
      echo "cp \"${temporaryFile}\" \"${absScriptPath}\""
      echo "rm -f \"${temporaryFile}\""
      echo "echo ${LOG_PREFIX} [updater] Re-running updated script"
      echo "exec \"${absScriptPath}\" --skip-self-update $@"
    } >> updater.sh

    if ! bash ./updater.sh; then
      err "[updater] Failed to run update"
      exit 1
    fi
  else
    log "[updater] No update available"
    rm -f "${temporaryFile}"
    # continue, we are at the latest version
    INSTALLER_LATEST=1
  fi
}

#######################################
# Downloads self update from
# GitHub SCM.
# Arguments:
#   TBD
# Returns:
#   TBD
#######################################
# shellcheck disable=SC2317
function get_self_github()
{
  local output="$1"
  local selfURL="${INSTALLER_SELF_URL}"
  local defaultBranch="${INSTALLER_DEFAULT_BRANCH}"
  local token="${INSTALLER_CONFIG_TOKEN}"

  # shellcheck disable=SC2001
  selfURL=$(echo "$selfURL" | sed "s/#token#/$token/")

  # shellcheck disable=SC2001
  selfURL=$(echo "$selfURL" | sed "s/#branch#/$defaultBranch/")
  httpCode=$(curl_scm "${selfURL}" '' "${output}")
  if [[ "$INSTALLER_GET_SELF_STRICT" = 'true' ]]; then
    if [[ ${httpCode} -ne 200 ]] ; then
      err "[updater] Failed to download self update"
      exit 1
    fi
  fi
}

#######################################
# Downloads self update from web server with static content.
# GitHub SCM.
# Arguments:
#   TBD
# Returns:
#   TBD
#######################################
# shellcheck disable=SC2317
function get_self_plain()
{
  get_self_github "$1"
}

#######################################
# Downloads self update from
# Bitbucket Enterprise SCM.
# Arguments:
#   TBD
# Returns:
#   TBD
#######################################
# shellcheck disable=SC2317
function get_self_bitbucket_server()
{
  local output="$1"
  local selfURL="${INSTALLER_SELF_URL}"
  local defaultBranch="${INSTALLER_DEFAULT_BRANCH}"
  local token="${INSTALLER_CONFIG_TOKEN}"

  local bearerToken
  if [[ -z $token ]]; then
    bearerToken=""
  else
    bearerToken="Authorization: Bearer ${token}"
  fi

  local httpCode
  { read -d '' streamRefSpec; }< <(urlencode "refs/heads/${defaultBranch}")

  httpCode=$(curl_scm "${selfURL}?at=${streamRefSpec}" "${bearerToken}" "${output}")
  if [[ "$INSTALLER_GET_SELF_STRICT" = 'true' ]]; then
    if [[ ${httpCode} -ne 200 ]] ; then
      err "[updater] Failed to download self update"
      exit 1
    fi
  fi
}

#######################################
# Process arguments controlling the update process.
# Globals:
#  INSTALLER_UPDATED - return 1 if the update was suppressed manually or an actual update was done
# Arguments:
#  $# - script argunements
#######################################
function process_updater_arguments()
{
  # pre-process arguments
  local params
  params=
  while (( "$#" )); do
    case "$1" in
      --skip-self-update) # inhibit update before/after
        INSTALLER_UPDATED=1
        shift
        ;;
      -y|--yes) # skip ahead
        shift
        ;;
      --link) # skip ahead
        shift
        shift
        ;;
      --branch) # skip ahead
        shift
        shift
        ;;
      --stream) # skip ahead
        shift
        shift
        ;;
      --clone-options) # skip ahead
        shift
        shift
        ;;
      --fetch-all) # skip ahead
        shift
        ;;
      --use-local-config) # skip ahead
        shift
        ;;
      --git-quiet) # skip ahead
        shift
        ;;
      --prune) # skip ahead
        shift
        ;;
      --skip-dolast) # skip ahead
        shift
        ;;
      --) # end argument parsing
        shift
        break
        ;;
      -*|--*=) # unsupported options
        echo "Unsupported option '$1'" >&2
        exit 1
        ;;
      *) # preserve positional arguments
        params="${params} $1"
        shift
        ;;
    esac
  done
  # set positional arguments in their proper place
  eval set -- "${params}"
}

#######################################
# The update process. There are 2 phases fo execution, "run" or "update and re-run".
# Globals:
#  INSTALLER_SELF - location of script executing
# Arguments:
#  None
#######################################
INSTALLER_SELF="$(pwd)/installer.sh"
function updater()
{
  # globals for update
  INSTALLER_LATEST=0
  INSTALLER_UPDATED=0

  # remove previous updater script
  rm -f updater.sh

  # handle arguments controlling update
  process_updater_arguments "$@"

  # called externally by the user, try to update
  if [[ ${INSTALLER_UPDATED} == 0 ]]; then
    update "$@"
  fi

  # called internally after an update or we already at the latest version
  if [[ ${INSTALLER_LATEST} == 1 || ${INSTALLER_UPDATED} == 1  ]]; then
    main "$@"
  fi
}

updater "$@"

# make sure the script is fully loaded into memory
# https://stackoverflow.com/questions/2336977/can-a-shell-script-indicate-that-its-lines-be-loaded-into-memory-initially
exit
}
