#!/usr/bin/env bash

# ============================================================================
# docker-machine-helper.sh shortcut
# ---------------------------------
#
# Copy the contents of this file into your `.bash_profile` / `.bashrc`
# or use the `source` instruction.
# ============================================================================

d() {
    local DIR=$(pwd -L)  # Use "pwd -P" to resolve symlinks
    local SCRIPT_NAME="docker-machine-helper.sh"

    while [[ ! -z ${DIR} ]] && [[ ! -f ${DIR}/${SCRIPT_NAME} ]]; do
        DIR="${DIR%\/*}"
    done

    if [[ -z ${DIR} ]]; then
        >&2 echo "Could not find `${SCRIPT_NAME}`"
        return 1
    fi

    ${DIR}/${SCRIPT_NAME} "${@:1}"
}

__d_completion() {
    complete_d() {
        # Add auto-completion for `exec` command only
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
