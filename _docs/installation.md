---
layout: docs
title: Installation Guide
description: Detailed instructions for installing Flame on bare metal or VMs using flmadm.
---

# Installation Guide

Flame is designed to run on bare metal servers or virtual machines. The primary tool for managing Flame installations is `flmadm`.

## Prerequisites

Before installing Flame, ensure your environment meets the following requirements:

- **Operating System**: Linux (Ubuntu 20.04+, CentOS 8+, etc.)
- **Root Privileges**: Required for system-wide installation and service management.
- **Dependencies**:
  - `curl` (for downloading scripts)
  - `git` (if building from source)
  - `rust` toolchain (version 1.70 or later)
  - `python3` & `pip` (for Python SDK)

## Installing flmadm

The `flmadm` tool is the administrator CLI for Flame.

### Build from Source

```bash
# Clone the repository
git clone https://github.com/xflops/flame.git
cd flame

# Build flmadm
cargo build --release -p flmadm

# Install to system path
sudo cp target/release/flmadm /usr/local/bin/
```

## Installing Flame Cluster

Once `flmadm` is installed, you can use it to install the Flame components.

### Single Node Installation (All-in-One)

For development or testing, you can install all components (Control Plane + Worker) on a single machine.

```bash
sudo flmadm install --all --enable
```

This command will:
1. Install all binaries to `/usr/local/flame/bin`.
2. Generate configuration files in `/usr/local/flame/conf`.
3. Create systemd services for `flame-session-manager` and `flame-executor-manager`.
4. Start and enable the services.

### Multi-Node Installation

For a production cluster, you should separate the Control Plane and Workers.

#### 1. Control Plane Node

On the machine designated as the Control Plane:

```bash
sudo flmadm install --control-plane --enable
```

#### 2. Worker Nodes

On each worker machine:

```bash
sudo flmadm install --worker --enable
```

### Client Installation

For machines that only need to submit jobs (no services running):

```bash
flmadm install --client --prefix ~/flame --no-systemd
```

> **Note**: After installation, add `export PATH=$PATH:~/flame/bin` to your shell profile (e.g., `~/.bashrc` or `~/.zshrc`) to make the client tools available in your terminal.

## Verifying Installation

After installation, check the status of the services:

```bash
# Check services
sudo systemctl status flame-session-manager
sudo systemctl status flame-executor-manager
```

You can also use `flmctl` to check the cluster status:

```bash
# Add flmctl to PATH if needed
export PATH=$PATH:/usr/local/flame/bin

# Check cluster status by listing sessions
flmctl list -s
```

## Troubleshooting

If you encounter issues during installation or verification, check the following:

### Common Issues

- **`flmadm: command not found`**: Ensure that `/usr/local/bin` is in your `$PATH`. You may need to add `export PATH=$PATH:/usr/local/bin` to your `.bashrc` or `.zshrc`.
- **Build Failures**: If `cargo build` fails, ensure you have the required build dependencies installed (e.g., `build-essential`, `libssl-dev`, `pkg-config`).
- **Service Failures**: If `systemctl status` shows services as `failed`, check the logs using `journalctl -u flame-session-manager` or `journalctl -u flame-executor-manager` for error details.

## Uninstallation

To remove Flame from your system:

```bash
# Uninstall with backup (default)
# Backups are stored in /var/backups/flame/ by default.
sudo flmadm uninstall

# Uninstall without backup (WARNING: This will permanently delete all data!)
sudo flmadm uninstall --no-backup --force
```
