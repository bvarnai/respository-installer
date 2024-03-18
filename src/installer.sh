#!/bin/bash
{

# Constants
# Important: only single digits are supported due to lexical comparsion
# shellcheck disable=SC2034
declare INSTALLER_VERSION="2.7.5"
declare INSTALLER_SCRIPT_URL='https://ies-iesd-bitbucket.ies.mentorg.com/projects/VSB/repos/tools/raw'
declare INSTALLER_CONF_URL=''
declare INSTALLER_BOOTSTRAP_PROJECT='tools'

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
  echo "Install and setup project repositories."; \
  echo "Commands:"; \
  echo "  install [project...]  install a project(s) - default command -"; \
  echo "  list                  list available projects"; \
  echo "  update                update existing projects"; \
  echo "  help                  print help - this command -"; \
  echo "Options:"; \
  echo "      --skipInstallerUpdate       do not run self updater"; \
  echo "      --useLocal                  use local configuration and dependencies"; \
  echo "  -y, --yes                       say 'yes' to user questions"; \
  echo "      --link <target>             symlinked mode for shared workspace support (CI only)"; \
  echo "      --branch <branch>           project branch, if it exits on remote (fallback to branch in configuration)"; \
  echo "      --stream <branch>           development stream (defaults to master)"; \
  echo "      --configuration <branch>    deprecated use --stream instead"; \
  echo "      --cloneOptions <branch>     clone options (fallback to clone options in configuration)"; \
  echo "      --fetchAll                  fetch all remotes"; \
  echo ""; \
  echo "More information at <http://ies-iesd-conf.ies.mentorg.com:8090/x/su3LCw>" 1>&2; exit 1;
}

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
#   $3 - the project branch set/unset
#   $4 - the project branch
#   $5 - the clone options set/unset
#   $6 - the clone options
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
  if [[ -z "${VSB_CI}" ]]; then
    quite=""
  else
    quite="--quiet"
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
    link "${path}" "${linkTarget}/${path}"
  fi

  if [[ -d "${path}" ]]; then
    # project directory exists
    if git -C "${path}" rev-parse > /dev/null 2>&1; then
      log "Existing repository found, updating"
      pushd "${path}" > /dev/null || exit
      # set remote url
      if ! git remote set-url origin "${fetchURL}"; then
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
      refsArray=($configRefs)
      if [[ "${refsArray[*]}" =~ "*" ]]; then
        git config --unset-all "remote.origin.fetch"
        git config --add remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
      else
        if ! git config --get-regex remote.origin.fetch "refs/heads/${branch}" > /dev/null 2>&1; then
          if ! git config --add remote.origin.fetch "+refs/heads/${branch}:refs/remotes/origin/${branch}" > /dev/null 2>&1; then
            err "Unable to add fetch refspec entry"
            exit 1
          fi
        fi
      fi

      # prune explicitly on CI
      local prune
      if [[ -z "${VSB_CI}" ]]; then
        prune=""
      else
        prune="--prune"
      fi

      log "Branch '${branch}' is selected"
      if [[ "${fetchAll}" == 1 ]]; then
        if ! git fetch --all "${prune}" $quite; then
          err "Unable to fetch remote"
          exit 1
        fi
      else
        if ! git fetch origin "${branch}" "${prune}" $quite; then
          err "Unable to fetch remote"
          exit 1
        fi
      fi

      if ! git checkout "${branch}"; then
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
  doLast "${configuration}"
}

#######################################
# Sets git configuration setting from the configuration.
# Arguments:
#   None
# Returns:
#   None
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

  log "Setting git config(s)"
  local gitConfigs
  gitConfigs=$(echo "${configuration}" | "${JQ}" -r ".configuration[]?")
  pushd "${path}" > /dev/null || exit
  while IFS= read -r gitConfig; do
    # split string by whitespace to key-value pairs
    # shellcheck disable=SC2206
    local keyValue=($gitConfig)
    if ! git config --local "${keyValue[0]}" "${keyValue[1]}"; then
      err "Unable to set local git configuration"
      popd > /dev/null || exit
      exit 1
    fi
  done <<< "${gitConfigs}"
  popd > /dev/null || exit
}

#######################################
# Executes doLast commands from the configuration.
# Arguments:
#   None
# Returns:
#   None
#######################################
function doLast()
{
  if [[ -z "${VSB_CI}" ]]; then
    local configuration="$1"
    local project
    project=$(echo "${configuration}" | "${JQ}" -r '.name')

    local path
    path=$(echo "${configuration}" | "${JQ}" -r ".path?")
    if [[ "${path}" == "null" ]]; then
      path="${project}"
    fi

    log "Running doLast command(s)"
    local commands
    commands=$(echo "${configuration}" | "${JQ}" -r ".doLast[]?")
    pushd "${path}" > /dev/null || exit
    while IFS= read -r command; do
      local trimmedCommand=$(echo "${command}" | xargs)
      if ! $trimmedCommand; then
        err "Failed to execute doLast command"
        popd > /dev/null || exit
        exit 1
      fi
    done <<< "${commands}"
    popd > /dev/null || exit
  else
    log "Skipping installation/modification of globals in CI mode"
  fi
}

#######################################
# Gets consent from the user that changes at risk.
# Arguments:
#   None
# Returns:
#   None
#######################################
function precondition_user_confirm_uncommited()
{
  # user already said yes?
  if [[ $1 == 0 ]]; then
    log "Existing project repositories might be reset depending on the configuration"
    while true; do
      read -r -p "Uncommited changes could be at risk, do you want to continue? (y/n)" yn
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
#   None
# Returns:
#   None
#######################################
function urlencode() {
  # urlencode <string>
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
# Downloads the stream configuration from remote SCM.
# credits https://gist.github.com/cdown/1163649
# Arguments:
#   None
# Returns:
#   None
#######################################
function get_stream_configuration()
{
  local streamBranchSet="$1"
  local streamBranch="$2"
  local configurationURL="${INSTALLER_CONF_URL}/projects.json"
  log "Getting stream configuration..."
  if [[ "${stream_branch_set}" == 1 ]]; then
    { read -d '' streamRefSpec; }< <(urlencode "refs/heads/${stream_branch}")
    # it's not possible to check remote branch here
    # as no git reposiory available yet, just try to fetch the file
    local httpCode
    httpCode=$(curl -s -k --write-out "%{http_code}" -# "${configurationURL}?at=${streamRefSpec}" -o "projects.json")
    if [[ ${httpCode} -ne 200 ]] ; then
      err "Stream branch doesn't exists"
      exit 1
    else
      # success
      log "Stream branch '${stream_branch}' is selected"
      return
    fi
  fi
  if ! curl -s -k -L -# "${configurationURL}" -o "projects.json"; then
    err "Failed to download stream configuration"
    exit 1
  fi
  log "Stream branch 'default' is selected"
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
# Downloads the JQ tool binary from local SCM.
# Arguments:
#   None
# Returns:
#   None
#######################################
function get_jq()
{
  if [[ ! -f "${JQ}" ]]; then
    # download it
    local jqURL="https://ies-iesd-bitbucket.ies.mentorg.com/projects/VSB/repos/tools/raw/bin/${JQFileSource}"
    log "Getting jq..."
    if ! curl -k -s -L -# "${jqURL}" -o "${JQFileName}" --create-dirs; then
      err "Failed to download jq binary"
      exit 1
    fi
  fi
}

#######################################
# Checks if we are running in the tools project folder. This was the old way.
# Arguments:
#   None
# Returns:
#   None
#######################################
function precondition_in_tools()
{
  local dir
  dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  if [[ $(basename "${dir}") == "tools" ]]; then
    err "It seems you are running in 'tools' folder..."
    err "Due to compatibility reasons, please run the script from the parent folder."
    exit 1
  fi
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
# Set JQ file name depending on OS type.
# jq for linux
# jq.exe for windows
# Arguments:
#   None
# Returns:
#   JQFileName - JQ file name
#######################################
function set_jq_file_name()
{
  if [[ $(uname -s) == "Linux" ]]; then
      JQFileSource='linux/jq'
      JQFileName='.installer/jq'
  else
      JQFileSource='jq.exe'
      JQFileName='.installer/jq.exe'
  fi
}
#######################################
# Set JQ binary location.
# Arguments:
#   None
# Returns:
#   JQ - jq binary location
#######################################
function set_jq_location()
{
  set_jq_file_name
  # JQ binary location is configurable
  if [[ -f "${VSB_TOOLS_HOME}/bin/${JQFileName}" ]]; then
    # use local binary
    JQ="${VSB_TOOLS_HOME}/bin/${JQFileName}"
  else
    JQ="./${JQFileName}"
  fi
}

#######################################
# Set JQ binary executable permission.
# Arguments:
#   None
# Returns:
#   None
#######################################
function set_jq_permission() {
  if [[ $(uname -s) == "Linux" ]]; then
    # try to set executable permission (it's curled)
    chmod +x "${JQ}" > /dev/null 2>&1;
  fi
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
  git config --unset-all "remote.origin.fetch"
  refsArray=($configRefs)
  for ref in "${refs_array[@]}"; do
    remoteBranchName=${ref#*+refs/heads/}
    remoteBranchName=${remoteBranchName%:*}
    # # first check if remote branch exists on remote?
    if git ls-remote --exit-code origin "refs/heads/${remoteBranchName}" > /dev/null 2>&1; then
        if [[ $remoteBranchName=="*" ]]; then
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
  local _local
  local fetchAll
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
  _local=0
  fetchAll=0
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
      --cloneOptions)
        cloneOptionsSet=1
        shift
        cloneOptions="$1"
        shift
        ;;
      --skipInstallerUpdate) # do nothing just silently ignore
        shift
        ;;
      --useLocal) # use local copy of configuration and dependencies
        _local=1
        shift
        ;;
      --fetchAll) # fetch all refs not only the specified branch
        fetchAll=1
        shift
        ;;
      -y|--yes) # no questions will be asked
        yes=1
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
  precondition_in_tools
  if [[ -z "${VSB_CI}" ]]; then
    precondition_nested_repository
  fi

  set_jq_location

  # update if needed
  if [[ "${_local}" == "0" ]]; then

    # update stream configuration
    get_stream_configuration "${streamBranchSet}" "${streamBranch}"

    # get jq executable (external dependency)
    get_jq
  else
    log "Using local copy of the configuration and dependencies (might be out-of-date)"
  fi

  set_jq_permission

  # some environment information (also fail fast...)
  log "jq version $("${JQ}" --version)"
  log "$(git --version)"

  # list projects
  if [[ ${list} == 1 ]]; then
    log "Available projects:"
    list_projects
    exit 0
  fi

  # getting dangerous from here
  precondition_user_confirm_uncommited "${yes}"

  # disable SSL verification
  if [[ -z "${VSB_CI}" ]]; then
    log "Disabling SSL certification validation globally to support self-signed certificates"
    if ! git config --global http.sslVerify false; then
      err "Failed to disable SSL certification validation"
      exit 1
    fi
  fi

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
    projectNamesArray=($projectNames)
  else
    # projects specified by exsiting projects in the workspace
    log "Searching for existing projects in the workspace"

    if [[ -z "$VSB_TOOLS_HOME" ]]; then
      err "Environment variable 'VSB_TOOLS_HOME' is not specified"
      exit 1
    fi

    local workspace
    if [[ $(uname -s) == "Linux" ]]; then
      workspace="$VSB_TOOLS_HOME/.."
    else
      workspace=$(cygpath -u "$VSB_TOOLS_HOME/..")
    fi

    if [[ ! -d "$workspace" ]]; then
      err "Workspace directory '$workspace' is not valid"
      exit 1
    fi

    projectNames=()
    local projectNamePredicates
    projectNamePredicates=$( find "$workspace" -maxdepth 1 -type d -printf '%P '  | xargs echo )
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

  local bootstrapProjectAdded=0
  # project order can affect doLast scripts
  local orderedProjects=false
  # is there a user project selection?
  if [[ "${#projectNamesArray[@]}" != "0" ]]; then
    for projectName in "${projectNamesArray[@]}"
    do
      project_exists "${projectName}"
      if [[ "${LAST_RETURN}" == "0" ]]; then
          # user selected project is not found
          err "Project '${projectName}' is undefined"
          log "Hint: Check your project(s) configuration"
          exit 1
      fi
      if [[ "${projectName}" == "tools" ]]; then
        bootstrapProjectAdded=1
      fi
    done

    # check if we are in CI mode or not, if not add the mandatory projects
    if [[ -z "$VSB_CI" ]]; then
      # make sure mandatory 'tools' project is added
      if [[ "${toolsProjectAdded}" == 0 ]]; then
        log "Adding project 'tools' implicitly"
        # add to the beginning of the array
        projectNamesArray=("tools" "${projectNamesArray[@]}")
      fi

      # make sure mandatory 'tools-deps' project is added
      if [[ "${toolsDepsProjectAdded}" == 0 ]]; then
        # add to the beginning of the array
        if [[ $(uname -s) == "Linux" ]]; then
          log "Adding project 'tools-deps-linux' implicitly"
          projectNamesArray=("tools-deps-linux" "${projectNamesArray[@]}")
        else
          log "Adding project 'tools-deps' implicitly"
          projectNamesArray=("tools-deps" "${projectNamesArray[@]}")
        fi
      fi
    fi

  else
    log "No projects were specified by the user, adding default projects"
    # no user project selection, add all 'default' projects from the configuration
    readarray -t projectNamesArray < <("${JQ}" -r '.projects[] | select(.default=="true") | .name' projects.json)

    # project order retained from the configuration file
    orderedProjects=true

    # check if we are in CI mode or not, if not add the mandatory projects which are not set default
    if [[ -z "$VSB_CI" ]]; then
      # tools-deps is platform specific
      # add to the beginning of the array
      if [[ $(uname -s) == "Linux" ]]; then
        log "Adding project 'tools-deps-linux' implicitly"
        projectNamesArray=("tools-deps-linux" "${projectNamesArray[@]}")
      else
        log "Adding project 'tools-deps' implicitly"
        projectNamesArray=("tools-deps" "${projectNamesArray[@]}")
      fi

      # we changed the order, need to sort
      orderedProjects=false
    fi
  fi

  # only sort when not running in CI mode (CI scripts should list projects correctly)
  if [[ -z "$VSB_CI" ]]; then
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
  fi

  # allow remote branch refs
  project_branch=${project_branch/"remotes/origin/"/""}

  # install projects
  for projectName in "${projectNamesArray[@]}"
  do
    # trim name
    projectName=$(echo "${projectName}" | xargs)
    find_project_by_name "${projectName}"
    install_project "${LAST_RETURN}" "${project_branch_set}" "${project_branch}" "${clone_options_set}" "${clone_options}" "${fetch_all}"
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

    printf "%-20s (category: %-11s, default: %-5s, path: %s)\n" "${currentProjectConfigurationArray[0]}" "${currentProjectConfigurationArray[1]}" "${currentProjectConfigurationArray[2]}" "${currentProjectPath}"
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
  LAST_RETURN=0
  local projectName="$1"

  local projectConfiguration
  projectConfiguration=$("${JQ}" -r ".projects[] | select(.name == \"${projectName}\")" projects.json)
  if [[ ! -z "${projectConfiguration}" ]]; then
    LAST_RETURN="${projectConfiguration}"
  fi
}

#######################################
# Checks project in configuration file by name;
# Globals:
#  LAST_RETURN - "1" if project exsits, "0" otherwise
# Arguments:
#  $1 - project name
#######################################
function project_exists()
{
  LAST_RETURN=0
  local projectName="$1"

  local projectConfiguration
  projectConfiguration=$("${JQ}" -r ".projects[] | select(.name == \"${projectName}\")" projects.json)
  if [[ ! -z "${projectConfiguration}" ]]; then
    LAST_RETURN=1
  fi
}

#######################################
# Self-update; credits https://gist.github.com/cubedtear/54434fc66439fc4e04e28bd658189701
# Globals:
#  LATEST - returns 1 if the script is at the lastest version; 0 otherwise
# Arguments:
#  None
#######################################
function update()
{
  log "[updater] Checking for updates..."
  local temporaryFile
  temporaryFile=$(mktemp -p "" "XXXXX.sh")

  local scriptURL="${INSTALLER_SCRIPT_URL}/installer.sh"
  if ! curl -s -k -L -# "${scriptURL}" > "${temporaryFile}"; then
    err "[updater] Failed to download updates"
    exit 1
  fi

  local nextVersion
  nextVersion=$(grep "^VERSION" "${temporaryFile}" | awk -F'[="]' '{print $3}')
  local absScriptPath
  absScriptPath=$(readlink -f "${SCRIPT_LOCATION}")
  if [[ "$VERSION" < "${nextVersion}" ]]; then
    printf "${LOG_PREFIX} [updater] Updating \e[31;1m%s\e[0m -> \e[32;1m%s\e[0m\n" "${VERSION}" "${nextVersion}"

    {
      echo "cp \"${temporaryFile}\" \"${absScriptPath}\""
      echo "rm -f \"${temporaryFile}\""
      echo "echo [updater] Re-running updated script"
      echo "exec \"${absScriptPath}\" --skipInstallerUpdate $@"
    } >> updater.sh

    bash ./updater.sh
  else
    log "[updater] No update available"
    rm -f "${temporaryFile}"
    # continue, we are at the latest version
    LATEST=1
  fi
}

#######################################
# Process arguments controlling the update process.
# Globals:
#  UPDATED - return 1 if the update was suppressed manually or an actual update was done
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
      --skipInstallerUpdate) # inhibit update before/after
        UPDATED=1
        shift
        ;;
      -y|--yes) # skip ahead
        shift
        ;;
      --useLocal) # skip ahead
        shift
        ;;
      -s|--ssh) # skip ahead
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
      --configuration) # skip ahead
        shift
        shift
        ;;
      --cloneOptions) # skip ahead
        shift
        shift
        ;;
      --fetchAll) # skip ahead
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
#  SCRIPT_LOCATION - location of script executing
# Arguments:
#  None
#######################################
SCRIPT_LOCATION="$(pwd)/installer.sh"
function updater()
{
  # globals for update
  LATEST=0
  UPDATED=0

  # remove previous updater script
  rm -f updater.sh

  # handle arguments controlling update
  process_updater_arguments "$@"

  # called externally by the user, try to update
  if [[ ${UPDATED} == 0 ]]; then
    update "$@"
  fi

  # called internally after an update or we already at the latest version
  if [[ ${LATEST} == 1 || ${UPDATED} == 1  ]]; then
    main "$@"
  fi
}

updater "$@"

# make sure the script is fully loaded into memory
# https://stackoverflow.com/questions/2336977/can-a-shell-script-indicate-that-its-lines-be-loaded-into-memory-initially
exit
}
