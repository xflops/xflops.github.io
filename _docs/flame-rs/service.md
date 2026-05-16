---
layout: docs
title: flame-rs Service Guide
description: Use flame_rs::service to implement Rust Flame service binaries managed by the executor shim.
---

# flame-rs Service Guide

`flame_rs::service` is the Rust service-side API. A Rust service implements the `FlameService` trait and calls `flame_rs::service::run()` from its binary entrypoint.

Use it for predefined Rust services that are built, deployed, registered, and versioned as Flame applications.

## Implement a Service

Service implementations receive session lifecycle callbacks and task invocations:

```rust
use flame_rs::{self as flame};
use flame_rs::apis::{FlameError, TaskOutput};
use flame_rs::service::{SessionContext, TaskContext};

struct EchoService;

#[tonic::async_trait]
impl flame::service::FlameService for EchoService {
    async fn on_session_enter(&self, ctx: SessionContext) -> Result<(), FlameError> {
        tracing::debug!("session {} entered", ctx.session_id);
        Ok(())
    }

    async fn on_task_invoke(&self, ctx: TaskContext) -> Result<Option<TaskOutput>, FlameError> {
        Ok(ctx.input)
    }

    async fn on_session_leave(&self) -> Result<(), FlameError> {
        tracing::debug!("session left");
        Ok(())
    }
}
```

Task input and output are byte payloads. Define your own encoding for request and response data, such as JSON, bincode, protobuf, or a compact binary format.

## Run the Service

Call `service::run()` from an async main:

```rust
use flame_rs::{self as flame};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    flame::apis::init_logger()?;
    flame::service::run(EchoService).await?;
    Ok(())
}
```

When Flame launches the service, the executor shim provides `FLAME_INSTANCE_ENDPOINT`. The Rust SDK binds a Unix domain socket at that path and serves the Flame instance protocol over gRPC.

The service runtime currently requires Unix domain socket support.

## Register the Application

Register the built service binary as a Flame application:

```yaml
metadata:
  name: rust-echo
spec:
  command: /usr/local/flame/bin/rust-echo-service
  environments:
    RUST_LOG: info
```

Then register it:

```bash
flmctl register --file rust-echo.yaml
flmctl list --application
```

An administrator usually owns this step for production services, including binary installation, application versioning, resource policy, and rollout.

## Cargo Setup

From the Flame source workspace, examples depend on the local SDK:

```toml
[dependencies]
flame-rs = { path = "../../../sdk/rust" }
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
tonic = { version = "0.14", features = ["tls-ring"] }
tracing = "0.1"
```

The Rust Pi example defines separate service and client binaries:

```toml
[[bin]]
name = "pi-service"
path = "src/service.rs"

[[bin]]
name = "pi"
path = "src/client.rs"
```

## Build and Deploy

A typical source build produces the service binary with Cargo:

```bash
cargo build --release -p pi
sudo install -m 755 target/release/pi-service /usr/local/flame/bin/
flmctl register --file examples/pi/rust/pi-app.yaml
```

The exact install path should match the `spec.command` path in the application YAML.

## Session Context

`SessionContext` includes:

- `session_id`: active Flame session ID.
- `application`: application name, image, and command metadata.
- `common_data`: optional session common data bytes.

Use `on_session_enter()` to initialize state for a bound service instance. Use `on_session_leave()` to release resources when the session unbinds.

## Task Context

`TaskContext` includes:

- `task_id`: task ID.
- `session_id`: owning session ID.
- `input`: optional task input bytes.

Return `Ok(Some(TaskOutput::from(bytes)))` when the task produces output, `Ok(None)` when it does not, and `Err(FlameError::...)` when the task should fail.

## Complete Example

See the [Rust Pi service](https://github.com/xflops/flame/blob/main/examples/pi/rust/src/service.rs), which implements `FlameService`, decodes a task input count, estimates Monte Carlo hits, and returns the hit count as bytes.
