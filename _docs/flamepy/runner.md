---
layout: docs
title: flamepy.app Guide
description: Package Python code and run functions and classes as remote Flame services.
---

# flamepy.app Guide

`flamepy.app` packages the current Python project, registers an application from the `flmrun` template, and exposes Python functions and classes as remote services. This page retains the old Runner URL for existing links; `flamepy.runner` is no longer in the current SDK.

## Prerequisites

Run a Flame cluster with a session manager, executor manager, object cache, and registered `flmrun` template. Install `flamepy` in the client environment and make application dependencies available to executors. Configure `FLAME_ENDPOINT` and `FLAME_CACHE_ENDPOINT` or `~/.flame/flame.yaml` as shown in [Getting Started](/docs/getting-started/).

## Remote Functions

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

Initialize the application before declaring services. Calling the decorated function directly executes it locally; `.remote()` submits a task and returns an `ObjectFuture`. Use `.get()` to fetch the result, `.wait()` to wait without fetching it, or `app.get()` to resolve a collection of futures. `app.destroy()` closes owned services and cleans up an application created by this process; an already existing application is reused and is not cleaned up by that process.

## Remote Classes

```python
import flamepy.app as app

app.init("counter-app")


@app.service(resreq="cpu=1,mem=1g")
class Counter:
    def __init__(self, start: int):
        self.value = start

    def increment(self, amount: int) -> int:
        self.value += amount
        return self.value


try:
    counter = Counter.remote(10)
    print(counter.increment(2).get())
finally:
    app.destroy()
```

A class proxy represents a service; executor processes retain its execution object across calls. Scheduling can use more than one executor, so do not assume all calls share a single in-memory object unless your session configuration ensures it. Set resource requirements and scheduling options on `@app.service()`. For grouped work, `batch_size` expresses the size of a gang; see the [App setup guide](https://github.com/xflops/flame/blob/main/docs/tutorials/app-setup.md) for current details.

## Packaging and Storage

App packages the current working directory into `dist/<name>.tar.gz`. Use `.flameignore` or `.flmignore` to exclude files. If `package.storage` is not configured, App uploads the package through the configured object cache. An explicit storage backend must be accessible to clients and executors.

Check `flmctl list --application` if the `flmrun` template cannot be found. See the upstream [App setup guide](https://github.com/xflops/flame/blob/main/docs/tutorials/app-setup.md) for configuration, data-aware scheduling, and troubleshooting.
