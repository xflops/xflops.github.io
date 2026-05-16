---
layout: docs
title: flamepy.core Guide
description: Use flamepy.core for direct Flame sessions, tasks, application registration, resource requirements, and object-cache references.
---

# flamepy.core Guide

`flamepy.core` is the lower-level Python API for Flame. It exposes the direct client model: connect to the session manager, register applications, create sessions, submit byte payloads as tasks, watch task state, and share cached objects with `ObjectRef`.

Use this layer when you are building integrations, custom service protocols, advanced workflows, or third-party libraries that need more control than `flamepy.runner` or `flamepy.service`.

## Configuration

Most callers can let `flamepy.core` create a connection from `FlameContext`:

```bash
export FLAME_ENDPOINT=http://127.0.0.1:8080
export FLAME_CACHE_ENDPOINT=grpc://127.0.0.1:9090
```

Or use `~/.flame/flame.yaml`:

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

For explicit connections:

```python
from flamepy.core import connect


conn = connect("http://127.0.0.1:8080")
```

## Sessions and Tasks

Core sessions work with bytes. Higher-level APIs such as `flamepy.service` add Python object serialization on top.

```python
from flamepy.core import create_session


session = create_session("byte-service")
try:
    future = session.run(b"hello")
    output = future.result()
    print(output)
finally:
    session.close()
```

Use `invoke()` for a synchronous one-shot call:

```python
from flamepy.core import create_session


session = create_session("byte-service")
try:
    output = session.invoke(b"hello")
finally:
    session.close()
```

## Watch Task State

Use `create_task()`, `watch_task()`, and `get_task()` when you need task metadata or progress events:

```python
from flamepy.core import TaskState, create_session


session = create_session("byte-service")
try:
    task = session.create_task(b"payload")

    for update in session.watch_task(task.id):
        print(update.id, update.state)
        if update.state in (TaskState.SUCCEED, TaskState.FAILED):
            break

    completed = session.get_task(task.id)
    print(completed.output)
finally:
    session.close()
```

`session.list_tasks()` returns an iterator over tasks in that session.

## Open and Close Sessions

```python
from flamepy.core import close_session, open_session


session = open_session("byte-service-a1b2c3")
print(session.application, session.state)
close_session(session.id)
```

`open_session(session_id, spec=...)` can create a session if it does not exist and a compatible `SessionAttributes` spec is provided.

## Resource Requirements

Use `ResourceRequirement` to request CPU, memory, or GPU resources for sessions:

```python
from flamepy.core import ResourceRequirement, create_session


resreq = ResourceRequirement.from_string("cpu=4,mem=16g,gpu=1")
session = create_session("gpu-service", resreq=resreq)
```

Memory strings support `k`, `m`, and `g` suffixes.

## Application Registration

Register applications programmatically when tooling needs to manage app lifecycle:

```python
from flamepy.core import ApplicationAttributes, register_application, unregister_application


register_application(
    "byte-service",
    ApplicationAttributes(
        working_directory="/opt/examples/byte-service",
        command="/usr/bin/python",
        arguments=["service.py"],
        environments={"FLAME_LOG_LEVEL": "INFO"},
    ),
)

try:
    # create sessions and run tasks
    pass
finally:
    unregister_application("byte-service")
```

For ordinary operations, `flmctl register --file app.yaml` is often simpler.

## Object Cache

The object cache stores Python objects and returns `ObjectRef` handles. Keys use the `<application>/<session>` prefix format.

```python
from flamepy.core import get_object, put_object, update_object


ref = put_object("training/shared", {"epoch": 0, "loss": 1.0})
print(get_object(ref))

ref = update_object(ref, {"epoch": 1, "loss": 0.8})
print(get_object(ref))
```

Set `ref.version = 0` before `get_object(ref)` to force a fresh full read instead of using the client-side cache.

## Patch Objects

Use `patch_object()` for append-heavy structures where writers should send deltas instead of replacing the full object:

```python
from flamepy.core import get_object, patch_object, put_object


def merge_batches(base, deltas):
    merged = list(base)
    for delta in deltas:
        merged.extend(delta)
    return merged


ref = put_object("replay/shared", [])
ref = patch_object(ref, [{"obs": 1, "reward": 0.5}])
ref = patch_object(ref, [{"obs": 2, "reward": 1.0}])

print(get_object(ref, deserializer=merge_batches))
```

Without a `deserializer`, `get_object(ref)` returns the base object for backward compatibility. With a deserializer, flamepy combines the base object and patch list into the materialized value.

## Common Types

- `SessionState`, `TaskState`, and `ApplicationState`: lifecycle enums.
- `Task`: task metadata, input/output bytes, completion time, and events.
- `Application`: registered application metadata.
- `SessionAttributes`: session creation/opening spec.
- `ApplicationAttributes`: application registration spec.
- `TaskInformer`: callback interface for task update integrations.
- `FlameError`: SDK exception with a `FlameErrorCode`.

## Higher-Level APIs

Use [`flamepy.service`](/docs/flamepy/service/) if your core payloads are Python objects handled by a typed, administrator-managed service entrypoint. Use [`flamepy.runner`](/docs/flamepy/runner/) if you want flamepy to package and register task-oriented Python code automatically.
