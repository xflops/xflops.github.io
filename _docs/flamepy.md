---
layout: docs
title: FlamePy Guide
description: Use FlamePy to build Python applications on Flame, from high-level Runner services to lower-level service and core APIs.
---

# FlamePy Guide

FlamePy is the Python SDK for Flame. It lets Python programs create Flame sessions, submit work, host service entrypoints, share objects through the Flame object cache, and package local Python code as distributed services.

Most task-oriented Python applications should start with `flamepy.runner`. Use `flamepy.service` when services are predefined, versioned, deployed, and managed by an administrator. Use `flamepy.core` when you need low-level APIs for integrations or third-party libraries.

## API Layers

| Module | Use it for | Typical user |
| --- | --- | --- |
| [`flamepy.runner`](/docs/flamepy/runner/) | Packaging local code or dynamic service code and exposing functions, classes, or instances as task-oriented remote services. | Python users scaling local code and submitting distributed tasks with minimal Flame boilerplate. |
| [`flamepy.service`](/docs/flamepy/service/) | Calling predefined service applications and writing service entrypoints for administrator-managed deployment. | Teams where an admin manages service registration, deployment, versions, and runtime policy. |
| [`flamepy.core`](/docs/flamepy/core/) | Working directly with sessions, tasks, applications, watchers, resource requests, and cached objects. | Integration authors and library builders who need low-level Flame APIs. |

## Choosing an API

Choose `flamepy.runner` when your application starts as ordinary Python code, dynamic service code, or task-oriented local logic:

```python
from flamepy.runner import Runner


def score(x: int) -> int:
    return x * x


with Runner("score-app") as runner:
    score_service = runner.service(score)
    print(score_service(7).get())
```

Choose `flamepy.service` when the service has a stable application name, a dedicated service process, a typed request/response boundary, and an administrator-managed deployment lifecycle:

```python
from dataclasses import dataclass
from flamepy import service


@dataclass
class Request:
    text: str


ins = service.FlameInstance()


@ins.entrypoint
def handle(req: Request) -> str:
    return req.text.upper()


if __name__ == "__main__":
    ins.run()
```

Choose `flamepy.core` when you are building an integration or third-party library and need direct control over bytes, sessions, tasks, or cached object references:

```python
from flamepy.core import create_session


session = create_session("byte-service")
future = session.run(b"payload")
print(future.result())
session.close()
```

## Configuration

FlamePy reads the same client configuration across these layers. The simplest local setup uses environment variables:

```bash
export FLAME_ENDPOINT=http://127.0.0.1:8080
export FLAME_CACHE_ENDPOINT=grpc://127.0.0.1:9090
```

For persistent configuration, use `~/.flame/flame.yaml`:

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
      template: "flmrun"
```

`flamepy.runner` also uses the `package` section when deciding where to upload application packages.

## Next

- Read [`flamepy.runner`](/docs/flamepy/runner/) for the fastest path from Python functions to distributed services.
- Read [`flamepy.service`](/docs/flamepy/service/) for explicit service applications.
- Read [`flamepy.core`](/docs/flamepy/core/) for lower-level integration and cache APIs.
