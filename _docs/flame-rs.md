---
layout: docs
title: flame-rs Guide
description: Use the Rust SDK for Flame clients, service applications, and lower-level typed API integrations.
---

# flame-rs Guide

`flame-rs` is the Rust SDK for Flame. The crate is named `flame-rs` in `Cargo.toml` and imported as `flame_rs` from Rust code.

Use `flame-rs` when you want a native Rust client, a Rust service binary managed by Flame, or a lower-level integration that works directly with Flame sessions, tasks, applications, and byte payloads.

## API Areas

| Module | Use it for | Typical user |
| --- | --- | --- |
| [`flame_rs::client`](/docs/flame-rs/client/) | Connecting to the session manager, managing applications, creating sessions, submitting tasks, and watching task state. | Rust application clients and integration tools. |
| [`flame_rs::service`](/docs/flame-rs/service/) | Implementing a Flame service binary with `FlameService` and running it under the Flame executor shim. | Teams deploying predefined Rust services. |
| `flame_rs::apis` | Shared types, configuration, errors, logging, TLS, and byte payload aliases. | SDK users who need typed access to Flame data structures. |

## Choosing an API

Choose `flame_rs::client` when your Rust program submits work to an existing Flame application:

```rust
use flame_rs::{self as flame};
use flame_rs::apis::FlameContext;

#[tokio::main]
async fn main() -> Result<(), flame_rs::apis::FlameError> {
    flame::apis::init_logger()?;

    let ctx = FlameContext::from_file_with_env(None)?;
    let current = ctx.get_current_context()?;
    let conn = flame::client::connect_with_tls(
        &current.cluster.endpoint,
        current.cluster.tls.as_ref(),
    )
    .await?;

    println!("connected to {}", current.cluster.endpoint);
    drop(conn);
    Ok(())
}
```

Choose `flame_rs::service` when you are building a Rust binary that Flame will launch as an application instance:

```rust
use flame_rs::{self as flame};
use flame_rs::apis::{FlameError, TaskOutput};
use flame_rs::service::{SessionContext, TaskContext};

struct EchoService;

#[tonic::async_trait]
impl flame::service::FlameService for EchoService {
    async fn on_session_enter(&self, _: SessionContext) -> Result<(), FlameError> {
        Ok(())
    }

    async fn on_task_invoke(&self, ctx: TaskContext) -> Result<Option<TaskOutput>, FlameError> {
        Ok(ctx.input)
    }

    async fn on_session_leave(&self) -> Result<(), FlameError> {
        Ok(())
    }
}
```

## Configuration

The Rust SDK reads the same client configuration file used by other Flame tools:

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

Use `FlameContext::from_file_with_env(None)` when you want `~/.flame/flame.yaml` plus environment overrides. Supported environment variables include:

- `FLAME_ENDPOINT`
- `FLAME_CACHE_ENDPOINT`
- `FLAME_CA_FILE`

Use `https://` endpoints with `FlameClientTls` or a `tls.ca_file` entry when the cluster requires TLS.

## Dependency

From inside the Flame source workspace, examples use the local SDK path:

```toml
[dependencies]
flame-rs = { path = "../../../sdk/rust" }
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
tonic = { version = "0.14", features = ["tls-ring"] }
```

When consuming Flame from another repository, point `flame-rs` at the Flame repository or the installation path your team publishes.

## Next

- Read the [`flame_rs::client` guide](/docs/flame-rs/client/) to create sessions and run tasks from Rust.
- Read the [`flame_rs::service` guide](/docs/flame-rs/service/) to implement a Rust Flame service.
- Browse the [Rust Pi example](https://github.com/xflops/flame/tree/main/examples/pi/rust).
