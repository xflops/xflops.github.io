---
layout: docs
title: Getting Started with Flame
description: Start a local Flame cluster, verify it with flmping, and run your first Python service.
---

# Getting Started with Flame

This guide follows the current Flame quick start: Docker Compose for the first local cluster, then `flmadm` for local source or systemd-based installs.

## Prerequisites

- Docker Compose for the quickest path.
- Rust, Git, Python, and `uv` if you build and install from source with `flmadm`.

## Option 1: Docker Compose

Clone Flame and start the local cluster:

```bash
git clone https://github.com/xflops/flame.git
cd flame
docker compose up -d
```

Open a shell in the console container:

```bash
docker compose exec flame-console /bin/bash
```

Verify the cluster:

```bash
flmping
flmctl list --session
flmctl list --application
```

The built-in applications should include `flmping`, `flmexec`, and `flmrun`.

## Option 2: Local flmadm Install

From a Flame source checkout:

```bash
cargo build --release -p flmadm
sudo install -m 755 target/release/flmadm /usr/local/bin/
sudo flmadm install --all --src-dir . --enable
source /usr/local/flame/sbin/flmenv.sh
```

For more installation profiles and multi-node layouts, see the [Installation Guide](/docs/installation/).

## Client Configuration

Python clients can use environment variables:

```bash
export FLAME_ENDPOINT=http://127.0.0.1:8080
export FLAME_CACHE_ENDPOINT=grpc://127.0.0.1:9090
```

Flame clients can also read `~/.flame/flame.yaml`:

```yaml
---
current-context: flame
contexts:
  - name: flame
    cluster:
      endpoint: "http://127.0.0.1:8080"
    cache:
      endpoint: "grpc://127.0.0.1:9090"
    package:
      excludes:
        - "*.log"
        - "*.pkl"
        - "*.tmp"
```

These plaintext endpoints are for local development. Configure TLS for deployments that require encrypted, authenticated connections.

When `package.storage` is absent, App uploads packages to the Flame object cache through `cache.endpoint`.

## First Python Service

Install the SDK from the Flame checkout you intend to use, configure the endpoints above, and verify that the built-in `flmrun` application is registered. For example, from the Flame checkout:

```bash
python -m pip install -e ./sdk/python
```

App packages the current working directory, so create a separate project directory for this example and run it from there.

Create `hello_app.py`:

```python
import flamepy.app as app

app.init("hello-app")


@app.service()
def hello(name: str) -> str:
    return f"hello, {name}"


try:
    print(hello.remote("flame").get())
finally:
    app.destroy()
```

```bash
python hello_app.py
```

## Next Steps

- Read the [`flamepy.app` Guide](/docs/flamepy/runner/) for functions, classes, futures, and package storage.
- Read the [flamepy Guide](/docs/flamepy/) for the Python SDK overview.
- Read the [flame-rs Guide](/docs/flame-rs/) for Rust clients and service binaries.
- Read the [User Guide](/docs/user-guide/) for `flmctl`, application registration, and cluster operations.
- Browse the [Flame examples](https://github.com/xflops/flame/tree/main/examples).
