---
layout: docs
title: Installation Guide
description: Install Flame with Docker Compose or flmadm profiles for control-plane, worker, cache, and client nodes.
---

# Installation Guide

Flame can run as a local Docker Compose cluster or as installed services on bare metal or virtual machines. `flmadm` is the administrator CLI for source builds, installation profiles, systemd services, and uninstall safety.

## Prerequisites

- Linux for systemd-based installations.
- Rust toolchain when building from source.
- Git when cloning from GitHub.
- `uv` for Python SDK installation.
- Root privileges for system-wide installs with systemd.

## Docker Compose

For first-time local use:

```bash
git clone https://github.com/xflops/flame.git
cd flame
docker compose up -d
docker compose exec flame-console /bin/bash
flmping
```

## Build flmadm

From the Flame source tree:

```bash
cargo build --release -p flmadm
sudo install -m 755 target/release/flmadm /usr/local/bin/
```

## Install Profiles

`flmadm install` requires at least one profile flag:

- `--all`: control plane, worker, cache, client tools, and Python SDK.
- `--control-plane`: `flame-session-manager`, `flmctl`, and `flmadm`.
- `--worker`: `flame-executor-manager`, built-in services, and `flamepy`.
- `--cache`: standalone `flame-object-cache`.
- `--client`: `flmctl`, `flmping`, `flmexec`, and `flamepy`.

Single-node installation:

```bash
sudo flmadm install --all --enable
source /usr/local/flame/sbin/flmenv.sh
```

Install from a local checkout:

```bash
sudo flmadm install --all --src-dir /path/to/flame --enable
```

Multi-node control plane:

```bash
sudo flmadm install --control-plane --enable
```

Worker with local cache:

```bash
sudo flmadm install --worker --cache --enable
```

Client-only machine:

```bash
flmadm install --client --prefix ~/flame --no-systemd
```

## Configuration

`flmadm` writes cluster configuration to:

```text
/usr/local/flame/conf/flame-cluster.yaml
```

A local development configuration includes the session endpoint, resource policy, executor shim, object cache endpoint, and cache storage:

```yaml
---
cluster:
  name: flame
  endpoint: "http://127.0.0.1:8080"
  resreq: "cpu=1,mem=2g"
  policies:
    - priority
    - drf
    - gang
  storage: "fs:///usr/local/flame/data"
  executors:
    shim: host
cache:
  endpoint: "grpc://127.0.0.1:9090"
  storage: "/usr/local/flame/data/cache"
```

Restart services after changing this file.

## Service Management

```bash
sudo systemctl status flame-session-manager
sudo systemctl status flame-executor-manager
sudo systemctl status flame-object-cache

sudo journalctl -u flame-session-manager -f
tail -f /usr/local/flame/logs/fsm.log
tail -f /usr/local/flame/logs/fem.log
```

Verify the cluster:

```bash
flmping
flmctl list --application
flmctl list --session
```

## Uninstall

Default uninstall creates a backup:

```bash
sudo flmadm uninstall
```

Complete removal without a backup:

```bash
sudo flmadm uninstall --no-backup --force
```

Preserve data and configuration:

```bash
sudo flmadm uninstall --preserve-data --preserve-config
```

## Troubleshooting

- If `flmadm` cannot build Flame, rerun with `--verbose` and inspect `/tmp/flame-install-build.log`.
- If services fail, check the matching `systemctl status`, `journalctl`, and `/usr/local/flame/logs/` files.
- If clients cannot connect, verify `FLAME_ENDPOINT`, `FLAME_CACHE_ENDPOINT`, and open ports `8080` and `9090`.
- If Runner cannot find `flmrun`, confirm `flmctl list --application` shows the built-in template.
