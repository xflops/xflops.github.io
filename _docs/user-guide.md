---
layout: docs
title: User Guide
description: Use flmctl, register applications, configure clients, and operate Flame sessions.
---

# Flame User Guide

This guide covers day-to-day Flame usage after a cluster is running.

## CLI Tools

Flame has two primary command-line tools:

- `flmctl`: user-facing CLI for applications, sessions, tasks, executors, and nodes.
- `flmadm`: administrator CLI for installation, service setup, upgrades, and uninstall.

## List Cluster Objects

```bash
flmctl list --application
flmctl list --session
flmctl list --executor
flmctl list --node
```

Short flags are also supported:

```bash
flmctl list -a
flmctl list -s
flmctl list -e
flmctl list -n
```

## View Details

```bash
flmctl view --application flmping
flmctl view --session <session-id>
flmctl view --task <task-id>
flmctl view --node <node-name>
```

Use `--output-format yaml` when you need structured output.

## Create and Close Sessions

Create a session for a registered application:

```bash
flmctl create --app flmping --batch-size 1 --priority 0
```

Pass a resource request when the workload needs explicit resources:

```bash
flmctl create --app flmping --resreq cpu=1,mem=1g
```

Close a session:

```bash
flmctl close --session <session-id>
```

## Register Applications

Register an application from YAML:

```bash
flmctl register --file app.yaml
```

Update or unregister it:

```bash
flmctl update --application app.yaml
flmctl unregister --application <app-name>
```

Most Python users should start with [Runner](/docs/runner/), which packages the current project and registers a temporary application from the built-in `flmrun` template.

## Client Configuration

Use environment variables for simple local clients:

```bash
export FLAME_ENDPOINT=http://127.0.0.1:8080
export FLAME_CACHE_ENDPOINT=grpc://127.0.0.1:9090
```

Use `~/.flame/flame.yaml` for persistent context-based configuration:

```yaml
---
current-context: flame
contexts:
  - name: flame
    cluster:
      endpoint: "http://127.0.0.1:8080"
    cache:
      endpoint: "grpc://127.0.0.1:9090"
```

## Cluster Configuration

Installed clusters use:

```text
/usr/local/flame/conf/flame-cluster.yaml
```

Important fields include:

- `cluster.endpoint`: session manager endpoint.
- `cluster.resreq`: default task resource request.
- `cluster.policies`: scheduler policy list.
- `cluster.executors.shim`: executor shim selection.
- `cache.endpoint`: object cache endpoint.
- `cache.storage`: object cache storage path.

Restart Flame services after changing cluster configuration.

## Troubleshooting

Services do not start:

```bash
sudo systemctl status flame-session-manager
sudo systemctl status flame-executor-manager
sudo systemctl status flame-object-cache
sudo journalctl -u flame-session-manager -n 50
```

Client cannot connect:

```bash
flmping
flmctl list --application
```

Then verify `FLAME_ENDPOINT`, `FLAME_CACHE_ENDPOINT`, and network access to ports `8080` and `9090`.

Runner cannot start services:

```bash
flmctl list --application
```

Confirm the `flmrun` template appears. If not, check that the session manager started with the expected installation prefix and configuration.
