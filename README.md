# sixte — APISIX Plugin Testing Environment CLI

> [!CAUTION]
> **Standalone Mode Only**: This testing environment currently only supports running APISIX in standalone mode. Deployments using etcd are not supported.

`sixte` is an easy-to-use CLI tool designed to streamline the development and testing of Apache APISIX plugins, inspired by tools like Kong's Pongo. It provides an isolated, container-based testing environment using Docker and Docker Compose.

## Prerequisites

Before using `sixte`, ensure you have the following installed and running:

* **Docker**
* **Docker Compose**

## Installation

zsh or bash

```sh
export PATH="$PATH:~/.local/bin"
```

fish

```sh
set -gx PATH $PATH ~/.local/bin
```

Clone the repository and create a symlink to the `sixte.sh` script in `~/.local/bin`.

```bash
git clone https://github.com/smilepakawat/apisix-testing-environment.git
mkdir -p ~/.local/bin
ln -s $(realpath apisix-testing-environment/sixte.sh) ~/.local/bin/sixte
```

## Usage

```bash
sixte <command> [options]
```

Run this from your plugin project directory. The script discovers the framework's Docker assets via `SIXTE_HOME` (which defaults to the directory containing the script).

### Commands

* **`build`** - Build the APISIX test Docker image. Use `-f` or `--force` to build without cache.
* **`run`** - Run APISIX in standalone mode
* **`test`** - Run integration tests (`prove -r t/`) inside the container
* **`down`** - Stop and remove APISIX test environment
* **`restart`** - Restart the APISIX container (useful for code reloads)
* **`logs`** - Tail the APISIX container logs
* **`init`** - Initialise a new plugin project (creates the `plugins/` and `t/` directories along with configuration files)
* **`help`** - Show the help message

## Getting Started

1. **Initialize the Project Structure**:
   From your plugin project directory, run:

   ```bash
   sixte init
   ```

   This command creates the scaffolding needed for your plugins and tests:
   * `apisix/plugins/` — place your Lua plugins here
   * `t/` — place your `.t` test files here
   * `.editorconfig` — Editor configuration

2. **Build the Test Image**:
   If this is your first time, build the APISIX test Docker image:

   ```bash
   sixte build
   ```

3. **Run Integration Tests**:
   To execute the `prove` tests located in the `t/` directory:

   ```bash
   sixte test
   ```
