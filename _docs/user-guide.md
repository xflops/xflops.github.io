---
layout: docs
title: User Guide
description: Comprehensive guide for using Flame effectively on bare metal.
---

# User Guide

This guide covers how to configure, manage, and monitor Flame on bare metal environments using `flmadm` and `flmctl`.

## Table of Contents

1. [Configuration](#configuration)
2. [Cluster Management](#cluster-management)
3. [Workload Management](#workload-management)
4. [Monitoring](#monitoring)
5. [Troubleshooting](#troubleshooting)

## Configuration

Flame uses a TOML-based configuration file located at `/usr/local/flame/conf/flm.conf`.

### Basic Configuration

```toml
[common]
# Unique identifier for the node
node_id = "node-01"

[session_manager]
# Port for the Session Manager service
port = 8080

[executor_manager]
# Port for the Executor Manager service
port = 9090
# Maximum number of concurrent tasks
max_tasks = 10
```

To apply changes, restart the services:

```bash
sudo systemctl restart flame-session-manager
sudo systemctl restart flame-executor-manager
```

## Cluster Management

Use `flmadm` to manage the cluster nodes.

### Adding a Node

To add a new worker node to the cluster:

1. Install Flame on the new node (see [Installation Guide](installation.md)).
2. Configure the `flm.conf` to point to the Session Manager.
3. Start the `flame-executor-manager` service.

### Checking Cluster Status

Use `flmctl` to view the status of all nodes:

```bash
flmctl get nodes
```

## Workload Management

Flame workloads are submitted using the `flmctl` CLI or the Python SDK.

### Submitting a Task

Create a task definition file `task.json`:

```json
{
  "name": "my-task",
  "image": "python:3.9",
  "command": "python script.py",
  "resources": {
    "cpu": 2,
    "memory": "4Gi"
  }
}
```

Submit the task:

```bash
flmctl submit task.json
```

### Listing Tasks

```bash
flmctl get tasks
```

### Viewing Task Logs

```bash
flmctl logs <task-id>
```

## Monitoring

Flame services log to systemd journal.

### Service Logs

View Session Manager logs:
```bash
journalctl -u flame-session-manager -f
```

View Executor Manager logs:
```bash
journalctl -u flame-executor-manager -f
```

## Troubleshooting

### Common Issues

- **Service fails to start**: Check configuration file syntax.
- **Task stuck in PENDING**: Check if there are enough resources (CPU/Memory) available on worker nodes.
