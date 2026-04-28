---
layout: blog
title: "Distributed REINFORCE with Flame Runner"
date: 2026-04-28
author: "Klaus Ma"
categories: ["Runner", "Flame", "RL"]
tags: ["flame", "runner", "reinforce", "gymnasium", "mujoco", "distributed-training", "uv"]
---

This report documents the RL example merged in [PR #424](https://github.com/xflops/flame/pull/424) and evaluates distributed versus local training for `Ant-v5`. The implementation is located under `examples/rl/` in the Flame repository.

## Executive summary

- A distributed REINFORCE example was added using `flamepy.runner`.
- The implementation supports both discrete and continuous action spaces.
- On the reported `Ant-v5` benchmark (`10,000` episodes), distributed mode reached `29.8 eps/sec` versus `20.8 eps/sec` in local mode.
- On the reported `CartPole-v1` benchmark (`10,000` episodes), distributed mode reached `19.3 eps/sec` versus `8.1 eps/sec` in local mode.
- This corresponds to a throughput gain of approximately `43.3%`.
- Across both runs, distributed mode improved wall-clock throughput; reward outcomes varied by environment and trial.

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

The following snippet captures the distributed control path from `examples/rl/main.py`:

```python
from functools import partial
from flamepy import put_object
from flamepy.runner import Runner

collect_fn = partial(collect_episode, env_name=env_name)

with Runner(f"rl-{env_name}") as rr:
    collector = rr.service(collect_fn)

    for iteration in range(num_iterations):
        weights_ref = put_object(f"rl-weights-{iteration}", policy.state_dict())

        futures = [collector(weights_ref) for _ in range(episodes_per_iteration)]
        episodes = rr.get(futures)

        # local learner step (compute loss, backprop, optimizer.step)
```

The remote worker entrypoint (`collect_episode`) is plain Python:

```python
def collect_episode(weights, env_name: str) -> dict:
    from model import ENV_CONFIGS, create_policy

    env_config = ENV_CONFIGS[env_name]
    model = create_policy(env_config)
    model.load_state_dict(weights)
    model.eval()

    env = gym.make(env_config.name)
    # rollout loop ...
    return {
        "states": states,
        "actions": actions,
        "rewards": rewards,
        "total_reward": sum(rewards),
    }
```

Each call to `collector(...)` can be scheduled on a remote executor; this enables concurrent episode collection.

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

### `put_object(key, value)`

Publishes a large object and passes a reference to remote tasks:

```python
weights_ref = put_object(f"rl-weights-{iteration}", policy.state_dict())
episodes = rr.get([collector(weights_ref) for _ in range(episodes_per_iteration)])
```

- Reduces repeated serialization/transfer of model weights.
- Remote workers consume the resolved object in `collect_episode`.

These interfaces implement an actor-learner pattern with minimal divergence from local training code.

## Reproduction procedure

### Prerequisites

Start the Flame cluster:

```bash
docker compose up -d
```

Enter the console and switch to the example directory:

```bash
docker compose exec -it flame-console /bin/bash
cd /opt/examples/rl
```

### Execution commands

Distributed `Ant-v5` run:

```bash
uv run main.py --env ant
```

Local baseline:

```bash
uv run main.py --env ant --local
```

Additional runs:

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

Reported benchmark settings:

- `iterations = 100`
- `episodes_per_iteration = 100`
- `total_episodes = 10000`

## Results (`Ant-v5`)

Results are based on the provided execution logs:

| Mode | Total Time | Episodes | Throughput | Final Mean Reward |
|---|---:|---:|---:|---:|
| Distributed (`--env ant`) | 335.71s | 10000 | 29.8 eps/sec | -252.6 |
| Local (`--env ant --local`) | 481.70s | 10000 | 20.8 eps/sec | -166.1 |

### Throughput comparison

Distributed mode improves episode throughput by approximately **43.3%**:

\[
\frac{29.8 - 20.8}{20.8} \approx 43.3\%
\]

### Reward observation

In this single trial, local mode reached a better final mean reward (`-166.1` vs `-252.6`) while distributed mode completed substantially faster. Because policy-gradient outcomes are high variance, reward quality conclusions should be based on repeated multi-seed runs.

## Results (`CartPole-v1`)

Results are based on the provided execution logs:

| Mode | Total Time | Episodes | Throughput | Final Mean Reward |
|---|---:|---:|---:|---:|
| Distributed (`uv run main.py`) | 517.94s | 10000 | 19.3 eps/sec | 499.8 |
| Local (`uv run main.py --local`) | 1230.12s | 10000 | 8.1 eps/sec | 193.4 |

### Throughput comparison

Distributed mode improves episode throughput by approximately **138.3%**:

\[
\frac{19.3 - 8.1}{8.1} \approx 138.3\%
\]

### Reward observation

In this trial, distributed mode also reached a substantially better final mean reward (`499.8` vs `193.4`). The local run shows late-stage instability at iteration 99, which reinforces the need for repeated seeded runs before making algorithm-quality conclusions.

## Interpretation: when distribution helps

Distributed execution introduces overhead; net benefit depends on rollout cost:

| Workload | Expected Distributed Benefit |
|---|---|
| Very fast envs (for example CartPole) | Environment-dependent; can still benefit significantly in practice |
| Medium-cost envs (for example Hopper/HalfCheetah) | Moderate, depends on batch parallelism |
| Heavier envs (for example Ant) | Strong with enough episodes per iteration |
| Expensive real-world/sim workloads | Very strong; often essential |

Observed in this setup:

- `Ant-v5`: distributed throughput gain of `43.3%`.
- `CartPole-v1`: distributed throughput gain of `138.3%`.

## Operational guidance

For improved distributed efficiency:

1. Increase `--episodes-per-iter` to amortize scheduling and transfer overhead.
2. Prefer heavier environments when validating speedups.
3. Scale executor count with rollout demand.
4. Use `--local` for lightweight environments and debugging loops.

## Conclusion

This evaluation indicates that Flame Runner can materially improve rollout throughput for heavier RL environments while preserving a simple learner implementation.

Practical implication:

- For faster experiment turnaround, distributed collection is effective in both tested environments.
- For reward-quality assessment, use repeated seeded runs and tune optimization hyperparameters.

## Post-merge notes

Two review-driven refinements were incorporated as part of the merge:

- Shared components were extracted into `model.py` to make remote imports more robust.
- Discounted reward computation was updated to reverse-index assignment, eliminating quadratic `insert(0, ...)` behavior.

## References

- [Add RL example (PR #424)](https://github.com/xflops/flame/pull/424)
- [Flame repository](https://github.com/xflops/flame)
- [RL example README (`xflops/flame`, `main`)](https://raw.githubusercontent.com/xflops/flame/main/examples/rl/README.md)
