---
layout: blog
title: "Running a Parameter Server with Runner"
date: 2026-04-03
author: "Klaus Ma"
categories: ["Runner", "Flame", "ML"]
tags: ["runner", "parameter-server", "distributed-training", "pytorch", "flamepy"]
---

In AI-related distributed workloads, large amounts of data often need to move between many worker nodes. Flame provides an **object cache** to help pass data objects across nodes. This walkthrough uses a simple **Parameter Server** (ps–worker) pattern to show how **Flame Runner** fits a training-style workflow. Later posts in the series will cover internal mechanics and optimizations for different scenarios.

## Overview

The ps–worker pattern is a classic distributed training architecture:

- The **Parameter Server** holds global model weights and applies gradient updates.
- Multiple **workers** compute gradients on different data batches in parallel.
- Each worker fetches the latest weights, computes gradients, and sends them back to the Parameter Server.

This example uses Flame’s **`flamepy.runner.Runner`** to orchestrate distributed services and handle communication between them.

## Architecture

```
   ┌─────────────────────┐
   │  Parameter Server   │  - Stores model weights
   │                     │  - Applies aggregated gradients
   └─────────┬───────────┘
             │
      ┌──────┴──────┐
      │             │
┌─────▼─────┐   ┌─────▼─────┐  - Fetch weights
│ Worker 1  │   │ Worker 2  │  - Compute gradients on data batches
└───────────┘   └───────────┘
```

## Components

- **ConvNet** — Small convolutional network for MNIST digit classification.
- **ParameterServer** — Keeps model state and applies gradient updates with SGD.
- **DataWorker** — Computes gradients on mini-batches from the training set.
- **Main training loop** — Coordinates synchronous training iterations.

## Files

- `main.py` — Entry point: sets up Runner and the training loop.
- `ps.py` — Model, parameter server, and data workers.
- `pyproject.toml` — Dependencies and project metadata.

## Requirements

- Python >= 3.12
- PyTorch and torchvision
- Flame Python SDK (`flamepy`)
- NumPy
- `filelock`

## How to run

Build the Flame cluster (if it is not already running):

```bash
docker compose build
docker compose up -d
```

Go to the example directory:

```bash
cd examples/ps
```

Run the example:

```bash
python main.py
```

The script downloads the MNIST dataset on first run and starts training.

## Expected output

```text
100.0%
100.0%
100.0%
100.0%
Running synchronous parameter server training.
Iter 0:         accuracy is 16.5
Iter 10:        accuracy is 32.9
Final accuracy is 32.9.
```

In this simplified run, accuracy usually rises from about **10%** (random guessing) to roughly **30–35%** after **20** training iterations, as shown above. Higher accuracy may require more iterations, a larger model, or evaluation on the full dataset.

## Key concepts

### 1. Creating services with Runner

```python
with Runner("ps-example") as rr:
    ps_svc = rr.service(ParameterServer(1e-2))
    workers_svc = [rr.service(DataWorker) for _ in range(2)]
```

Runner creates and manages distributed services. A service can be built from any Python class.

### 2. Asynchronous remote calls

```python
gradients = [worker.compute_gradients(current_weights) for worker in workers_svc]
current_weights = ps_svc.apply_gradients(*gradients).get()
```

Method calls on services return futures. Use **`.get()`** to block and retrieve the result.

### 3. Synchronous training

The training loop waits for every worker to finish its gradients before the parameter server applies an update:

```python
for i in range(20):
    # Start all gradient computations in parallel
    gradients = [worker.compute_gradients(current_weights) for worker in workers_svc]
    # Wait for all gradients, then apply the update
    current_weights = ps_svc.apply_gradients(*gradients).get()
```

This is a **synchronous** parameter server: each iteration waits for all workers.

For more on Runner lifecycle (packaging, registration, cleanup), see [Running Monte Carlo Pi with Flame Runner (Python)](/blog/estimating-pi-with-runner/).

## Customization

**Change the number of workers** in `main.py`:

```python
workers_svc = [rr.service(DataWorker) for _ in range(4)]  # four workers
```

**Change the learning rate** when constructing the parameter server:

```python
ps_svc = rr.service(ParameterServer(1e-3))  # lower learning rate
```

**Train for more iterations** by changing the loop bound in `main.py` from `range(20)` to e.g. `range(50)`.

## Notes

- The example uses **`filelock`** so MNIST can be downloaded safely when several workers start at the same time.
- **Evaluation** is capped at **1024** samples so iteration during development stays fast.
- The model is deliberately small: the goal is to demonstrate the **pattern**, not state-of-the-art accuracy.

## Related examples

- Reinforcement learning: see the `examples/rl/` directory in the Flame repo.
- Other distributed patterns: browse under `examples/`.

## Troubleshooting

If something goes wrong:

1. **Services do not start** — Confirm the Flame cluster is up (`docker compose ps`).
2. **Import errors** — After changing `sdk/python`, rebuild containers: `docker compose build`.
3. **Test timeouts** — Inspect logs: `docker logs flame-executor-manager` and `docker logs flame-session-manager`.

## References

- [Flame on GitHub](https://github.com/xflops/flame)
- [Parameter Server example (`examples/ps`)](https://github.com/xflops/flame/tree/main/examples/ps)
- Mu Li *et al.*, [Scaling Distributed Machine Learning with the Parameter Server](https://www.usenix.org/system/files/conference/osdi14/osdi14-paper-li_mu.pdf) (OSDI ’14)
- [RFE280 — Runner design](https://github.com/xflops/flame/blob/main/docs/designs/RFE280-runner/RFE280-runner.md)
- [Runner setup tutorial](https://github.com/xflops/flame/blob/main/docs/tutorials/runner-setup.md)
