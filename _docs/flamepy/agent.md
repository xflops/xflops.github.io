---
layout: docs
title: flamepy.agent Guide
description: Run agent code with Flame sandboxes and sessions.
---

# flamepy.agent Guide

`flamepy.agent` runs shell commands and Python code through Flame's `flmbox` application. Use `Sandbox` for a single bound environment with a filesystem shared across calls, and `Session` to submit code as tasks that can be scheduled across executors.

## Prerequisites

Configure the Flame client endpoint, and make sure the cluster has the `flmbox` application and its sandbox runtime available. The sandbox image and its dependencies must be available to the workers. See [Getting Started](/docs/getting-started/) for client configuration and the [flmbox documentation](https://github.com/xflops/flame/tree/main/flmbox) for runtime setup.

Sandbox isolation and network access depend on the deployment. The built-in `flmbox` configuration uses host networking; configure the runtime and network policy for the trust level of the code you run.

## Persistent Sandbox

A sandbox binds one executor and can retain files across commands while its environment remains available:

```python
from flamepy import agent

with agent.Sandbox.create() as sandbox:
    result = sandbox.run("mkdir -p /tmp/demo && echo hello > /tmp/demo/message")
    if not result.ok:
        raise RuntimeError(result.stderr_text())

    result = sandbox.run_code(
        "from pathlib import Path; print(Path('/tmp/demo/message').read_text())",
        language="python",
    )
    if not result.ok:
        raise RuntimeError(result.stderr_text())
    print(result.stdout_text())
```

`run()` executes shell commands; `run_code()` supports Python and shell. Results include `exit_code`, `stdout`, and `stderr`, and a nonzero exit is returned as a result rather than raised automatically. `submit()` and `submit_code()` return futures. Use `Sandbox.connect(sandbox_id)` to attach to an existing sandbox, and close it when finished.

A sandbox can be suspended and resumed, but resuming starts a fresh environment: process and filesystem state are not preserved. Worker loss or session closure can also remove transient state; store important data externally.

## Session Tasks

An agent session can submit multiple code tasks without requiring a single persistent sandbox:

```python
from flamepy import agent

with agent.open_session(max_instances=2) as session:
    futures = [
        session.submit_code(f"print({number} * {number})", language="python")
        for number in range(4)
    ]
    for future in futures:
        result = future.result()
        if not result.ok:
            raise RuntimeError(result.stderr_text())
        print(result.stdout_text())
```

`run_code()` waits for one result; `submit_code()` returns a future. Tasks can run on different executors, so do not rely on a shared local filesystem between calls. `max_instances` limits the session's executor count; actual parallelism depends on available cluster resources. Use `agent.open_session(ssn_id=...)` to open or create a named session; existing sessions retain their original creation options.

For a practical integration and in-cluster measurements, see [Hermes with Flame](/blog/hermes-flamepy/).
