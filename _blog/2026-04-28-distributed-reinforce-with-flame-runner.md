---
layout: blog
title: "Distributed REINFORCE with Flame Runner"
date: 2026-04-28
author: "Klaus Ma"
categories: ["Runner", "Flame", "RL"]
tags: ["flame", "runner", "reinforce", "gymnasium", "mujoco", "distributed-training", "uv"]
---

This report describes the reinforcement-learning example merged in [PR #424](https://github.com/xflops/flame/pull/424), summarizes its design against current upstream sources, and presents single-run throughput and reward metrics for `Ant-v5` and `CartPole-v1`. Companion site changes are recorded in [xflops.github.io #17](https://github.com/xflops/xflops.github.io/pull/17). Reference implementation: [`examples/rl/`](https://github.com/xflops/flame/tree/main/examples/rl) in the Flame repository.

## Executive summary

| Item | Finding |
|---|---|
| Artifact | Distributed REINFORCE training using `flamepy.runner`; discrete and continuous Gymnasium environments. |
| `Ant-v5` (10000 episodes) | Distributed 29.8 eps/sec vs local 20.8 eps/sec; relative throughput gain approximately 43.3%. |
| `CartPole-v1` (10000 episodes) | Distributed 19.3 eps/sec vs local 8.1 eps/sec; relative throughput gain approximately 138.3%. |
| Reward quality | Single-trial outcomes differ by mode and environment; multi-seed study recommended before policy conclusions. |

## Scope and motivation

The primary objective is to assess whether Flame Runner reduces rollout bottlenecks in policy-gradient training. In RL pipelines, episode collection is typically the dominant wall-clock cost and is naturally parallelizable because episodes are independent. The example adopts an actor-learner structure:

- Remote executors collect trajectories.
- A centralized learner computes gradients and updates policy weights.
- Updated weights are published for the next collection round.

## Supported environments

| Environment | Type | Observation | Action | Typical Episode Time |
|---|---|---:|---:|---:|
| `cartpole` | Discrete | 4 | 2 | ~1ms |
| `hopper` | Continuous (MuJoCo) | 11 | 3 | ~15ms |
| `halfcheetah` | Continuous (MuJoCo) | 17 | 6 | ~20ms |
| `walker2d` | Continuous (MuJoCo) | 17 | 6 | ~20ms |
| `ant` | Continuous (MuJoCo) | 105 | 8 | ~50ms |

## System architecture

The training loop follows a distributed actor-learner flow:

1. The learner keeps a local policy network.
2. Policy weights are serialized and sent to remote workers.
3. Workers run complete episodes and return trajectories.
4. The learner computes discounted returns and policy gradients.
5. Updated weights are broadcast for the next iteration.

Flame Runner is responsible for remote task scheduling and result collection; policy optimization remains in a single local learner loop.

## Core implementation (`flamepy.runner`)

**Excerpt — learner control path.** The listing below is abbreviated from upstream [`examples/rl/main.py`](https://github.com/xflops/flame/blob/main/examples/rl/main.py); the learner-side loss and optimizer step are omitted for brevity.

```python
from functools import partial
from flamepy.runner import Runner

collect_fn = partial(collect_episode, env_name=env_name)

with Runner(f"rl-{env_name}") as rr:
    collector = rr.service(collect_fn)

    for iteration in range(num_iterations):
        weights_ref = rr.put_object(policy.state_dict())

        futures = [collector(weights_ref) for _ in range(episodes_per_iteration)]
        episodes = rr.get(futures)

        # ... policy loss, backward(), optimizer.step()
```

**Excerpt — remote worker.** The worker callable matches the upstream structure: third-party and framework modules are imported inside the function body so execution environments resolve them at task run time (see upstream file for the full rollout loop).

```python
def collect_episode(weights, env_name: str) -> dict:
    import gymnasium as gym
    import torch

    from model import ENV_CONFIGS, create_policy

    env_config = ENV_CONFIGS[env_name]
    model = create_policy(env_config)
    model.load_state_dict(weights)
    model.eval()

    env = gym.make(env_config.name)
    # ... rollout until termination ...
    return {
        "states": states,
        "actions": actions,
        "rewards": rewards,
        "total_reward": sum(rewards),
    }
```

**Parallelism.** Each invocation of `collector(...)` may execute on a distinct remote executor, yielding concurrent episode collection subject to cluster capacity and scheduling policy.

## `flamepy.runner` interface notes

### `Runner(name)`

`Runner` is the lifecycle container for a distributed run:

```python
with Runner("rl-ant") as rr:
    ...
```

- Initializes a named runner context.
- Manages runner/session connectivity during execution.
- Releases resources on context exit.

### `rr.service(callable)`

Registers a callable as a runner service and returns an invokable handle:

```python
collector = rr.service(collect_fn)
```

- Accepts a function or callable class implementing remote work.
- Returns a handle that is invoked like a local function.
- Each call schedules remote execution and returns a future-like object.

### Remote invocation and futures

The training loop fans out episode jobs:

```python
futures = [collector(weights_ref) for _ in range(episodes_per_iteration)]
```

- Calls are asynchronous.
- Pattern: fan-out task submission, then fan-in result collection.

### `rr.get(futures)`

Waits for completion and returns resolved outputs:

```python
episodes = rr.get(futures)
```

- Typical pattern: submit batch -> resolve batch -> run learner update.
- Preserves clear separation between collection and optimization.

### `rr.put_object(value)`

Publishes a payload on the active `Runner` session and yields a reference suitable for remote task arguments. Upstream training uses the policy `state_dict()` as the published value ([`examples/rl/main.py`](https://github.com/xflops/flame/blob/main/examples/rl/main.py)):

```python
weights_ref = rr.put_object(policy.state_dict())
episodes = rr.get([collector(weights_ref) for _ in range(episodes_per_iteration)])
```

- Publication is scoped to the runner instance (`rr.put_object`); earlier variants that used a module-level `put_object` with explicit string keys are not required here.
- Workers observe a resolved `state_dict` where the runtime maps the reference to materialized data (per upstream docstring on `weights`).

**Summary.** The listed APIs suffice for an actor-learner layout with localized changes relative to a single-process trainer.

## Reproduction procedure

### Environment

1. Start the Flame cluster (repository default compose workflow):

```bash
docker compose up -d
```

2. Open a shell in the console container and set the working directory to the example:

```bash
docker compose exec -it flame-console /bin/bash
cd /opt/examples/rl
```

### Commands exercised in this report

Distributed `Ant-v5`:

```bash
uv run main.py --env ant
```

Local `Ant-v5` baseline:

```bash
uv run main.py --env ant --local
```

Additional command patterns (not all re-measured here):

```bash
# distributed cartpole (default env)
uv run main.py

# distributed mujoco envs
uv run main.py --env halfcheetah
uv run main.py --env hopper
uv run main.py --env walker2d

# custom training schedule
uv run main.py --env ant --iterations 50 --episodes-per-iter 50

# reward plot
uv run main.py --plot
```

### CLI options

| Flag | Description | Default |
|---|---|---|
| `--env` | `cartpole`, `halfcheetah`, `hopper`, `walker2d`, `ant` | `cartpole` |
| `--local` | Run locally without Flame cluster | off |
| `--iterations` | Number of training iterations | `100` |
| `--episodes-per-iter` | Episodes collected per iteration | `100` |
| `--plot` | Show reward plot after training | off |

**Benchmark configuration (both environments reported below).**

- Training iterations: `100`
- Episodes per iteration: `100`
- Total episodes: `10000`

## Results — `Ant-v5`

**Data source.** Single pair of runs; logs supplied for this note. Hardware and cluster topology were not varied within the study.

**Measurements.**

| Mode | Total Time | Episodes | Throughput | Final Mean Reward |
|---|---:|---:|---:|---:|
| Distributed (`--env ant`) | 335.71s | 10000 | 29.8 eps/sec | -252.6 |
| Local (`--env ant --local`) | 481.70s | 10000 | 20.8 eps/sec | -166.1 |

### Throughput

Relative improvement of distributed over local throughput:

\[
\frac{29.8 - 20.8}{20.8} \approx 43.3\%
\]

### Reward

Under the stated single trial, the local configuration achieved a higher terminal mean reward than the distributed configuration (`-166.1` vs `-252.6`), while distributed mode completed in less wall time. Policy-gradient estimators are sensitive to sample noise; generalization of reward ordering requires replicated experiments with controlled randomness.

## Results — `CartPole-v1`

**Data source.** Single pair of runs; logs supplied for this note.

**Measurements.**

| Mode | Total Time | Episodes | Throughput | Final Mean Reward |
|---|---:|---:|---:|---:|
| Distributed (`uv run main.py`) | 517.94s | 10000 | 19.3 eps/sec | 499.8 |
| Local (`uv run main.py --local`) | 1230.12s | 10000 | 8.1 eps/sec | 193.4 |

### Throughput

Relative improvement of distributed over local throughput:

\[
\frac{19.3 - 8.1}{8.1} \approx 138.3\%
\]

### Reward

Distributed mode reported a higher terminal mean reward than local mode (`499.8` vs `193.4`). The local trace exhibits a sharp regression at the final logged iteration, which is consistent with stochastic policy-gradient training rather than a definitive ranking of modes.

## Interpretation — when distribution helps

Distributed execution incurs coordination and transfer overhead; net benefit scales with per-episode simulation cost and batching parameters:

| Workload | Expected Distributed Benefit |
|---|---|
| Very fast envs (for example CartPole) | Environment-dependent; can still benefit significantly in practice |
| Medium-cost envs (for example Hopper/HalfCheetah) | Moderate, depends on batch parallelism |
| Heavier envs (for example Ant) | Strong with enough episodes per iteration |
| Expensive real-world/sim workloads | Very strong; often essential |

**Observations under this report’s configuration.**

- `Ant-v5`: distributed throughput approximately 43.3% above local.
- `CartPole-v1`: distributed throughput approximately 138.3% above local.

## Recommendations (operations)

Operational parameters suggested by the example and measured runs:

1. Increase `--episodes-per-iter` to amortize scheduling and transfer overhead.
2. Prefer heavier environments when validating speedups.
3. Scale executor count with rollout demand.
4. Use `--local` for lightweight environments and debugging loops.

## Conclusion

Within the two single-run configurations documented here, Flame Runner–backed distributed rollout increased episode throughput relative to local rollout for both `Ant-v5` and `CartPole-v1`. Terminal reward favored local training in the Ant trial and distributed training in the CartPole trial, underscoring that throughput and policy quality should be evaluated on separate criteria and, where reward matters, with multi-seed statistical replication.

## Implementation status (upstream `examples/rl/`)

The following items are reflected in the current `main` branch layout:

- Shared policy and environment configuration in `model.py` to stabilize imports on remote workers.
- Discounted return computation implemented with linear-time reverse indexing.
- Weight publication via `Runner.put_object(policy.state_dict())` (session-scoped object handle).

## References

- Flame: [Add RL example — PR #424](https://github.com/xflops/flame/pull/424)
- Flame repository: [xflops/flame](https://github.com/xflops/flame)
- Reference code: [`examples/rl/main.py`](https://github.com/xflops/flame/blob/main/examples/rl/main.py)
- Reference documentation: [`examples/rl/README.md`](https://github.com/xflops/flame/blob/main/examples/rl/README.md)
- This article (site merge): [xflops/xflops.github.io — PR #17](https://github.com/xflops/xflops.github.io/pull/17)
- Report polish and unit consistency: [xflops/xflops.github.io — PR #18](https://github.com/xflops/xflops.github.io/pull/18)
