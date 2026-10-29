---
layout: docs
title: flamepy Guide
description: Build Python applications with Flame using the App and core APIs.
---

# flamepy Guide

flamepy is the Python SDK for Flame. It provides distributed Python services, lower-level sessions and tasks, and APIs for agents and model serving.

| Module | Use it for |
| --- | --- |
| [`flamepy.app`](/docs/flamepy/app/) | Package a Python project and run functions and classes as remote services. |
| [`flamepy.core`](/docs/flamepy/core/) | Work directly with applications, sessions, byte tasks, and cached objects. |
| [`flamepy.agent`](/docs/flamepy/agent/) | Run agent workloads using Flame sessions and sandboxes. |
| [`flamepy.serving`](/docs/flamepy/service/) | Deploy and call Python services, including model serving and agents. |

The former `flamepy.runner` and `flamepy.service` modules are not part of the current SDK. For application code, start with `flamepy.app`; for a custom service protocol use `flamepy.core`. See the [migration notes](/docs/migration/flamepy.service/).

## First Service

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

App uses the configured session manager and object cache and packages the current working directory. See [Getting Started](/docs/getting-started/) for configuration and [`flamepy.app`](/docs/flamepy/app/) for lifecycle and packaging details.

For direct byte tasks, use [`flamepy.core`](/docs/flamepy/core/). The endpoint examples in these guides use plaintext for local development; configure TLS for deployments that require encrypted, authenticated connections.
