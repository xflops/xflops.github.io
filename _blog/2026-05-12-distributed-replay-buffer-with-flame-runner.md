---
layout: blog
title: "Distributed Replay Buffer with Flame App"
date: 2026-05-12
author: "Klaus Ma"
description: "A technical blog on Flame's replay-buffer example, covering patch_object delta updates, parallel sampling, and the handler-plus-data programming model."
categories: ["Flame", "RL"]
tags: ["flame", "flamepy", "app", "replay-buffer", "reinforcement-learning", "patch-object", "distributed-training"]
---

This blog reviews the replay-buffer example in [`examples/rl/replay_buffer`](https://github.com/xflops/flame/tree/main/examples/rl/replay_buffer). The example demonstrates how Flame can manage an append-heavy reinforcement-learning data structure by combining `flamepy.core.patch_object`, versioned object reads, and `flamepy.app` services.

The example is not intended to evaluate an RL algorithm. It uses random Gymnasium actions, so reward quality is outside the scope here. The relevant question is whether the replay-buffer data path can support distributed collection and repeated sampling without forcing every operation through full-buffer copies.

The measurements below came from the original Runner-based example. The code
excerpts describe the current App implementation; its performance has not been
re-measured for this post.

## Executive summary

| Item | Finding |
|---|---|
| Artifact | Distributed replay buffer implemented with `flamepy.app`, Flame object cache, and Gymnasium collectors. |
| Primary write path | Collectors append transition batches through `flamepy.core.patch_object`, so writes send only deltas instead of replacing the full buffer. |
| Primary read path | Replay-buffer service instances use `get_object(..., deserializer=...)` to materialize state from a base object plus patches. With cached versions, reads can apply only newly observed patch batches. |
| Sampling model | `--sample-parallelism N` issues up to `N` sample requests; the buffer service starts with two warm instances and can scale with demand. |
| Differentiation | Flame separates handler and data: multiple handlers can serve parallel `sample()` calls while the buffer data remains in one shared `ObjectRef`. |
| Programming model | The example separates handler and data: `ReplayBuffer` carries behavior and an `ObjectRef`; the buffer contents live in Flame's object cache. |
| Performance interpretation | The example run shows incremental distributed reads substantially outperforming forced full reads. Local in-memory execution can still be faster for cheap environments because it avoids Flame runtime overhead. |

## Scope

The implementation under review consists of four files:

| File | Role |
|---|---|
| [`main.py`](https://github.com/xflops/flame/blob/main/examples/rl/replay_buffer/main.py) | Creates service handles, coordinates collection, and issues sample requests. |
| [`distributed.py`](https://github.com/xflops/flame/blob/main/examples/rl/replay_buffer/distributed.py) | Initializes the app and declares collector and buffer services. |
| [`collector.py`](https://github.com/xflops/flame/blob/main/examples/rl/replay_buffer/collector.py) | Steps a Gymnasium environment, accumulates transitions, and calls `buffer.push(...)`. |
| [`replay_buffer.py`](https://github.com/xflops/flame/blob/main/examples/rl/replay_buffer/replay_buffer.py) | Owns the shared `ObjectRef`, appends patches, materializes state, merges patches, and samples transitions. |

The example covers data movement and service orchestration. It does not implement policy learning, prioritized replay, storage eviction, or correctness guarantees beyond the shared object-cache semantics used by the example.

## System architecture

The distributed path imports two service declarations and creates a shared cached object:

```python
from distributed import BufferService, CollectorService

buffer = ReplayBuffer(force_full_get=force_full_get)
buffer_service = BufferService()
collector_service = CollectorService()
```

`ReplayBuffer` initializes the cache object:

```python
self.buffer_ref = app.put({"transitions": [], "total_added": 0})
```

From that point forward, the replay buffer is represented by two parts:

| Part | Responsibility |
|---|---|
| `ObjectRef` data | Stores the base replay-buffer state plus appended transition patches in Flame's cache. |
| `ReplayBuffer` handler | Provides `push`, `state`, `sample`, `merge`, and materialization behavior around the shared object reference. |

The collection loop fans out environment work and lets each collector append directly to the shared object:

```python
collect_futures = [
    collector_service.collect(env_name, buffer, steps_per_collection)
    for _ in range(num_collections)
]
collect_results = app.get(collect_futures)
```

## Finding 1: Delta updates reduce write amplification

The write path is deliberately narrow:

```python
def push(self, transitions: List[dict]) -> None:
    self._patch_object(self.buffer_ref, transitions)
```

Each collector accumulates a batch of transitions locally, then calls `buffer.push(transitions)`. Because `push` uses `patch_object`, the collector writes only the newly produced transitions.

This is the main design advantage for replay-buffer writes. A whole-object update would require a worker or service to read the existing buffer, append locally, and write the full object back. The patch-based path changes the normal append flow to:

```text
collector -> ObjectRef patch
```

instead of:

```text
collector -> replay-buffer service -> full buffer replacement
```

The replay-buffer service remains important for reads and sampling, but append traffic does not need to be serialized through one service method that owns the entire Python list.

## Finding 2: Incremental reads control replay-buffer read cost

Patch writes only help if readers can avoid repeatedly downloading and replaying the full patch history. The example addresses this with Flame's versioned `get_object` behavior and a stateful deserializer.

`ReplayBuffer._fetch()` reads the object through `get_object`:

```python
def _fetch(self) -> dict:
    ref = self.buffer_ref
    if self.force_full_get:
        ref = self._object_ref(endpoint=ref.endpoint, key=ref.key, version=0)
    return self._get_object(ref, deserializer=self._deserializer)
```

The `--force-full-get` flag changes the `ObjectRef` version to `0`, forcing a full read. Normal mode allows the client cache to request only the patches that arrived after the service instance's last cached version when the server can safely return a patch-only response.

The replay-buffer deserializer then applies only the newly seen patch batches:

```python
for delta in deltas[self._materialized_patch_count :]:
    self._materialized_data["transitions"].extend(delta)
    self._materialized_data["total_added"] += len(delta)

self._materialized_patch_count = len(deltas)
return self._materialized_data
```

For a long-lived replay-buffer service instance, this changes repeated `state()` and `sample()` calls from rebuilding against the entire history to advancing a local materialized view. That is the read-side complement to `patch_object`.

## Finding 3: Sampling can run in parallel

The example exposes replay-buffer sample parallelism as a runtime parameter, not as an afterthought:

```python
DEFAULT_SAMPLE_PARALLELISM = 2
```

`main.py` splits one logical batch into multiple sample requests:

```python
sample_request_sizes = _sample_request_sizes(batch_size, sample_parallelism)
sample_futures = [
    buffer_service.sample(buffer, request_size)
    for request_size in sample_request_sizes
]
batches = app.get(sample_futures)
```

`BufferService` is declared with `@app.service(warmup=2)`. For example, `--batch-size 64 --sample-parallelism 2` creates two sample requests whose returned batches sum to 64 transitions. The request count does not set the warm instance count.

This does not add threads inside a single replay-buffer instance. Flame schedules sample requests across service instances. Each instance retains a materialized view per buffer reference; the shared `ObjectRef` is the source of truth.

The expected benefit depends on workload shape. Parallel sampling is most useful when the buffer is large enough, sampling is frequent enough, or the learner can overlap sampling with other distributed work.

The important differentiation is the ownership model. The replay-buffer data lives in the object cache, while `BufferService` instances are handlers around the same `ObjectRef`. Increasing `--sample-parallelism` increases the number of sample requests without changing the logical ownership of the data.

That makes parallel sampling a direct expression of Flame's handler-plus-data model. The application issues more sample requests; Flame keeps the buffer data in shared cache and lets each handler materialize the patches it needs.

## Finding 4: Handler plus data is the general model

The example is best read as a handler-plus-data pattern.

The data is the object stored in Flame's cache:

```python
{"transitions": [], "total_added": 0}
```

The handler is the Python object that defines behavior:

```python
class ReplayBuffer:
    def push(self, transitions): ...
    def state(self): ...
    def sample(self, batch_size): ...
    def merge(self): ...
```

This model is more general than replay buffers. The handler can be passed to remote collectors, registered as a service, and materialized in multiple processes. The data remains addressable through `ObjectRef` and can evolve through patches.

The same structure applies to other append-heavy shared objects, including rollout queues, metrics accumulators, feature caches, evaluation logs, and intermediate datasets produced by many workers.

## Reproduction procedure

Run the distributed example from a Flame console container:

```shell
docker compose exec -it flame-console /bin/bash
cd /opt/examples/rl/replay_buffer
uv run main.py
```

Run the local baseline without a Flame cluster:

```shell
uv run main.py --local
```

Relevant distributed flags:

| Flag | Description | Default |
|---|---|---|
| `--env` | Gymnasium environment | `CartPole-v1` |
| `--iterations` | Collection iterations | `50` |
| `--collections` | Collector calls per iteration | `20` |
| `--steps-per-collection` | Environment steps per collector call | `500` |
| `--batch-size` | Total sampled batch size per iteration | `64` |
| `--sample-parallelism` | Distributed sample requests per batch | `2` |
| `--metrics-json` | Write per-iteration metrics | off |
| `--force-full-get` | Force full replay-buffer reads for baseline measurement | off |
| `--merge-every` | Compact patches every N iterations | mode-dependent |
| `--no-merge` | Disable patch merging | off |

To compare forced full reads with incremental reads on the same workload:

```shell
mkdir -p /tmp/replay-buffer-metrics

uv run main.py \
  --force-full-get \
  --metrics-json /tmp/replay-buffer-metrics/full.json \
  --iterations 50 \
  --collections 20 \
  --steps-per-collection 500 \
  --batch-size 64

uv run main.py \
  --metrics-json /tmp/replay-buffer-metrics/incremental.json \
  --iterations 50 \
  --collections 20 \
  --steps-per-collection 500 \
  --batch-size 64
```

## Example measurement

The example README includes one 500,000-transition run:

| Mode | Total time | Throughput |
|---|---:|---:|
| Local baseline | 2.24s | 223,376.4 transitions/sec |
| Incremental reads | 6.58s | 76,016.1 transitions/sec |
| Forced full reads | 71.84s | 6,959.5 transitions/sec |

The main distributed comparison is incremental reads versus forced full reads. In this run, incremental reads completed in 6.58s and forced full reads completed in 71.84s, a difference consistent with reducing repeated full-history transfer and materialization.

The local baseline is still faster for this specific workload because `CartPole-v1` and random action sampling are cheap, while distributed execution pays service, scheduler, network, and cache overhead. This result should not be read as a claim that distributed replay is always faster than local memory. It shows where patch-based reads and writes improve the distributed path.

## Limitations

The example is a data-path demonstration, not a complete RL training system.

- The collector uses random actions; no policy update or reward-quality conclusion should be drawn.
- The replay buffer does not implement prioritized sampling or capacity-based eviction.
- Parallel sampling duplicates materialized views across service instances, trading memory for concurrency.
- Results depend on cluster size, cache placement, environment cost, batch size, and collection parallelism.
- Local execution remains the right baseline for small environments and small buffers.

## Conclusion

The replay-buffer example demonstrates a practical Flame pattern for append-heavy RL workloads:

1. Use `flamepy.core.patch_object` to append transition batches as deltas.
2. Use versioned `get_object` plus a deserializer to materialize only newly observed patches on repeated reads.
3. Use `flamepy.app` services to issue sample requests in parallel over the same shared replay-buffer object when the buffer is large enough to justify it.
4. Model shared state as handler plus data: Python behavior around an `ObjectRef`, with the data stored and evolved in Flame's cache.

The broader result is a programming model that keeps application code small while giving Flame room to optimize data movement and service placement.

## References

- [Replay buffer example](https://github.com/xflops/flame/tree/main/examples/rl/replay_buffer)
- [ReplayBuffer implementation](https://github.com/xflops/flame/blob/main/examples/rl/replay_buffer/replay_buffer.py)
- [Collector implementation](https://github.com/xflops/flame/blob/main/examples/rl/replay_buffer/collector.py)
- [Incremental object retrieval design](https://github.com/xflops/flame/blob/main/docs/designs/RFE445-incremental-object-get/FS.md)
