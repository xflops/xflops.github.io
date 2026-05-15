---
layout: docs
title: flamepy.service Guide
description: Use flamepy.service to build typed Flame service processes and call them from Python clients.
---

# flamepy.service Guide

`flamepy.service` is the typed Python service layer. A service process uses `FlameInstance` to register one entrypoint, and a client uses `Session` to create or open a Flame session and invoke that entrypoint with Python objects.

Use this layer when the application is a named Flame service that is predefined, deployed, versioned, and managed by an administrator.

## Service Process

Define request and response types, create a `FlameInstance`, and decorate one entrypoint:

```python
# echo_service.py
from dataclasses import dataclass
from flamepy import service


@dataclass
class EchoRequest:
    text: str


@dataclass
class EchoResponse:
    text: str
    count: int


ins = service.FlameInstance()


@ins.entrypoint
def echo(req: EchoRequest) -> EchoResponse:
    history = ins.context() or []
    history.append(req.text)
    ins.update_context(history)
    return EchoResponse(text=req.text.upper(), count=len(history))


if __name__ == "__main__":
    ins.run()
```

Entrypoints must take zero or one positional-or-keyword parameter. The entrypoint can be synchronous or `async`. Inputs and outputs are serialized with `cloudpickle`, so request and response classes must be importable in the service environment.

## Client Session

Create a session with the registered application name and call `invoke()`:

```python
# client.py
from echo_service import EchoRequest
from flamepy.service import Session


with Session("echo-app", ctx=[]) as session:
    response = session.invoke(EchoRequest("hello"))
    print(response.text)
    print(response.count)
    print(session.id())
```

`Session(name, ctx=...)` creates a new Flame session. `ctx` is optional shared session data and is stored through the Flame object cache. `session.context()` reads the current shared context, and `session.close()` closes the underlying Flame session.

## Open an Existing Session

Pass `session_id` instead of `name` to reconnect to an existing session:

```python
from flamepy.service import Session


session = Session(session_id="echo-app-a1b2c3")
try:
    print(session.context())
finally:
    session.close()
```

`name` and `session_id` are mutually exclusive.

## Resource Requirements

Use `resreq` when each service instance needs explicit resources:

```python
from flamepy.service import Session


with Session(
    "echo-app",
    resreq={"cpu": 2, "memory": "4g", "gpu": 0},
) as session:
    print(session.invoke("ping"))
```

You can also import `flamepy` and pass `flamepy.ResourceRequirement.from_string("cpu=2,mem=4g")`.

## Application Registration

Unlike `flamepy.runner`, the service layer does not package and register the application for you. Register the service with `flmctl` or the lower-level `flamepy.core.register_application` API.

A simple application spec can point Flame to the Python service process:

```yaml
metadata:
  name: echo-app
spec:
  working_directory: /opt/examples/echo
  command: /usr/bin/python
  arguments:
    - echo_service.py
  environments:
    FLAME_LOG_LEVEL: INFO
```

Register it:

```bash
flmctl register --file echo-app.yaml
flmctl list --application
```

## Session Context

Service context is useful for agents, crawlers, and applications that reuse state across many tasks in the same session.

On the client:

```python
with Session("agent-app", ctx={"messages": []}) as session:
    answer = session.invoke("what changed?")
    print(session.context())
```

In the service:

```python
state = ins.context() or {"messages": []}
state["messages"].append("handled one task")
ins.update_context(state)
```

For large or frequently updated state, consider storing the main data explicitly with `flamepy.core.put_object`, `update_object`, or `patch_object` and passing `ObjectRef` values through requests.

## When to Use Runner Instead

Use [`flamepy.runner`](/docs/flamepy/runner/) if you want FlamePy to package the current project, register a temporary application, and expose Python functions or classes directly. Use `flamepy.service` when deployment, registration, versions, and application identity are managed as part of the service contract.

## Related Examples

- [Crawler example](https://github.com/xflops/flame/tree/main/examples/crawler)
- [OpenAI agent example](https://github.com/xflops/flame/tree/main/examples/agents/openai)
- [LangChain agent example](https://github.com/xflops/flame/tree/main/examples/agents/langchain)
