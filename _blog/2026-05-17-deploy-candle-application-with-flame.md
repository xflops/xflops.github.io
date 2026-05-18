---
layout: blog
title: "Deploy a Candle Application with Flame"
date: 2026-05-17
author: "Klaus Ma"
description: "A walkthrough of the Candle Based Rust example in Flame, showing that the main code change is wrapping local inference in a Flame service macro, while flmctl deploy handles packaging and registration."
categories: ["Flame", "Rust", "AI"]
tags: ["flame", "flame-rs", "flmctl", "candle", "rust", "deployment", "llm", "text-generation"]
thumbnail: "/images/huggingface-logo.svg"
thumbnail_alt: "Hugging Face logo"
thumbnail_fit: "contain"
---

PR [#459](https://github.com/xflops/flame/pull/459) adds two pieces that work well together: `flmctl deploy` and a Candle Based text-generation example in [`examples/candle/based`](https://github.com/xflops/flame/tree/main/examples/candle/based). Together they show the simplest Flame story for a local Rust inference app:

1. Put the local model code behind a small Flame service type.
2. Mark the service with Flame macros.
3. Build the service binary.
4. Deploy it with one `flmctl deploy` command.

That is the main point of this example. The model logic stays ordinary Candle code. The only change that turns it into a distributed Flame application is the service wrapper: a service struct, `#[flame::instance]`, and one `#[flame::entrypoint]` method.

The short version is:

```bash
cargo build -p candle-based-example --release

flmctl deploy \
  --name candle-based-example \
  --application ./target/release/candle-based-example-service

cargo run -p candle-based-example --bin candle-based-example --release -- \
  --app candle-based-example \
  --prompt "The future of distributed inference is" \
  --sample-len 64 \
  --which 360m
```

That is the main deployment story. Build the service binary, deploy the executable, and invoke it from the client. Flame handles the package upload and application registration.

## Local app to distributed app

The Candle example is deliberately close to a local application. The model loader still uses Candle, `hf-hub`, `tokenizers`, and normal Rust state. Generation still calls the model's `forward()` loop and decodes tokens in the usual way.

The distributed boundary is added by one service type:

```rust
#[derive(Default)]
struct BasedService {
    model: Mutex<Option<ModelBundle>>,
}

#[flame::instance]
impl BasedService {
    async fn enter(&self, instance: FlameInstance) -> Result<(), FlameError> {
        let options = instance
            .common_data::<BasedModelOptions>()?
            .unwrap_or_default();
        let bundle = load_model(options)?;

        *self.model.lock().map_err(lock_error)? = Some(bundle);
        Ok(())
    }

    #[flame::entrypoint]
    async fn generate(&self, req: GenerateRequest) -> Result<GenerateResponse, FlameError> {
        let bundle = self
            .model
            .lock()
            .map_err(lock_error)?
            .as_ref()
            .cloned()
            .ok_or_else(|| FlameError::InvalidConfig("Based model is not loaded".to_string()))?;
        bundle.generate(req)
    }
}
```

`enter()` is where the local app's startup work moves. In this example, it loads the selected Based model once when an executor is assigned to a session. `generate()` is the distributed entrypoint. Flame calls it for task execution: one call per task input, with tasks executed one by one by that executor.

That is the important code change. You do not rewrite Candle, invent a scheduler, or manually manage worker processes. You wrap the local inference path in a Flame service class, mark it with the Flame macro, and Flame can run it remotely.

## What changed

Before `flmctl deploy`, deploying an application usually meant doing the mechanical steps by hand:

| Step | Manual deployment |
|---|---|
| Package | Build a binary or create a package with the expected layout. |
| Upload | Put the artifact in object cache. |
| URL | Construct the `grpc://` or `grpcs://` object-cache URL. |
| Manifest | Write an application YAML with `spec.url`, `spec.installer`, `spec.command`, arguments, environment, and other fields. |
| Register | Run `flmctl register` against the manifest. |

`flmctl deploy` collapses the common case into one command:

```bash
flmctl deploy --name <app-name> --application <path>
```

The command is intentionally easy to use. The `--application` path can be an executable file, a `.tar.gz` or `.tgz` package, or a directory. For an executable file, `flmctl deploy` creates a normalized package with the binary under `bin/`, computes a content hash, uploads the package to Flame object cache, detects `installer=binary`, detects the command from the executable name, and registers the application.

For the Candle example, that means this command is enough:

```bash
flmctl deploy \
  --name candle-based-example \
  --application ./target/release/candle-based-example-service
```

A successful deploy prints a summary like this:

```text
Application <candle-based-example> deployed.
Input Kind: executable-file
Installer: binary
Command: candle-based-example-service
Object: candle-based-example/pkg/candle-based-example-<sha16>.tar.gz
SHA256: <sha256>
URL: grpc://<object-cache-host>:9090/candle-based-example/pkg/candle-based-example-<sha16>.tar.gz
```

The content-addressed object key is important. If you rebuild and deploy different bytes under the same application name, the package URL changes, so workers do not accidentally reuse stale installed content.

## The Candle example

The new example has two binaries:

| Binary | Role |
|---|---|
| `candle-based-example-service` | Flame service. It loads the Based model once when an executor is assigned to a session, then serves typed generation tasks. |
| `candle-based-example` | Client. It creates a Flame session, passes model options as typed common data, invokes one generation request, prints the output, and closes the session. |

The shared API is defined with regular Rust structs that derive `flame_rs::FlameMessage`:

```rust
#[derive(Debug, Clone, Serialize, Deserialize, flame_rs::FlameMessage)]
pub struct BasedModelOptions {
    pub which: BasedModelSize,
    pub model_id: Option<String>,
    pub revision: String,
    pub tokenizer_id: String,
    pub config_file: Option<String>,
    pub tokenizer_file: Option<String>,
    pub weight_files: Option<Vec<String>>,
    pub cpu: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, flame_rs::FlameMessage)]
pub struct GenerateRequest {
    pub prompt: String,
    pub sample_len: usize,
    pub temperature: Option<f64>,
    pub top_p: Option<f64>,
    pub seed: u64,
    pub repeat_penalty: f32,
    pub repeat_last_n: usize,
}
```

With those types, the service wrapper shown earlier becomes the distributed interface:

1. `enter()` runs once when the executor is assigned to a session.
2. The service reads typed common data for model selection and device options.
3. The model, tokenizer, and device are cached for that session assignment.
4. Each task input calls the typed `generate()` entrypoint once.
5. Tasks assigned to that executor run one by one.

The application code is ordinary Candle code around that lifecycle. The Flame-specific surface is small: derive typed messages, implement an instance, mark the entrypoint, and call `flame::run(...)` from the service binary.

## Deployment walkthrough

Start from a Flame checkout that includes PR #459 and build the example:

```bash
cargo build -p candle-based-example --release
```

This produces both binaries under `target/release/`. The service binary is the part that should run on Flame workers:

```bash
./target/release/candle-based-example-service
```

Deploy it:

```bash
flmctl deploy \
  --name candle-based-example \
  --application ./target/release/candle-based-example-service
```

Because the input is an executable file, `flmctl deploy` detects the binary installer and packages the executable under `bin/candle-based-example-service`. Flame's binary installer adds the extracted `bin/` directory to `PATH`, so the registered application can use `candle-based-example-service` as its command. There is no hand-written object-cache upload step and no hand-written application manifest for this common path.

If you want to inspect the generated application without registering it, use a dry run:

```bash
flmctl deploy \
  --name candle-based-example \
  --application ./target/release/candle-based-example-service \
  --dry-run \
  -o yaml
```

The rendered application shape is equivalent to:

```yaml
metadata:
  name: candle-based-example
spec:
  shim: Host
  command: candle-based-example-service
  url: grpc://<object-cache-host>:9090/candle-based-example/pkg/candle-based-example-<sha16>.tar.gz
  installer: binary
```

The checked-in example also includes a minimal manifest:

```yaml
metadata:
  name: candle-based-example
spec:
  command: /usr/local/flame/examples/candle/based/candle-based-example-service
```

That manifest is useful when the service binary is already installed on every worker. `flmctl deploy` is the easier path when you want Flame to distribute the application artifact for you.

## Running inference

After the application is deployed, run the client:

```bash
cargo run -p candle-based-example --bin candle-based-example --release -- \
  --app candle-based-example \
  --prompt "The future of distributed inference is" \
  --sample-len 64 \
  --which 360m
```

The client creates a Flame session for `candle-based-example`, sends the model options as common data, invokes the service with a `GenerateRequest`, waits for the typed `GenerateResponse`, prints the generated text, and closes the session. If the client submits several task inputs, Flame executes the entrypoint once for each input.

One container test used an app registered as `candle-based` and ran the installed client binary directly:

```bash
/usr/local/flame/examples/candle/based/candle-based-example \
  --app candle-based \
  --prompt 'Flying monkeys are'
```

The run completed one generation task:

```text
Flying monkeys are the most common species of bird in the world. They are found throughout the world, from Central and South America to Australia and New Zealand.

...

128 tokens generated in 6895 ms (18.56 token/s)
```

The session list then showed the closed session with one successful task:

```text
ID                   State   App           Resources            Priority  Pending  Running  Succeed  Failed  Created
candle-based-1R3e9n  Closed  candle-based  cpu=1,mem=2Gi,gpu=0  0         0        0        1        0       20:24:16
```

The exact generated text varies because the default client uses sampled decoding, but the operational signal is stable: the Flame application started, served one task input through the entrypoint, returned a typed response, and closed the session successfully.

The first service start downloads the Based model config and safetensors file from Hugging Face, plus the GPT-2 tokenizer, unless local paths are provided:

```bash
cargo run -p candle-based-example --bin candle-based-example --release -- \
  --app candle-based-example \
  --prompt "The future of distributed inference is" \
  --sample-len 64 \
  --which 360m \
  --config-file /models/based-360m/config.json \
  --weight-files /models/based-360m/model.safetensors \
  --tokenizer-file /models/gpt2/tokenizer.json
```

For local smoke tests, CPU execution is explicit:

```bash
cargo run -p candle-based-example --bin candle-based-example --release -- \
  --app candle-based-example \
  --prompt "Flame makes Rust inference services" \
  --sample-len 32 \
  --which 360m \
  --cpu
```

For workers with accelerators, the service chooses CUDA first, then Metal, then CPU. The client also accepts a resource request:

```bash
cargo run -p candle-based-example --bin candle-based-example --release -- \
  --app candle-based-example \
  --prompt "A distributed model service should" \
  --sample-len 64 \
  --which 360m \
  --resreq "cpu=4,mem=16g,gpu=1"
```

## Why this is easy to operate

The deployment flow has a clean separation:

| Concern | Owner |
|---|---|
| Model code | The Candle service binary. |
| Request and response types | Rust structs deriving `FlameMessage`. |
| Session assignment setup | `BasedService::enter()`. |
| Per-task generation | `#[flame::entrypoint] generate(...)`. |
| Artifact packaging | `flmctl deploy`. |
| Artifact storage | Flame object cache. |
| Worker installation | Flame binary installer. |
| Invocation | The Rust client using `flame-rs`. |

That separation keeps the application focused on inference logic. The service does not need to know how the artifact was uploaded, where the package is stored, or how workers install it. The client does not need to copy binaries to workers. The deploy command bridges local build output and the Flame application registry.

The two developer-facing steps stay small:

| Goal | What you do |
|---|---|
| Make the local app distributed | Wrap it in a Flame service type and add `#[flame::instance]` plus `#[flame::entrypoint]`. |
| Put it on the cluster | Run `flmctl deploy --name ... --application ...`. |

It also keeps iteration short:

```bash
cargo build -p candle-based-example --release
flmctl deploy --name candle-based-example --application ./target/release/candle-based-example-service
cargo run -p candle-based-example --bin candle-based-example --release -- \
  --app candle-based-example \
  --prompt "Try the new service build" \
  --sample-len 32
```

Rebuild, redeploy, rerun. The application name can stay the same while the uploaded object URL changes with the package hash.

## Operational notes

Build the service binary for the same operating system and architecture as the Flame workers. If workers are Linux hosts, build a Linux binary. If the service depends on shared libraries, package them with the application and make sure they are available under the layout expected by the binary installer, such as `lib/` or `libs/`.

The first task on a newly assigned executor may include model download and model load time because `enter()` runs before task execution for that session assignment. For repeated inference, keep executors warm with session sizing options such as `--min-instances` and `--max-instances`.

Based is a completion model, not an instruction-tuned chat model. The example defaults to sampled decoding with `--temperature 0.8`, `--top-p 0.95`, and `--repeat-penalty 1.3`. Use `--temperature 0` when deterministic argmax output is more useful than varied samples.

## Conclusion

The Candle Based example shows the Rust service path Flame is aiming for: keep the local model code, wrap it in a Flame service macro, build a binary, and deploy it with one command.

`flmctl deploy` removes the packaging and registration ceremony from the common case. For this example, the full path is just:

```bash
cargo build -p candle-based-example --release
flmctl deploy --name candle-based-example --application ./target/release/candle-based-example-service
cargo run -p candle-based-example --bin candle-based-example --release -- \
  --app candle-based-example \
  --prompt "The future of distributed inference is" \
  --sample-len 64 \
  --which 360m
```

That is enough to move a local Candle service binary into Flame and invoke it as a distributed application.

## References

- [PR #459: add flmctl deploy and object helpers](https://github.com/xflops/flame/pull/459)
- [Candle Based example](https://github.com/xflops/flame/tree/main/examples/candle/based)
- [`flmctl deploy` design](https://github.com/xflops/flame/blob/main/docs/designs/RFE458-flmctl-deploy/FS.md)
- [Flame Rust SDK](https://github.com/xflops/flame/tree/main/sdk/rust)
- [Hugging Face Candle](https://github.com/huggingface/candle)
