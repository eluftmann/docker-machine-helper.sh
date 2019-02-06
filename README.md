# docker-machine-helper.sh

This script is intended to speed up routine docker-machine activities during local development.
It lets you easily create and setup, SSH into and run docker CLI inside the machine with a single command.

The code was written with clarity and easy extensibility in mind so you are encouraged to customize it to your project's needs.


----


## Example usage

### Create and setup local machine

    $ ./docker-machine-helper.sh

With default configuration it will:

- Create and setup docker-machine instance with configured name (if it does not exist).
- Add script's base directory as shared folder mapped 1 <-> 1 (e.g. `/Users/user/project` will be accessible under `/Users/user/project` inside the virtual machine).
- Install Docker Compose.
- Disable swap memory.
- SSH into the machine and set default shared folder as current working directory.

Check the *Machine configuration* section in the source code for more details.

### Run docker command inside the machine

    $ ./docker-machine-helper.sh d [docker CLI command]

### Execute command inside the container

    $ ./docker-machine-helper.sh e <container_name> [command]

When `command` is not provided `/bin/bash` will be used by default.

### Display machine information

    $ ./docker-machine-helper.sh i

Display machine status, IP, memory and shared folders.
   
### Show complete list of commands

    $ ./docker-machine-helper.sh help


----


## Installation

1. Download `docker-machine-helper.sh` script to a desired location.

    ```sh
    $ curl -O https://raw.githubusercontent.com/eluftmann/docker-machine-helper.sh/master/docker-machine-helper.sh && chmod +x docker-machine-helper.sh
    ```

2. Edit and review *Machine configuration* variables inside the script's code.

    ```sh
    $ vi +/"readonly MACHINE_NAME=" docker-machine-helper.sh
    ```


### Optionally add shell shortcut method with auto-completion

Check `completion.bash` source code for details and customization. It defines additional method which acts as a CLI wrapper for multiple `docker-machine-helper.sh` scripts.

It lets you execute the script from nested directories and autocomplete running containers names when using `exec` / `e` command.
