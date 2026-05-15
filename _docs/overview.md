---
layout: docs
title: XFLOPS/Flame Overview
description: Flame is a distributed engine for AI workloads, agents, reinforcement learning, and other elastic task-heavy systems.
---

# Flame Overview

Flame is a distributed engine for AI workloads. It provides the runtime pieces commonly needed by agents, reinforcement learning, generated-code execution, and other elastic workloads: sessions, task scheduling, executor reuse, object caching, secure runtime isolation, and multi-language service integration.

## Why Flame

AI applications often create many short tasks rather than a single long-running batch job. Flame gives those tasks a shared execution model:

- **Scale**: Run work across multiple nodes while sharing resources fairly across tenants and sessions.
- **Performance**: Reuse executors inside a session to reduce cold starts and improve throughput.
- **Security**: Isolate session runtime environments and use mTLS between Flame components.
- **Flexibility**: Integrate services through gRPC and shims, with Rust, Go, Python, and other application code.

## Core Concepts

- **Session**: A group of related tasks with scheduling and isolation boundaries. Clients can submit tasks until the session is closed.
- **Task**: A unit of work submitted to a session.
- **Executor**: A runtime environment that hosts application services for one session.
- **Shim**: The protocol adapter used by an executor to manage an application service.
- **Object cache**: Shared storage for common data, Runner packages, Runner contexts, and incremental object updates.

## Architecture

![Flame architecture](/images/flame-arch.jpg)

Flame accepts client requests through the session manager, schedules session resources, and has executors connect back over gRPC to pull and run tasks. Services can react to session bind and unbind events, reuse data while the session is active, and release resources when the session closes.

## Quick Start Paths

1. Use Docker Compose for a first local cluster.
2. Use `flmadm install --all --enable` for a local or single-node systemd installation.
3. Use `flmadm` profiles for multi-node deployments: `--control-plane`, `--worker`, `--cache`, and `--client`.
4. Use `flamepy.runner.Runner` to turn Python functions, classes, or instances into remote services.

## Getting Help

- Issues: [github.com/xflops/flame/issues](https://github.com/xflops/flame/issues)
- Community: [https://xflops.slack.com](https://xflops.slack.com)
- Email: [support@xflops.io](mailto:support@xflops.io)

## Next

Start with [Getting Started](/docs/getting-started/), then read the [FlamePy Guide](/docs/flamepy/) for Python APIs and service examples.
