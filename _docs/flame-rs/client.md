---
layout: docs
title: flame-rs Client Guide
description: Use flame_rs::client to connect to Flame, create sessions, submit Rust task payloads, and manage applications.
---

# flame-rs Client Guide

`flame_rs::client` is the Rust API for client-side Flame operations. It connects to the session manager, manages applications, creates sessions, submits tasks, watches task state, and closes sessions.

Use it for Rust applications and integration tools that call existing Flame services.

## Connect

Load client configuration and connect to Flame:

```rust
use flame_rs::{self as flame};
use flame_rs::apis::{FlameContext, FlameError};

#[tokio::main]
async fn main() -> Result<(), FlameError> {
    flame::apis::init_logger()?;

    let ctx = FlameContext::from_file_with_env(None)?;
    let current = ctx.get_current_context()?;
    let conn = flame::client::connect_with_tls(
        &current.cluster.endpoint,
        current.cluster.tls.as_ref(),
    )
    .await?;

    let apps = conn.list_application().await?;
    println!("applications: {}", apps.len());
    Ok(())
}
```

For plaintext local clusters, `connect("http://127.0.0.1:8080").await` is also available. Use `connect_with_tls()` for `https://` endpoints or explicit CA configuration.

## Create a Session

Create a session for a registered Flame application:

```rust
use flame_rs::client::SessionAttributes;

let session = conn
    .create_session(&SessionAttributes {
        id: "rust-client-demo".to_string(),
        application: "flmping".to_string(),
        common_data: None,
        min_instances: 0,
        max_instances: None,
        batch_size: 1,
        priority: 0,
        resreq: None,
    })
    .await?;
```

Use `open_session(&session_id, Some(&attrs)).await` when you want open-or-create behavior with spec validation.

## Run Tasks

Task input and output are byte payloads. The SDK aliases them as `TaskInput` and `TaskOutput`.

```rust
use std::sync::{Arc, Mutex};

use flame_rs::apis::{FlameError, TaskInput, TaskState};
use flame_rs::client::{Task, TaskInformer, TaskInformerPtr};

struct PrintInformer;

impl TaskInformer for PrintInformer {
    fn on_update(&mut self, task: Task) {
        if task.state == TaskState::Succeed {
            println!("task {} succeeded", task.id);
        }
    }

    fn on_error(&mut self, error: FlameError) {
        eprintln!("task error: {error}");
    }
}

let informer: TaskInformerPtr = Arc::new(Mutex::new(PrintInformer));
session
    .run_task(Some(TaskInput::from(b"hello".to_vec())), informer)
    .await?;
```

Use `create_task()` if you need the task ID before watching:

```rust
let task = session.create_task(None).await?;
let refreshed = session.get_task(&task.id).await?;
println!("{} {:?}", refreshed.id, refreshed.state);
```

Use `list_tasks()` to fetch the tasks currently known for a session.

## Close Sessions

Close a session through the session handle:

```rust
session.close().await?;
```

Or through the connection:

```rust
conn.close_session("rust-client-demo").await?;
```

## Resource Requirements

Request resources through `SessionAttributes.resreq`:

```rust
use flame_rs::client::{ResourceRequirement, SessionAttributes};

let attrs = SessionAttributes {
    id: "gpu-session".to_string(),
    application: "gpu-app".to_string(),
    common_data: None,
    min_instances: 0,
    max_instances: None,
    batch_size: 1,
    priority: 0,
    resreq: Some(ResourceRequirement::from("cpu=4,mem=16g,gpu=1")),
};
```

Memory strings support `k`, `m`, and `g` suffixes.

## Application Lifecycle

Register applications programmatically when a Rust tool owns the application lifecycle:

```rust
use std::collections::HashMap;

use flame_rs::client::ApplicationAttributes;

conn.register_application(
    "rust-echo".to_string(),
    ApplicationAttributes {
        shim: None,
        image: None,
        description: Some("Rust echo service".to_string()),
        labels: vec!["rust".to_string()],
        command: Some("/usr/local/flame/bin/rust-echo-service".to_string()),
        arguments: vec![],
        environments: HashMap::new(),
        working_directory: None,
        max_instances: None,
        delay_release: None,
        schema: None,
        url: None,
        installer: None,
    },
)
.await?;
```

For ordinary operations, `flmctl register --file app.yaml` is simpler and keeps deployment policy outside the client binary.

## Common Types

- `Connection`: client connection to the Flame session manager.
- `SessionAttributes`: session creation/opening spec.
- `Session`: session metadata plus task operations.
- `Task`: task metadata, state, input, output, and events.
- `TaskInformer`: callback trait for watched task updates.
- `ApplicationAttributes`: application registration spec.
- `ResourceRequirement`: CPU, memory, and GPU request.
- `FlameError`: SDK error type.

## Example

See the [Rust Pi client](https://github.com/xflops/flame/blob/main/examples/pi/rust/src/client.rs) for a complete client that creates a session, submits many tasks, aggregates task outputs, and closes the session.
