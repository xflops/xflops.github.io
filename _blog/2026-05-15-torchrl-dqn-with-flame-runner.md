---
layout: blog
title: "TorchRL DQN with Flame Runner and Sharded Replay"
date: 2026-05-15
author: "Klaus Ma"
description: "A technical blog on the TorchRL DQN example in Flame, covering distributed collectors, Flame-backed TorchRL replay storage, sharded sampling, and an Apple M4 Podman test run."
categories: ["Runner", "Flame", "RL"]
tags: ["flame", "flamepy", "runner", "torchrl", "dqn", "replay-buffer", "reinforcement-learning", "distributed-training"]
thumbnail: "/images/pytorch-logo.svg"
thumbnail_alt: "PyTorch logo"
thumbnail_fit: "contain"
---

This post reviews the TorchRL DQN example in [`examples/rl/torchrl_dqn`](https://github.com/xflops/flame/tree/main/examples/rl/torchrl_dqn), then summarizes one sharded-replay test on an Apple M4 MacBook Pro using a Podman-backed Flame cluster.

The example adapts a conventional TorchRL DQN loop to Flame Runner. The learner remains local. Flame distributes rollout collection, stores replay data through a TorchRL-compatible storage layer backed by Flame objects, and exposes replay buffers as Runner services for sampling.

## Summary

| Item | Finding |
|---|---|
| Artifact | TorchRL DQN training on discrete Gymnasium environments using Flame Runner collectors and Flame-backed TorchRL replay buffers. |
| Main pattern | `collector services -> ReplayBuffer(FlameObjectStorage) services -> DQNLoss -> local optimizer`. |
| Replay modes | `simple` uses one shared replay buffer; `sharded` creates multiple replay-buffer services and distributes collector writes across them. |
| Test environment | **Host:** Apple M4 MacBook Pro, 8 CPU cores, 24 GB unified memory. **VM:** Podman Machine, 5 vCPU, 8 GB RAM. **Flame on Podman Compose:** 1 FSM, 3 FEM, 1 FOC. |
| Workload measured | `CartPole-v1`, 20 iterations, 4 collections per iteration, 100 frames per collection, 8000 total frames, `--replay sharded --replay-shards 4 --sample-work 4096`. |
| Primary comparison | `--sample-parallelism 4` completed in 10.16s at 787.3 frames/sec; `--sample-parallelism 1` completed in 16.27s at 491.8 frames/sec. |
| Interpretation | Under this synthetic sampling-heavy workload, four-way sharded sampling reduced sample time from 8.415s to 2.301s and increased overall throughput by about 60.1%. |

## Scope

The implementation under review consists of the following upstream files:

| File | Role |
|---|---|
| [`main.py`](https://github.com/xflops/flame/blob/main/examples/rl/torchrl_dqn/main.py) | CLI, distributed training loop, local training loop, metrics, and sampling plan. |
| [`collector.py`](https://github.com/xflops/flame/blob/main/examples/rl/torchrl_dqn/collector.py) | Stateful rollout worker used as a Flame Runner service. |
| [`replay_buffer.py`](https://github.com/xflops/flame/blob/main/examples/rl/torchrl_dqn/replay_buffer.py) | TorchRL storage implementations, Flame object-backed replay storage, local replay storage, and sharding helpers. |
| [`model.py`](https://github.com/xflops/flame/blob/main/examples/rl/torchrl_dqn/model.py) | Environment inspection, Q-value policy construction, TorchRL `DQNLoss`, and transition conversion helpers. |
| [`pyproject.toml`](https://github.com/xflops/flame/blob/main/examples/rl/torchrl_dqn/pyproject.toml) | Runtime dependencies: Gymnasium, TensorDict, PyTorch, and TorchRL. |

The example is a DQN integration and data-path benchmark vehicle. It should not be read as a production DQN recipe or as a reward-quality study. The run uses `CartPole-v1` and intentionally adds synthetic sampling work so replay sampling becomes visible in wall-clock timing.

## System architecture

The training loop keeps the learner local and distributes the work that naturally fans out:

![TorchRL DQN with Flame Runner architecture](/images/torchrl-dqn-flame-architecture.svg)

At a high level, the learner publishes policy weights through `Runner.put_object()`, Flame schedules collector services, collectors write TensorDict transition batches into sharded replay buffers, and the learner samples those replay services before running the local `DQNLoss` and optimizer step.

The collector is stateful. Each service instance owns a Gymnasium environment and a policy object, loads the latest learner weights for each collection call, steps the environment, and writes a TensorDict transition batch into the replay buffer.

The replay buffer remains a TorchRL `ReplayBuffer` from the learner's point of view. The important difference is its storage:

| Storage | Location | Purpose |
|---|---|---|
| `FlameObjectStorage` | Flame object cache | Stores TensorDict batches behind an object reference and appends new batches through Flame object patches. |
| `LocalObjectStorage` | In-process Python object | Provides a local comparison path with the same append-oriented semantics. |

This keeps the TorchRL training surface recognizable while allowing Flame to manage remote collection, shared object state, and service-level sample parallelism.

## Replay modes

The example exposes two distributed replay layouts:

| Mode | Behavior |
|---|---|
| `--replay simple` | Creates one `ReplayBuffer(FlameObjectStorage)` service path. This is the baseline distributed replay mode. |
| `--replay sharded` | Creates multiple replay-buffer services, spreads collector writes across shards, and samples shards independently. |

The sharded mode is the relevant mode for the measurement here. With `--replay-shards 4`, collector writes are distributed across four Flame-backed replay buffers. With `--sample-parallelism 4`, the learner sends four sample requests per optimization step, each targeting a shard selected by the sampling plan.

The `--sample-work` flag adds CPU work inside the storage `get()` path used by TorchRL sampling. It is synthetic by design. It models replay operations that are common in larger RL systems, such as decompression, frame stacking, sequence assembly, or augmentation. Without this extra work, `CartPole-v1` is too small for replay sampling to dominate.

## Reproduction procedure

Start a Flame cluster, open the console container, and run the example from the Flame repository checkout:

```shell
docker compose exec -it flame-console /bin/bash
cd /opt/examples/rl/torchrl_dqn
```

Four-way sample run:

```shell
uv run main.py \
  --replay sharded \
  --replay-shards 4 \
  --sample-work 4096 \
  --sample-parallelism 4
```

Single-sample-service comparison:

```shell
uv run main.py \
  --replay sharded \
  --replay-shards 4 \
  --sample-work 4096 \
  --sample-parallelism 1
```

Relevant default workload parameters for both commands:

| Parameter | Value |
|---|---:|
| Environment | `CartPole-v1` |
| Iterations | 20 |
| Collections per iteration | 4 |
| Frames per collection | 100 |
| Total frames | 8000 |
| Batch size | 64 |
| Replay buffer size | 10000 |
| Optimizer steps per iteration | 1 |
| Target update tau | 0.05 |
| Epsilon schedule | 0.200 to 0.020 |

## Test environment

All measurements below come from one local Mac setup:

| Component | Configuration |
|---|---|
| Host | Apple M4 MacBook Pro |
| Host CPU / memory | 8 CPU cores, 24 GB unified memory |
| Container VM | Podman Machine |
| VM sizing | 5 vCPU, 8 GB RAM |
| Flame deployment | Podman Compose |
| Flame services | 1 FSM, 3 FEM, 1 FOC |

This is a same-machine, VM-contained test environment. It is useful for validating behavior and relative timing under constrained resources, but it is not a bare-metal Linux cluster or a datacenter benchmark.

## Results

### Summary

| Sample parallelism | Total time | Total frames | Throughput | Final loss |
|---:|---:|---:|---:|---:|
| 4 | 10.16s | 8000 | 787.3 frames/sec | 0.4962 |
| 1 | 16.27s | 8000 | 491.8 frames/sec | 0.4705 |

Throughput improvement from `--sample-parallelism 1` to `--sample-parallelism 4`:

$$
\frac{787.3 - 491.8}{491.8} \approx 60.1\%
$$

Total wall-clock reduction:

$$
\frac{16.27 - 10.16}{16.27} \approx 37.6\%
$$

### Timing breakdown

| Phase | Parallelism 4 | Parallelism 1 | Change |
|---|---:|---:|---:|
| Collect | 7.607s total, 0.380s/iter | 7.606s total, 0.380s/iter | No material change |
| State | 0.053s total, 0.003s/iter | 0.054s total, 0.003s/iter | No material change |
| Sample | 2.301s total, 0.115s/iter | 8.415s total, 0.421s/iter | 72.7% lower sample time |
| Optimize | 0.089s total, 0.004s/iter | 0.108s total, 0.005s/iter | Small relative to run time |
| Iteration | 10.072s total, 0.504s/iter | 16.203s total, 0.810s/iter | 37.8% lower iteration time |

The timing breakdown is the main result. Collection time is essentially identical in both runs, which means the improvement is not coming from faster environment stepping. The difference is concentrated in replay sampling: four-way sampling completed the sample phase in 2.301s instead of 8.415s, a sample-phase speedup of about 3.66x.

### Training trace

Both runs collected exactly 8000 frames and used the same default epsilon schedule. Average completed-episode reward stayed around 9 to 11 during the short run. Final loss landed in the same broad range:

| Sample parallelism | Initial loss | Final loss | Final reward |
|---:|---:|---:|---:|
| 4 | 1.0685 | 0.4962 | 9.3 |
| 1 | 1.2380 | 0.4705 | 9.5 |

This trace is adequate for confirming that the learner is exercising TorchRL `DQNLoss` and updating the policy, but it is not a policy-quality comparison. The run is short, single-seed, and configured to expose sampling behavior rather than solve CartPole.

## Interpretation

The workload was intentionally shaped so sampling mattered:

1. `CartPole-v1` keeps collection cheap.
2. `--sample-work 4096` adds deterministic CPU work to each sampled transition.
3. `--replay sharded --replay-shards 4` gives sampling a layout that can be parallelized.
4. `--sample-parallelism 4` lets the learner issue concurrent sample requests to different replay-buffer services.

Under those conditions, Flame's service model gives the replay stage useful concurrency. The collector path does not change materially between the two runs, and optimizer time is small. The throughput gain therefore maps directly to reduced sampling latency.

The result also clarifies a boundary: sample parallelism helps when sample work is real enough and when the replay layout has enough shards to serve independent requests. For cheap single-shard sampling, the overhead of extra services and requests may not pay for itself.

## Operational notes

Use this example in three modes:

| Goal | Suggested command shape |
|---|---|
| Smoke test TorchRL integration | `uv run main.py --local --iterations 5` |
| Validate distributed collectors | `uv run main.py --iterations 20 --collections 4` |
| Stress replay sampling | `uv run main.py --replay sharded --replay-shards 4 --sample-work 4096 --sample-parallelism 4` |

For larger experiments, increase `--collections`, `--frames-per-collection`, and `--optim-steps` so each scheduling round carries more useful work. For heavier discrete-action environments, the example supports aliases such as `acrobot`, `mountaincar`, and `lunarlander`; `lunarlander` requires the Box2D extra.

## Limitations

- Results are from one run per setting on one Apple M4 Podman environment.
- The run uses synthetic `--sample-work`; the exact speedup depends on the real replay workload.
- `CartPole-v1` is intentionally small, so absolute frame throughput is not a cluster-scale result.
- Reward and loss should not be compared statistically without repeated seeds and longer training.
- DQN supports discrete action spaces; continuous MuJoCo tasks belong in PPO, SAC, or another continuous-control example.

## Conclusion

The TorchRL DQN example demonstrates that Flame can wrap a familiar TorchRL learner without replacing the learning stack. TorchRL still owns the Q-value actor, TensorDict batches, `ReplayBuffer` interface, `DQNLoss`, and optimizer step. Flame supplies the distributed runtime around it: collector services, object-backed replay storage, sharded replay services, and concurrent sample requests.

On the measured Apple M4 Podman setup, the sharded replay test shows the expected effect. With a sampling-heavy workload, increasing sample parallelism from 1 to 4 improved throughput from 491.8 to 787.3 frames/sec and cut sample time from 8.415s to 2.301s. The evidence is narrow but useful: when replay sampling is the bottleneck, sharding the Flame-backed TorchRL replay path gives the learner a practical way to reduce sampling latency.

## References

- [TorchRL DQN example](https://github.com/xflops/flame/tree/main/examples/rl/torchrl_dqn)
- [TorchRL DQN example README](https://github.com/xflops/flame/blob/main/examples/rl/torchrl_dqn/README.md)
- [TorchRL DQN main loop](https://github.com/xflops/flame/blob/main/examples/rl/torchrl_dqn/main.py)
- [Flame-backed replay storage](https://github.com/xflops/flame/blob/main/examples/rl/torchrl_dqn/replay_buffer.py)
- [TorchRL introduction tutorial](https://docs.pytorch.org/rl/stable/tutorials/torchrl_demo.html)
