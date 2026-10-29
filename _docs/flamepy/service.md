---
layout: docs
title: flamepy.serving Guide
description: Build and call deployed Python services with flamepy.serving.
---

# flamepy.serving Guide

`flamepy.serving` provides a Python-object interface for a deployed Flame application. A service process defines an `Instance` and an entrypoint; a client creates or opens a session and sends requests to that entrypoint. It can be used for model serving, agents, and other long-lived services.

Serving serializes Python requests and responses with `cloudpickle`; optional session context is stored in the Flame object cache. Use compatible Python environments and dependencies on the client and executor. Only deserialize data from trusted sources: Python pickle serialization can execute code during deserialization.

## Define a Service

Save the following as `agent_service.py`. Its entrypoint accepts one positional-or-keyword argument:

```python
from flamepy import serving

instance = serving.Instance()


@instance.entrypoint
def answer(question: str) -> str:
    history = instance.context() or []
    history.append(question)
    instance.patch_context(history)
    return f"received {question}"


if __name__ == "__main__":
    instance.run()
```

`instance.run()` connects to Flame when started by an executor; without an executor endpoint it starts a local debug server. The entrypoint may be synchronous or asynchronous. A real model-serving entrypoint can initialize its model once in the service process and reuse it for requests handled by that process.

## Deploy the Service

With client access configured to the session manager and object cache, preview and deploy the script:

```bash
flmctl deploy --name agent-app --application ./agent_service.py --dry-run -o yaml
flmctl deploy --name agent-app --application ./agent_service.py
flmctl view --application agent-app
```

`flmctl deploy` packages the script, uploads it to the object cache, and registers the application. A standalone Python script runs with `python3` and does not install dependencies: the executors must already have `flamepy` and any other required packages. The session manager and executors must be able to reach the object cache. For project packaging, dependency installation, profiles, and CLI options, see [Deploy Applications](/docs/user-guide/#deploy-applications).

## Call the Service

After the application is registered as `agent-app`, create a session with initial context and submit requests:

```python
from flamepy.serving import open_session

with open_session("agent-app", ctx=[]) as session:
    print(session.run("hello"))
    future = session.submit("another request")
    print(future.result())
    print(session.context())
```

`run()` waits for the deserialized result; `submit()` returns a future. The context manager closes the session. To reopen an existing session, use `open_session(session_id=...)` instead of an application name. Set `resreq` when the session needs explicit CPU, memory, or GPU resources.

`instance.context()` reads the session's cached context, and `patch_context()` appends a new version when the session was created with context. It is not a transactional merge: coordinate concurrent updates when the application needs them. For large state or more control, use the [core object-cache API](/docs/flamepy/core/).

## Data-Aware Scheduling

A service can advertise data held by an executor using `instance.publish({key})` and withdraw keys with `instance.retract({key})` when the data is evicted. Clients can pass `TaskOptions(affinity={key})` to `session.run()` or `session.submit()` to express a preference for an executor advertising that key. Keys are bytes; the application defines their meaning and must keep advertisements consistent with its cache. Affinity is a scheduling preference, so a cache hit is not guaranteed.

For an inference example and measured comparison, see [Flame and vLLM serving](/blog/flame-vllm-serving/). For the API and data-aware scheduling examples, see the upstream [Python SDK guide](https://github.com/xflops/flame/blob/main/docs/sdk/python.md#use-the-serving-helper).

## Choosing an API

Use `flamepy.serving` when deploying and calling a named Python service. Use [`flamepy.app`](/docs/flamepy/app/) to package a local Python project and expose its functions or classes as remote services. Use [`flamepy.core`](/docs/flamepy/core/) for direct byte-level protocols. The former `flamepy.service` API is historical; see the [migration notes](/docs/migration/flamepy.service/).
