---
layout: blog
title: "Training a Search-R1 Agent with Flame"
date: 2026-10-20
author: "Klaus Ma"
description: "How Flame simplifies Search-R1 training with Python services, warm GPU executors, elastic rollouts, gang-scheduled trainers, and incremental weight transfer, demonstrated in a 100-step run."
categories: ["Flame", "Reinforcement Learning", "AI"]
tags: ["flame", "flamepy", "search-r1", "grpo", "vllm", "object-cache", "gang-scheduling"]
# Logo source: https://github.com/PeterGriffinJin/Search-R1/blob/main/public/logo.png
thumbnail: "/images/search-r1-logo.png"
thumbnail_alt: "Search-R1 logo"
thumbnail_fit: "contain"
---

An agent that can call a search tool still has to learn when to search, what to ask, and when it has enough information to answer. Training that behavior creates a distributed loop: generate several attempts, retrieve evidence along the way, score the answers, update the policy, and send the new weights back to the generators.

Flame's [Search-R1 training example](https://github.com/xflops/flame/tree/main/examples/rl/search-r1) runs this loop as distributed Python services. The driver uses `flamepy.app` to run vLLM rollouts and data-parallel trainers as services, while Flame's object cache carries trajectories, training batches, and weight updates.

For the application developer, Flame brings these pieces into one runtime: declare Python services and their resource needs, submit calls from the training loop, and let the engine allocate executors, distribute the project, and move shared objects. Stateful services keep models and indexes warm across calls. Rollouts can grow with pending work, while the trainers receive the coordinated allocation their collectives require.

In the reported 100-step run, Qwen2.5-3B-Instruct improved from **14.5% to 47.0% held-out exact match** on 200 questions. The run used 14 rollout GPUs and two trainer GPUs across a two-node cluster, completed without dropped rollout calls, and averaged **24.3 seconds per step over steps 3–100**. These are results from one demo run, with a small evaluation set and a purpose-built retrieval corpus. The [training report](https://github.com/xflops/flame/blob/main/docs/reports/search-r1/training/2026-10-20.md) records the measurements and limitations.

## What Flame brings to the training loop

Search-R1 combines two scheduling patterns. Rollouts are independent tasks with variable completion times; trainer replicas form a group that must run together. Both carry expensive state between steps, and both exchange data larger than a typical task message. Flame provides mechanisms for each of those needs within the same application.

| Flame feature | How the demo uses it | Practical advantage |
| --- | --- | --- |
| Python service API and project packaging | `@app.service` exposes rollout and trainer classes; Flame packages the project and installs its declared dependencies on workers. | Keep the training driver in Python and launch remote services without a separate application manifest or manual project copy to each worker. |
| Warm, stateful executors | Service instances retain vLLM engines, retrieval indexes, policy replicas, and optimizer state between calls. | Reuse expensive initialization across many tasks and training steps. |
| Elastic sessions and resource requests | Rollouts request CPU, memory, and GPU resources and can add executors while calls are pending. | Size the initial pool with `warmup` and let demand drive additional rollout capacity when cluster resources permit. |
| Gang scheduling | In the reported run, the fixed trainer session received its minimum executor count together. | Avoid partial resource allocation that leaves a trainer waiting for an unscheduled collective partner. |
| Versioned object cache and incremental fetch | Trajectories and batches travel by reference; weight shards receive appended delta parts. | Keep large data out of task messages and let existing rollout executors fetch only the weight parts they have not seen. |

The application still owns the search protocol, reward, policy update, and NCCL group. Flame supplies the execution and data-management mechanisms around them. This lets the example combine vLLM, PyTorch, and BM25 in ordinary Python services while sharing a common runtime for scheduling and object transfer.

## What the agent learns

The example follows the tool-use protocol of [Search-R1](https://github.com/PeterGriffinJin/Search-R1): the model generates reasoning inside `<think>` tags, requests retrieval with `<search>query</search>`, reads passages supplied inside `<information>` tags, and returns its final answer inside `<answer>` tags.

During a rollout, generation stops at a completed search request or answer. If the model requests a search, the executor queries its local BM25 index, appends the retrieved passages to the context, and resumes generation. The reported configuration allows up to four searches per sample.

The reward is binary exact match against the gold answer, after normalization of case, punctuation, articles, and whitespace. There is no separate reward for searching more often. Search is useful only insofar as it helps produce the correct answer.

Training uses group-relative advantages: five attempts at the same question are scored relative to their group's mean and standard deviation. If every attempt gets the same reward, the group provides no relative learning signal and is left out of the update. Of the 350 samples generated in each reported step, about 140–200 contributed to training.

Retrieved passages remain in the model's context, but their tokens are masked out of the training loss. The policy learns from the tokens it generated, including its search requests and answers.

## A training loop made of services

The driver holds no model and needs no GPU. It samples questions, submits remote calls, computes advantages, and coordinates updates. The GPU state lives in two service types:

| Component | State kept by each executor | Work per call |
| --- | --- | --- |
| `Rollout` | One vLLM engine, a BM25 index, and a CPU copy of published weights | Apply new weights and generate search-and-answer trajectories. |
| `Trainer` | A full policy replica with fp32 master weights, Adam state, and a frozen reference model | Train on its batch slice and all-reduce gradients with the other replicas. |

The service declarations express the different resource and scheduling needs. The following declarations are from the [rollout](https://github.com/xflops/flame/blob/1c00f3c6/examples/rl/search-r1/src/rollout.py) and [trainer](https://github.com/xflops/flame/blob/1c00f3c6/examples/rl/search-r1/src/trainer.py) modules used by the reported October 20 example:

```python
@app.service(resreq="cpu=8,mem=64g,gpu=1", warmup=ROLLOUTS)
class Rollout:
    ...

@app.service(
    resreq="cpu=16,mem=128g,gpu=1",
    autoscale=False,
    warmup=TRAINERS,
)
class Trainer:
    ...
```

Rollouts can autoscale as calls accumulate. `warmup` sets their initial executor count; it is not a cap. The trainer group has a fixed size because its replicas must participate together in NCCL collectives.

The [current trainer](https://github.com/xflops/flame/blob/main/examples/rl/search-r1/src/trainer.py) instead declares `@app.service(resreq="cpu=16,mem=128g,gpu=1", batch_size=TRAINERS)` without warmup. Pending trainer calls request the group together, while idle executors can be shared with rollouts. The measurements below describe the historical configuration, not a new run of this updated scheduler.

These classes are long-lived service instances. A new rollout call reuses the executor's loaded model and index; a trainer update reuses its policy and optimizer. That reuse is particularly useful for an iterative workload: each step sends new work to already initialized services. The report does not isolate a cold-start speedup, but the implementation avoids rebuilding those objects for every task.

Each step follows the same sequence:

1. Fan out questions to rollout executors and collect the trajectories.
2. Compute group-relative advantages and put the training batch in object cache.
3. Call every trainer replica, each of which processes its slice of the batch.
4. All-reduce gradients, then update each replica's policy.
5. Have rank 0 publish the new bf16 weights for subsequent rollouts.

Trajectories and training batches pass through object references because Flame task inputs and outputs have a 128 KB limit. NCCL carries the gradients directly between trainer replicas; the object cache carries application data and published weights.

## Keep retrieval beside generation

Every rollout executor builds an in-memory BM25 index from the corpus. Search is a local call inside that executor, so a generation task can retrieve evidence without waiting for another service to acquire resources.

This placement came from a failure in an earlier version. A separate retriever service could be starved while the rollout tasks waiting for it held the available executors. The [October 17 report](https://github.com/xflops/flame/blob/main/docs/reports/search-r1/training/2026-10-17.md) describes that stall. Moving retrieval into the rollout service removed the resource dependency, at the cost of keeping an index copy in every rollout executor.

The corpus is built from the context paragraphs of the selected HotpotQA training and validation questions. This makes the experiment self-contained, but also defines its evaluation scope: it tests learning to use this retriever and corpus. Its scores are not directly comparable with published Search-R1 benchmarks.

## Start the trainer group together

In the reported run, with two trainers, `autoscale=False, warmup=2` gives the trainer session a minimum and maximum of two executors. Flame's gang scheduling binds the whole minimum together. This prevents one trainer from entering a collective while its partner remains unscheduled for lack of resources.

After allocation, the trainers register their executor IDs and addresses in a shared cache object. Sorting those IDs assigns ranks, and rank 0 provides the NCCL rendezvous address. The driver chooses one rendezvous port for the entire group before issuing the join calls.

Gang scheduling provides the resource allocation. Rank assignment and NCCL initialization remain application logic. It also does not prescribe node placement: both trainers ran on the same node in the 100-step experiment. A separate three-step smoke run exercised trainers on two nodes, but the full accuracy run did not test cross-node NCCL.

## Publish the weight changes

The bf16 model weights occupy about 6.17 GB. Sending that full payload after every small policy update would add substantial copy, serialization, upload, and download work.

The example keeps fp32 master weights for training and compares the bf16 export with the previously published version. At the learning rate used here, many fp32 changes leave the rounded bf16 value unchanged. The export path uses that property:

- The first publication stores the full weights in shards.
- Later publications append changed element indices and their new bf16 values to each shard object.
- If more than a third of a tensor changes, the exporter sends the whole tensor instead.
- Each rollout executor fetches unseen parts, patches its CPU copy, and loads only changed tensors into vLLM.

This preserves the published bf16 values exactly. The engine also clears its prefix cache after loading a new weight version.

In steady state, the 100-step run published about **165 MB per step**, compared with the 6.17 GB model. Export took about 0.4 seconds; the slowest rollout executor spent about 0.9 seconds fetching and applying the delta on CPU, then 1.7 seconds loading it into vLLM. The first synchronization still transfers the full model, and a new executor must read the accumulated parts to catch up. The saving depends on how many bf16 values change; it is not a fixed compression ratio.

This is where Flame's object-cache API becomes a performance advantage. The application encodes the changed values; Flame's versioned objects, append operations, and incremental reads deliver the new parts to each consumer. In the earlier [weight-sync experiment](https://github.com/xflops/flame/blob/main/docs/reports/search-r1/training/2026-10-17.md), switching from full-weight publication to this delta path reduced mean steady-state step time from **70.8 to 38.4 seconds**, about **1.8 times the throughput**. Those averages cover only seven to eight steps per variant. They measure the benefit of the application's delta encoding together with the cache's incremental transfer, and use a different configuration from the later 24.3-second run.

## What the complete run showed

The experiment generated 70 prompts per step, split into 14 calls of five prompts. With five samples per prompt, that produced 350 trajectories per step and 35,000 samples across the run. Fourteen rollout executors handled those calls, alongside two data-parallel trainers, on two eight-GPU nodes.

Greedy evaluation used the same 200 held-out questions throughout:

| Training step | 0 | 20 | 40 | 60 | 80 | 100 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Exact match | 14.5% | 33.0% | 40.0% | 41.0% | 45.0% | 47.5% |

A second evaluation of the final weights returned 47.0%; the report leaves that generation variation unexplained. With only 200 questions, small differences between nearby evaluations should be treated cautiously. This was one run with one seed.

Mean training reward rose from 0.33 over the first ten steps to 0.58 over the last ten. Average searches per sample rose from about 1.04 early in training to 2.02 over steps 51–100. More searches accompanied better answers in this run, although that does not establish that every additional search was useful.

The sum of training-step times was 2,471 seconds, about 41 minutes. That figure excludes setup and evaluation time. After the first two steps' full-weight synchronization costs, the average step broke down as follows:

| Phase | Mean time, steps 3–100 |
| --- | ---: |
| Rollout phase | 14.3 s |
| Policy update, as seen by the driver | 9.5 s |
| Complete step | 24.3 s |

These timings also expose the main utilization limit. The loop is synchronous: trainers wait during generation, and rollout GPUs wait during the update. In that run, all 16 GPUs stayed allocated, but the report estimates useful work at no more than roughly half of the available GPU-seconds. Overlapping generation with updates could reduce that idle time, while introducing policy lag; the demo has not tested that change.

## Run the example

Use a checkout of Flame's `main` branch, a configured client with the Flame SDK and `datasets`, and a GPU cluster with enough device memory for the model and trainer state. The example initializes executors with Python 3.12 and declares its worker dependencies, including vLLM 0.31.0, in `pyproject.toml`.

Run from the example directory so Flame packages the intended project:

```bash
cd examples/rl/search-r1

python3 src/train.py \
  --model Qwen/Qwen2.5-3B-Instruct \
  --steps 100 \
  --prompts-per-step 70 \
  --prompts-per-task 5 \
  --group-size 5 \
  --rollouts 14 \
  --trainers 2 \
  --out sr1-out
```

The driver creates the application and services through `flamepy.app`; no separate `flmctl deploy` step is needed. It writes per-step metrics to `sr1-out/metrics.jsonl` and weight references to `sr1-out/checkpoint.json`. The checkpoint file names cache objects; it is not a standalone model archive or a complete optimizer checkpoint.

For the reported cluster, `cluster.limits.node.maxExecutors=8` matched the GPUs per node. The Flame Helm chart provides settings for a memory-backed object-cache volume and a configurable open-file limit. The run used `objectCache.openFiles=524288`: the cache keeps two files open per served object, so a container limit of 1,024 can be exhausted after a few hundred objects.

This remains a training demo. Each trainer holds a full model replica and optimizer state on one GPU, the loop has no replay buffer, and trainer loss has no automatic NCCL-group recovery.

Flame makes this experiment easier to build and run by combining Python project distribution, warm service instances, elastic rollout scheduling, coordinated trainer allocation, and versioned data transfer. The 100-step run demonstrates those mechanisms working together across 16 GPUs. The delta-sync experiment shows a measurable gain from using incremental object transfer for frequent policy updates. The same execution pattern applies to other iterative agent workloads: retain expensive state, fan out independent tasks, coordinate collective work, and publish shared updates between iterations.

## References

- [Search-R1: Training LLMs to Reason and Leverage Search Engines with Reinforcement Learning](https://github.com/PeterGriffinJin/Search-R1) — the original project and search-and-reason protocol.
- [Search-R1 on Flame: example README](https://github.com/xflops/flame/blob/main/examples/rl/search-r1/README.md) — requirements, project layout, training command, and limitations.
- [RFE584: Search-R1 demo design](https://github.com/xflops/flame/blob/main/docs/designs/RFE584-search-r1-demo/FS.md) — the application design and component responsibilities.
- [Flame App setup guide](https://github.com/xflops/flame/blob/main/docs/tutorials/app-setup.md) — Python application initialization and service setup.
- [Training driver](https://github.com/xflops/flame/blob/main/examples/rl/search-r1/src/train.py), [rollout service](https://github.com/xflops/flame/blob/main/examples/rl/search-r1/src/rollout.py), and [trainer service](https://github.com/xflops/flame/blob/main/examples/rl/search-r1/src/trainer.py) — orchestration, resource declarations, trainer-group formation, and policy updates.
- [Weight-delta encoding](https://github.com/xflops/flame/blob/main/examples/rl/search-r1/src/delta.py) and [rollout engine](https://github.com/xflops/flame/blob/main/examples/rl/search-r1/src/engine.py) — incremental weight representation, application of updates, and the search loop.
- [October 17 weight-sync report](https://github.com/xflops/flame/blob/main/docs/reports/search-r1/training/2026-10-17.md) — the full-weight versus delta-sync experiment, timings, and operational findings.
- [October 20 complete training report](https://github.com/xflops/flame/blob/main/docs/reports/search-r1/training/2026-10-20.md) and [driver log](https://github.com/xflops/flame/blob/main/docs/reports/search-r1/training/2026-10-20-driver.txt) — the 100-step run, accuracy, throughput, utilization analysis, and evaluation caveats.
- [Flame Helm chart values](https://github.com/xflops/flame/blob/main/charts/flame/values.yaml) — cluster executor limits and object-cache volume and open-file settings.
