#!/usr/bin/env bash

# ============================================================================
# docker-machine-helper.sh shortcut
# ---------------------------------
#
# Copy the contents of this file into your `.bash_profile` / `.bashrc`
# or use the `source` instruction.
# ============================================================================

d() {
    local -r CURRENT_DIR=$(pwd -L)  # Use "pwd -P" to resolve symlinks
    local -r SCRIPT_NAME="docker-machine-helper.sh"

    download_script() {
        local -r URL="https://raw.githubusercontent.com/eluftmann/docker-machine-helper.sh/master/docker-machine-helper.sh"
        curl -s -o "${SCRIPT_NAME}" ${URL} && chmod +x "${SCRIPT_NAME}"
    }

    run_configuration_editor() {
        vi +/"readonly MACHINE_NAME=" "${SCRIPT_NAME}"
    }

    # Find script going from current directory up
    local DIR="${CURRENT_DIR}"
    while [[ ! -z ${DIR} ]] && [[ ! -f ${DIR}/${SCRIPT_NAME} ]]; do
        DIR="${DIR%\/*}"
    done

    if [[ -z ${DIR} ]]; then
        >&2 echo "Could not find '${SCRIPT_NAME}'"

        # If shell is running in interactive mode
        if [[ $- =~ i ]]; then
            read -r -n 1 -p "Do you want to download it into '${CURRENT_DIR}' and run configuration editor (y/N)? "
            echo
            [[ $REPLY =~ ^[Yy]$ ]] || return 1

            download_script && run_configuration_editor
            DIR="${CURRENT_DIR}"
        else
            return 1
        fi
    fi

    ${DIR}/${SCRIPT_NAME} "${@:1}"
}

__d_completion() {
    complete_d() {
        # Constrain auto-completion for `exec` command only
        if [[ ${COMP_WORDS[COMP_CWORD-1]} != "e" && ${COMP_WORDS[COMP_CWORD-1]} != "exec" ]]; then
            return
        fi

        local current_string=${COMP_WORDS[COMP_CWORD]}

        local containers_list=$(d docker ps --format "{{.Names}}" 2>/dev/null)
        if [[ -z ${containers_list} ]]; then
            return
        fi

        COMPREPLY=($(compgen -W '${containers_list[@]}' -- "$current_string"))
    }

    complete -F complete_d d
}

__d_completion
unset __d_completion
