#!/usr/bin/env bash
#
# This script is intended to speed up routine docker-machine activities
# during local development. It lets you easily create and setup,
# SSH into and run docker CLI inside the machine with a single command.
#
# Example usage:
#
# `./docker-machine-helper.sh`
#   Create and setup machine if it does not exist, SSH into after or when
#   already exists.
#
# `./docker-machine-helper.sh d [docker CLI command]`
#   Run [docker CLI command] inside the machine.
#
# `./docker-machine-helper.sh b [command]`
#   List containers/images and run [command] ('/usr/bin/env bash' when not provided) on selected one.
#
# `./docker-machine-helper.sh i`
#   Display machine information (status, IP, memory, shared folders, etc.).
#
# `./docker-machine-helper.sh help`
#   Show complete list of commands.
#
#
# !!! IMPORTANT !!!
# Please review 'Machine configuration' section below.
# Setting `MACHINE_NAME` variable is required to run the script.
#
# The code was written with clarity and easy extensibility in mind so you are
# encouraged to customize it to your project's needs.

set -o errexit
set -o nounset
#set -o xtrace

if [[ ${OSTYPE} != "darwin"* ]]; then
    echo "This script is intended to be used on macOS / OS X systems."
    echo "However, it should also work on other *nix systems."
    echo "Please check the source code of this script for details."

    exit 1
fi


# Get script's absolute directory path
# (required only to setup default shared directory and ssh command)
pushd $(dirname "${0}") > /dev/null
readonly BASE_DIR=$(pwd -L)  # Use "pwd -P" to resolve symlinks
popd > /dev/null


# ============================================================================
# Machine configuration
# ---------------------
#
#  MACHINE_NAME must be unique. Existing docker-machine instance can be used,
#    but then you will have to manually take care of the setup steps.
#
#  MACHINE_MEMORY is specified in MBs.
#
#  MACHINE_DISK_SIZE is specified in MBs.
#
#  MACHINE_DISABLE_SWAP set to true will disable SWAP with `swapoff -a`
#    command at boot time.
#
#  MACHINE_SHARED_DIRECTORIES array of absolute paths to shared directories.
#    Paths will be mapped 1 <-> 1, so e.g. `/Users/user/project` will be
#    accessible at the same path inside the machine. By default it is set to
#    this script's directory as it is intended to be used per-project.
#
#  MACHINE_DOCKER_COMPOSE_VERSION - set to empty string if you do not want to
#    auto-install docker-compose at boot time.
#
#  MACHINE_DIVE_VERSION - set to empty string if you do not want to
#    auto-install dive at boot time.
#    Project site: https://github.com/wagoodman/dive
#
#  MACHINE_DEFAULT_SSH_COMMAND - set to empty string if you want the default
#    behaviour of `docker-machine ssh` command.
# ============================================================================

readonly MACHINE_NAME=""  # Required
readonly MACHINE_MEMORY=1024  # 1 GB of RAM
readonly MACHINE_DISK_SIZE=$((1024 * 15))  # 15 GB of disk space
readonly MACHINE_DISABLE_SWAP=true
readonly MACHINE_SHARED_DIRECTORIES=(
    "${BASE_DIR}"
)
readonly MACHINE_DOCKER_COMPOSE_VERSION="1.24.1"
readonly MACHINE_DIVE_VERSION="0.8.1"
readonly MACHINE_DEFAULT_SSH_COMMAND="cd ${BASE_DIR}; exec \$SHELL --login"


# ============================================================================
# Internal configuration
# ----------------------
#
# You will not need to change these options in most cases.
# ============================================================================

# VBoxManage executable
readonly VBOX_MANAGE_BIN=$(command -v VBoxManage) || {
    >&2 echo "VBoxManage not found"
    exit 1
}

# docker-machine executable
readonly DOCKER_MACHINE_BIN=$(command -v docker-machine) || {
    >&2 echo "docker-machine not found"
    >&2 echo "Visit https://docs.docker.com/machine/install-machine/ for installation instructions"
    exit 1
}

# Boot2Docker bootlocal.sh script path
readonly BOOT2DOCKER_BOOTLOCAL="/var/lib/boot2docker/bootlocal.sh"

# Error codes
readonly ERR_MACHINE_NOT_SPECIFIED=64
readonly ERR_MACHINE_DOES_NOT_EXIST=65
readonly ERR_MACHINE_ALREADY_RUNNING=66
readonly ERR_MACHINE_NOT_RUNNING=67

# Setup output formatting if supported
readonly TAB='    '
if [[ -t 0 ]]; then
    readonly F_B=$(tput bold)
    readonly F_RED=$(tput setaf 1)
    readonly F_GREEN=$(tput setaf 2)
    readonly F_CYAN=$(tput setaf 6)
    readonly F_END=$(tput sgr0)
else
    readonly F_B=
    readonly F_RED=
    readonly F_GREEN=
    readonly F_CYAN=
    readonly F_END=
fi


# ============================================================================
# Main function
# ============================================================================

main() {
    local command=${1:-""}
    shift || true

    case ${command} in
        help|h|--help|-h) arg_help ;;

        "")       arg_ ;;
        bash|b)   arg_bash "${@:1}" ;;
        docker|d) arg_docker "${@:1}" ;;
        info|i)   arg_info ;;
        inspect)  arg_inspect ;;
        rm)       arg_rm ;;
        status)   arg_status ;;
        stop)     arg_stop ;;

        *) arg_help; return 1 ;;
    esac
}


# ============================================================================
# Command handlers
# ============================================================================

arg_() {
    if ! docker-machine::exists ${MACHINE_NAME}; then
        utils::echo-missing-resource "Machine '${MACHINE_NAME}' does not exist"

        utils::echo-header "Create machine"
        docker-machine::create ${MACHINE_NAME} ${MACHINE_MEMORY} ${MACHINE_DISK_SIZE}

        utils::echo-header "Stop machine"
        docker-machine::stop ${MACHINE_NAME}

        # Further steps require machine turned off

        utils::echo-header "Add shared directories"
        virtualbox::add-shared-folders ${MACHINE_NAME} ${MACHINE_SHARED_DIRECTORIES[@]}

        utils::echo-header "Start machine"
        docker-machine::start ${MACHINE_NAME}

        utils::echo-header "Create bootlocal.sh"
        docker-machine::create-bootlocal-script ${MACHINE_NAME}

        if [[ ${MACHINE_DISABLE_SWAP} = true ]]; then
            utils::echo-header "Disable swap"
            docker-machine::disable-swap ${MACHINE_NAME}
        fi

        utils::echo-header "Automount shared directories"
        docker-machine::automount-shared-folders ${MACHINE_NAME} ${MACHINE_SHARED_DIRECTORIES[@]}

        if [[ ! -z ${MACHINE_DOCKER_COMPOSE_VERSION} ]]; then
            utils::echo-header "Autoinstall docker-compose"
            docker-machine::autoinstall-docker-compose ${MACHINE_NAME} ${MACHINE_DOCKER_COMPOSE_VERSION}
        fi

        if [[ ! -z ${MACHINE_DIVE_VERSION} ]]; then
            utils::echo-header "Autoinstall dive"
            docker-machine::autoinstall-dive ${MACHINE_NAME} ${MACHINE_DIVE_VERSION}
        fi

        utils::echo-header "\`${BOOT2DOCKER_BOOTLOCAL}\` configuration"
        docker-machine::print-bootlocal-script ${MACHINE_NAME}
        echo

        utils::echo-header "Restart machine"
        docker-machine::restart ${MACHINE_NAME}
    fi

    if ! docker-machine::in-state ${MACHINE_NAME} "running"; then
        docker-machine::start ${MACHINE_NAME}
    fi

    docker-machine::ssh ${MACHINE_NAME} "${MACHINE_DEFAULT_SSH_COMMAND}"
}

arg_bash() {
    utils::assert-machine-exists ${MACHINE_NAME}

    local command="/usr/bin/env bash"
    if [[ $# -ge 1 ]]; then
        command="${@:1}"
    fi

    local -r docker_objects=$(IFS= docker-machine::exec ${MACHINE_NAME} "
        docker ps     --format '[CONTAINER] {{.Image}}\t({{.Names}})\t{{.Command}}' 2>/dev/null;
        docker images --format '[  IMAGE  ] {{.Repository}}:{{.Tag}}'               2>/dev/null;
    ")
    [[ -z ${docker_objects} ]] && { utils::echo-missing-resource "No available containers or images"; return 1; }

    # Prepare array of containers and images for select
    local options=()
    while read -r line; do options+=("${line}"); done < <(printf "%s\n" "${docker_objects}")

    utils::echo-header "Run '${command}'"
    select option in "${options[@]}"; do
        [[ -z ${option} ]] && return 1

        local container_name=$(echo "${option}" | cut -s -f 2 | sed 's/[()]//g')
        if [[ ! -z ${container_name} ]]; then
            docker-machine::exec-container ${MACHINE_NAME} ${container_name} ${command}
        else
            local image_name=$(echo "${option}" | cut -c 13-)
            docker-machine::run-image ${MACHINE_NAME} ${image_name} ${command}
        fi

        break
    done
}

arg_docker() {
    utils::assert-machine-exists ${MACHINE_NAME}

    docker-machine::exec ${MACHINE_NAME} "docker ${*:1}"
}

arg_info() {
    utils::assert-machine-exists ${MACHINE_NAME}

    docker-machine::print-info ${MACHINE_NAME}
    virtualbox::print-shared-folders ${MACHINE_NAME}
}

arg_inspect() {
    utils::assert-machine-exists ${MACHINE_NAME}

    docker-machine::inspect ${MACHINE_NAME}
}

arg_rm() {
    utils::assert-machine-exists ${MACHINE_NAME}

    docker-machine::remove ${MACHINE_NAME}
}

arg_status() {
    utils::assert-machine-exists ${MACHINE_NAME}

    docker-machine::state ${MACHINE_NAME}
}

arg_stop() {
    utils::assert-machine-exists ${MACHINE_NAME}

    docker-machine::stop ${MACHINE_NAME}
}

arg_help() {
    echo "Usage: ${0} [command] [arg...]"
    echo "       Run without arguments to initialize and ssh-into the machine"
    echo ""
    echo "Setup and run docker-machine."
    echo ""
    echo "Commands:"
    echo "    bash, b     List containers/images and run given command ('/usr/bin/env bash' by default) on selected one"
    echo "    docker, d   Run docker CLI"
    echo "    info, i     Get basic information about the machine"
    echo "    inspect     Inspect information about the machine"
    echo "    rm          Remove the machine"
    echo "    status      Get the status of the machine"
    echo "    stop        Stop the machine"
    echo "    help        Show a list of commands"
}


# ============================================================================
# Logging and other utilities
# ============================================================================

utils::echo-header() {
    echo "${F_B}===== ${1} =====${F_END}"
}

utils::echo-ok() {
    echo "[${F_GREEN}+${F_END}]" "${@:1}"
}

utils::echo-error() {
    >&2 echo "[${F_RED}!${F_END}]" "${@:1}"
}

utils::echo-missing-resource() {
    >&2 echo "[${F_RED}-${F_END}]" "${@:1}"
}

utils::assert-machine-exists() {
    local machine_name=${1}

    if ! docker-machine::exists ${machine_name}; then
        utils::echo-missing-resource "Machine '${machine_name}' does not exist"
        exit ${ERR_MACHINE_DOES_NOT_EXIST}
    fi
}


# ============================================================================
# docker-machine wrapper functions
# ============================================================================

docker-machine::list() {
    ${DOCKER_MACHINE_BIN} ls --filter "driver=virtualbox" --format "{{.Name}}"
}

docker-machine::exists() {
    local machine_name=${1}

    docker-machine::list | grep -q -m 1 -x ${machine_name}
}

docker-machine::inspect() {
    local machine_name=${1}

    ${DOCKER_MACHINE_BIN} inspect ${machine_name} "${@:2}"
}

docker-machine::state() {
    local machine_name=${1}

    ${DOCKER_MACHINE_BIN} status ${machine_name} 2>/dev/null | tr "[:upper:]" "[:lower:]"
}

docker-machine::in-state() {
    local machine_name=${1}
    local state=${2}

    docker-machine::state ${machine_name} | grep -q -E -i -x ${state}
}

docker-machine::create() {
    local machine_name=${1}
    local machine_memory=${2}
    local machine_disk_size=${3}

    ${DOCKER_MACHINE_BIN} create \
        --driver virtualbox \
        --virtualbox-memory ${machine_memory} \
        --virtualbox-disk-size ${machine_disk_size} \
        --virtualbox-no-share \
        ${machine_name}
}

docker-machine::remove() {
    local machine_name=${1}

    ${DOCKER_MACHINE_BIN} rm ${machine_name} --force
}

docker-machine::start() {
    local machine_name=${1}

    # docker-machine::in-state ${machine_name} "running" && return ${ERR_MACHINE_ALREADY_RUNNING}
    ${DOCKER_MACHINE_BIN} start ${machine_name}
}

docker-machine::stop() {
    local machine_name=${1}

    # docker-machine::in-state ${machine_name} "stopped" && return ${ERR_MACHINE_NOT_RUNNING}
    ${DOCKER_MACHINE_BIN} stop ${machine_name}
}

docker-machine::restart() {
    local machine_name=${1}

    ${DOCKER_MACHINE_BIN} restart ${machine_name}
}

docker-machine::ssh() {
    local machine_name=${1}
    local command=${2:-}

    if [[ -z ${command} ]]; then
        ${DOCKER_MACHINE_BIN} ssh ${machine_name}
    else
        ${DOCKER_MACHINE_BIN} ssh ${machine_name} -t ${command}
    fi
}

docker-machine::exec() {
    local machine_name=${1}
    local command=${2:-}

    ${DOCKER_MACHINE_BIN} ssh ${machine_name} ${command}
}


# ============================================================================
# docker-machine setup helper functions
# -------------------------------------
#
# Functions to setup docker-machine instance through bootlocal.sh script.
# bootlocal.sh is persistent and executed on every machine boot.
# ============================================================================

docker-machine::create-bootlocal-script() {
    local machine_name=${1}

    local result=0
    docker-machine::exec ${machine_name} "sudo ls ${BOOT2DOCKER_BOOTLOCAL}" > /dev/null 2>&1 || result=$?
    if [[ ${result} -ne 0 ]]; then
        docker-machine::exec ${machine_name} "sudo touch ${BOOT2DOCKER_BOOTLOCAL}"
        docker-machine::exec ${machine_name} "sudo chmod +x ${BOOT2DOCKER_BOOTLOCAL}"
        docker-machine::exec ${machine_name} "echo \"#!/usr/bin/env sh\" | sudo tee ${BOOT2DOCKER_BOOTLOCAL}" > /dev/null 2>&1
    fi
}

docker-machine::print-bootlocal-script() {
    local machine_name=${1}

    docker-machine::exec ${machine_name} "sudo cat ${BOOT2DOCKER_BOOTLOCAL}"
}

docker-machine::disable-swap() {
    local machine_name=${1}

    docker-machine::exec ${machine_name} "sudo sed -i '/ swap / s/^/#/' /etc/fstab"
    docker-machine::exec ${machine_name} "echo \"sysctl vm.swappiness=0\" | sudo tee -a ${BOOT2DOCKER_BOOTLOCAL}" > /dev/null 2>&1
    docker-machine::exec ${machine_name} "echo \"swapoff -a\" | sudo tee -a ${BOOT2DOCKER_BOOTLOCAL}" > /dev/null 2>&1
}

docker-machine::automount-shared-folders() {
    local machine_name=${1}
    local shared_folders_array=(${2})

    for shared_directory in ${shared_folders_array[*]}; do
        # Append only if the entry does not already exist in the bootlocal.sh
        local result=0
        docker-machine::exec ${machine_name} "sudo cat ${BOOT2DOCKER_BOOTLOCAL} | grep -E -i ${shared_directory}" > /dev/null 2>&1 || result=$?
        if [[ ${result} -ne 0 ]]; then
            docker-machine::exec ${machine_name} "echo \"mkdir -p ${shared_directory}\" | sudo tee -a ${BOOT2DOCKER_BOOTLOCAL}" > /dev/null 2>&1
            docker-machine::exec ${machine_name} "echo \"mount -t vboxsf -o defaults,uid=\`id -u docker\`,gid=\`id -g docker\` ${shared_directory} ${shared_directory}\" | sudo tee -a ${BOOT2DOCKER_BOOTLOCAL}" > /dev/null 2>&1
        fi
    done
}

docker-machine::autoinstall-docker-compose() {
    local machine_name=${1}
    local docker_compose_version=${2}
    local docker_compose_install_cmd="curl -L https://github.com/docker/compose/releases/download/${docker_compose_version}/docker-compose-\`uname -s\`-\`uname -m\` -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose"

    docker-machine::exec ${machine_name} "echo \"${docker_compose_install_cmd}\" | sudo tee -a ${BOOT2DOCKER_BOOTLOCAL}" > /dev/null 2>&1
}

docker-machine::autoinstall-dive() {
    local machine_name=${1}
    local dive_version=${2}
    local dive_tmp_file="/tmp/dive.rpm"
    local dive_install_cmd="wget -qO ${dive_tmp_file} https://github.com/wagoodman/dive/releases/download/v${dive_version}/dive_${dive_version}_linux_amd64.rpm && rpm -i ${dive_tmp_file} && rm ${dive_tmp_file}"

    docker-machine::exec ${machine_name} "echo \"${dive_install_cmd}\" | sudo tee -a ${BOOT2DOCKER_BOOTLOCAL}" > /dev/null 2>&1
}


# ============================================================================
# docker-machine helper functions
# ============================================================================

docker-machine::print-info() {
    local machine_name=${1}
    local machine_state=$(docker-machine::state ${machine_name})

    echo "${F_B}Name:${F_END} ${F_CYAN}${machine_name}${F_END}"

    case ${machine_state} in
        "running") echo "${F_B}State:${F_END} ${F_GREEN}running${F_END}" ;;
        "stopped") echo "${F_B}State:${F_END} ${F_RED}stopped${F_END}" ;;
        *)         echo "${F_B}State:${F_END} ${machine_state}" ;;
    esac

    if [[ ${machine_state} = "running" ]]; then
        echo "${F_B}IP:${F_END} `docker-machine::inspect ${machine_name} --format='{{.Driver.IPAddress}}'`"

        echo "${F_B}Memory:${F_END}"
        docker-machine::exec ${machine_name} "free -h" | sed "s/^/${TAB}/"
    else
        echo "${F_B}Memory:${F_END} `docker-machine::inspect ${machine_name} --format='{{.Driver.Memory}}'`M"
    fi
}

docker-machine::exec-container() {
    local machine_name=${1}
    local container_name=${2}
    local container_command=${@:3}

    local result=$(docker-machine::exec ${machine_name} "docker ps --format '{{.Names}}' --filter 'name=${container_name}'")
    [[ -z ${result} ]] && { utils::echo-missing-resource "Container '${container_name}' does not exist"; return 1; }

    docker-machine::ssh ${machine_name} "docker exec -it ${container_name} ${container_command}"
}

docker-machine::run-image() {
    local machine_name=${1}
    local image_name=${2}
    local image_command=${@:3}

    local volume_arguments=""
    if [[ ${#MACHINE_SHARED_DIRECTORIES[@]} -gt 0 ]]; then
        for d in "${MACHINE_SHARED_DIRECTORIES[@]}"; do
            volume_arguments+=" -v \"${d}\":\"${d}\" "
        done
    fi

    docker-machine::ssh ${machine_name} "docker run --rm -it ${volume_arguments} ${image_name} ${image_command}"
}


# ============================================================================
# VirtualBox helper functions
# ============================================================================

virtualbox::shared-folder-exists() {
    local machine_name=${1}
    local shared_directory=${2}

    ${VBOX_MANAGE_BIN} showvminfo ${machine_name} | grep ${shared_directory} > /dev/null 2>&1
}

virtualbox::add-shared-folders() {
    local machine_name=${1}
    local shared_directories_array=(${2})

    for shared_directory in ${shared_directories_array[*]}; do
        if ! virtualbox::shared-folder-exists ${machine_name} "${shared_directory}"; then
            local result=0
            ${VBOX_MANAGE_BIN} sharedfolder add ${machine_name} --name ${shared_directory} --hostpath ${shared_directory} --automount || result=$?
            if [[ ${result} -ne 0 ]]; then
                utils::echo-error "Failed to add shared folder \`${shared_directory}\`"
            else
                utils::echo-ok "Successfully added shared folder \`${shared_directory}\`"
            fi
        else
            utils::echo-ok "Shared folder \`${shared_directory}\` already exists"
        fi
    done
}

virtualbox::print-shared-folders() {
    local machine_name=${1}

    local SF_MOUNT_DIR=$(${VBOX_MANAGE_BIN} guestproperty get "${1}" "/VirtualBox/GuestAdd/SharedFolders/MountDir" 2>/dev/null | sed -e 's/No value set!/\/media/' -e 's/^Value: \([[:print:]]*\)$/\1/' | tr '\n' '\0')
    local SF_MOUNT_PREFIX=$(${VBOX_MANAGE_BIN} guestproperty get "${1}" "/VirtualBox/GuestAdd/SharedFolders/MountPrefix" 2>/dev/null | sed -e 's/No value set!/sf_/' -e 's/^Value: \([[:print:]]*\)$/\1/' | tr '\n' '\0')

    ${VBOX_MANAGE_BIN} showvminfo ${machine_name} 2>/dev/null | sed -n "
        /^Shared folders:[[:space:]]*$/ {
        "'
            i\'"
            ${F_B}Shared folders${F_END} (mount dir: ${F_B}${SF_MOUNT_DIR}${F_END}, mount prefix: ${F_B}${SF_MOUNT_PREFIX}${F_END})${F_B}:${F_END}
            :sf_loop
                n
                /^$/ b sf_loop
                s/^Name: '\([^,]*\)', Host path: '\([^,]*\)' \(.*\), \(.*\)/${TAB}${F_B}${F_CYAN}\1${F_END} -> ${F_CYAN}\2${F_END} (\4)/ p; b sf_loop
                # /^Name:/ p; b sf_loop
        }
    "
}


# ============================================================================
# Run main program function
# ============================================================================

if [[ -z ${MACHINE_NAME} ]]; then
    utils::echo-error "'MACHINE_NAME' not specified -- please check the script source for configuration"
    exit ${ERR_MACHINE_NOT_SPECIFIED}
else
    main "$@"
fi
