---
layout: docs
title: flamepy.runner Guide
description: Use flamepy.runner to package Python code and expose functions, classes, or instances as remote Flame services.
---

# flamepy.runner Guide

`flamepy.runner.Runner` packages the current Python project, registers a temporary Flame application, and exposes Python functions, classes, or instances as remote services.

Use Runner when you want to scale local Python code, generate service code dynamically, or submit task-oriented work without writing an application YAML or a dedicated service entrypoint.

## Requirements

- A running Flame cluster with session manager, executor manager, and object cache.
- A Python environment that can import `flamepy`.

## Configuration

Runner reads `~/.flame/flame.yaml` through `flamepy.core.FlameContext`:

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

`package.storage` is optional. If it is omitted, Runner uploads packages to the Flame object cache through `cache.endpoint`.

Supported package storage schemes:

- `grpc://` and `grpcs://`: Flame object cache storage.
- `file://`: shared filesystem storage.
- `http://` and `https://`: HTTP storage with PUT, GET, and DELETE support.

## Function Service

```python
from flamepy.runner import Runner


def sum_fn(a: int, b: int) -> int:
    return a + b


with Runner("sum-app") as runner:
    sum_service = runner.service(sum_fn)
    result = sum_service(1, 3)
    print(result.get())
```

Functions default to autoscaling sessions. Runner submits each call as a task and returns an `ObjectFuture`.

## Class or Instance Service

```python
from flamepy.runner import Runner


class Counter:
    def __init__(self, initial: int = 0):
        self._count = initial

    def add(self, value: int) -> int:
        self._count += value
        return self._count

    def get(self) -> int:
        return self._count


with Runner("counter-app") as runner:
    counter = runner.service(Counter(10), stateful=True, warmup=1)
    counter.add(1).wait()
    counter.add(3).wait()
    print(counter.get().get())
```

Classes and instances default to fixed sessions. Passing `warmup=N` with `autoscale=False` creates `N` fixed instances. Use `stateful=True` only with instances that need persistent in-service state.

## ObjectFuture Values

Remote calls return `ObjectFuture`. Passing an `ObjectFuture` into another remote call sends the underlying `ObjectRef` instead of fetching and re-uploading the object.

```python
from flamepy.runner import Runner


def double(value: int) -> int:
    return value * 2


def add(a: int, b: int) -> int:
    return a + b


with Runner("chain-app") as runner:
    double_service = runner.service(double)
    add_service = runner.service(add)

    first = double_service(21)
    total = add_service(first, 8)
    print(total.get())
```

Useful methods:

- `future.get()`: fetch and deserialize the result.
- `future.ref()`: return the underlying `ObjectRef`.
- `future.wait()`: wait without fetching the object.
- `runner.get(futures)`: resolve multiple futures.
- `runner.ref(futures)`: resolve multiple object references.
- `runner.wait(futures)`: wait for multiple futures.
- `runner.select(futures)`: iterate as futures complete.

## Shared Objects

Use `runner.put_object(obj)` when several remote calls should read the same large object:

```python
from flamepy.core import get_object
from flamepy.runner import Runner


def count_items(ref) -> int:
    data = get_object(ref)
    return len(data)


with Runner("shared-data-app") as runner:
    data_ref = runner.put_object(["a", "b", "c"])
    svc = runner.service(count_items)
    print(svc(data_ref).get())
```

The object lives in the Flame object cache under the Runner application scope.

## Resource Requests

Pass a `ResourceRequirement` when a service needs explicit resources:

```python
import flamepy
from flamepy.runner import Runner


with Runner("cpu-app") as runner:
    svc = runner.service(
        sum,
        resreq=flamepy.ResourceRequirement.from_string("cpu=1,mem=1g"),
    )
```

## Packaging

Runner packages the current working directory into `dist/<name>.tar.gz`.

Default exclusions include virtual environments, Python caches, `.git`, `node_modules`, bytecode files, and common test caches. Additional `package.excludes` patterns from `~/.flame/flame.yaml` are merged with those defaults.

## Advanced Template Configuration

Runner uses the standard built-in Runner template by default. Most users should not configure `runner.template`.

Only set `runner.template` when an administrator has registered a custom Runner application template:

```yaml
---
current-context: flame
contexts:
  - name: flame
    cluster:
      endpoint: "http://127.0.0.1:8080"
    cache:
      endpoint: "grpc://127.0.0.1:9090"
    runner:
      template: "custom-flmrun"
```

If you are debugging a cluster installation or a custom template, verify the template application explicitly:

```python
import flamepy

if flamepy.get_application("flmrun") is None:
    raise RuntimeError("flmrun application is not registered")
```

## Cleanup

Use Runner as a context manager where possible. On exit, Runner closes created services, removes cached objects for the Runner application, unregisters the temporary application, deletes uploaded package data, and removes the local package file.

If the application already existed before the Runner started, Runner reuses it and skips cleanup for that application.

## Troubleshooting

- `Failed to get application template 'flmrun'`: confirm the session manager is running and `flmrun` appears in `flmctl list --application`.
- `Storage not configured`: configure `cache.endpoint` or `package.storage`.
- `Storage directory does not exist`: for `file://` storage, create a shared directory visible to both clients and executors.
- Package upload or download failures: verify the selected storage backend is reachable from both client and executor nodes.
- Pickle or import errors: keep service functions and classes importable from the packaged project and install required Python dependencies on executor nodes.

## Upstream Reference

- [Runner setup tutorial](https://github.com/xflops/flame/blob/main/docs/tutorials/runner-setup.md)
- [Python Pi Runner example](https://github.com/xflops/flame/tree/main/examples/pi/python)
- [Replay buffer Runner example](https://github.com/xflops/flame/tree/main/examples/rl/replay_buffer)
