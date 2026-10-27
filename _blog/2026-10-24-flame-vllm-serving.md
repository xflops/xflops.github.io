---
layout: blog
title: "Faster Document Reuse with Flame's Data-Aware Scheduling"
date: 2026-10-24
last_modified_at: 2026-10-27
author: "Klaus Ma"
description: "Flame's experimental DAS + LRU placement improves throughput by 16.8% over round-robin vLLM in a controlled two-GPU cache-pressure workload, with native cache-aware controls retained."
categories: ["Flame", "Inference", "Benchmarks"]
tags: ["flamepy", "vllm", "inference", "prefix-caching", "data-aware-scheduling", "das"]
# Logo source: https://github.com/vllm-project/media-kit/blob/main/vLLM-Full-Logo.svg
thumbnail: "/images/vllm-logo.svg"
thumbnail_alt: "vLLM logo"
thumbnail_fit: "contain"
---

*Updated October 27, 2026 with fresh data-aware scheduling (DAS) measurements using KV-cache residency.*

An assistant answering several questions about one document repeatedly processes the same prefix. Keeping that prefix on a GPU that already holds its attention keys and values can save prefill work. Across replicas, placement determines whether that local cache is useful.

In a controlled two-GPU document-reuse workload, **Flame's experimental data-aware scheduling (DAS), with LRU cold placement, delivered 16.8% higher throughput than two prefix-caching vLLM replicas behind round-robin routing**. Six fresh paired runs all favored Flame. The paired 95% bootstrap interval was **+16.0% to +17.8%**.

This is a placement advantage: Flame embeds the same vLLM inference engine. Native vLLM with an equally cache-aware external router was approximately level with Flame in descriptive pilots. We retain that control, the unfavorable random-placement result, and the earlier adapter experiments below.

## A DAS advantage under cache pressure

The table reports arithmetic mean throughput and measured cached-input fractions across six fresh cases per arm. The gain and interval above use the geometric mean of the six paired throughput ratios, with 20,000 run-level bootstrap resamples. Each case measures 192 requests after two excluded warmups.

| Configuration | Mean requests/s | Mean phase time | Cached input tokens |
| --- | ---: | ---: | ---: |
| Native vLLM, round-robin job routing | 3.364 | 57.070 s | 90.56% |
| Flame, DAS + LRU cold placement | **3.931** | **48.847 s** | **96.79%** |

![Six fresh paired runs: Flame DAS plus LRU averages 3.93 requests/s versus 3.36 for round-robin vLLM, with 96.79% versus 90.56% cached input. The paired gain is 16.8%, with a 95% bootstrap interval of 16.0% to 17.8%.](/assets/images/serving-benchmark/das-kv-placement.svg)

Both systems keep all four requests in a job on the same worker. DAS improves placement **across jobs** that revisit the same document. It raises cache reuse while retaining the costs of Flame's sessions, task transfer, scheduling, and result collection inside the phase timer.

### How DAS and session binding work together

The prototype connects real vLLM GPU-cache events to Flame executor attributes:

1. Each persistent GPU worker observes KV blocks being stored, removed, or cleared. The bridge publishes matching resident-prefix keys and retracts keys when the required blocks disappear.
2. Each job supplies affinity keys derived from the model's token IDs: four parent-chained 256-token blocks covering the first 1,024 tokens, salted with the model revision.
3. DAS prefers an eligible idle executor with the greatest overlap between those keys and its published resident prefixes. When there is no overlap and the job has affinity keys, the cold-LRU candidate prefers the executor that has been idle longest. Cache hits retain priority over idle age.
4. The session binds the four related tasks to that worker, where its local vLLM engine can reuse the document prefix. Closing the session makes the persistent worker available for another job.

The LRU rule here controls **cold worker selection**; it does not change vLLM's KV-block eviction policy. Prefix keys are routing metadata. KV tensors remain in GPU memory, full request inputs still reach the worker, and every request generates 16 new tokens. There is no application response cache in this experiment.

The cache-event bridge and cold-placement policy are experimental. The LRU scheduler change was tested in an isolated benchmark binary and has not been deployed as a production default. We did not run a retraction-on/off ablation, so these measurements do not isolate the speedup from attribute retraction alone.

### Why we followed random placement with LRU

Random cold placement improved throughput by **11.7%** across six paired runs, with a 95% bootstrap interval of **+3.6% to +17.1%**. It was less consistent. One run routed 160 requests to one GPU and 32 to the other, reached only 89.13% cache reuse, and ran **6.7% slower** than its matched round-robin reference: 3.127 versus 3.351 requests/s.

We retained that regression and selected LRU for a separate confirmation. Its six pairs used entirely fresh models and measurements, with three Flame-first and three native-first orders fixed before launch. No earlier pilot or random-placement timing entered the LRU estimate. All six LRU runs achieved 96.79% cache reuse and a 96/96 request split across the GPUs; paired gains ranged from 15.6% to 18.5%.

### Keep the native cache-aware control visible

Native vLLM can also benefit from cache-aware routing. In the initial six-arm exploration, the external native routers consumed the same resident-prefix metadata as DAS. The LRU router preferred the least recently released worker on a cold miss; the random router selected randomly on a cold miss. Both retained actual cache-hit priority.

These are **single descriptive pilots**, separate from the repeated comparison above:

| Pilot configuration | Requests/s | Cached input tokens |
| --- | ---: | ---: |
| Native vLLM, round-robin | 3.362 | 90.56% |
| Native vLLM, cache-aware + LRU | 4.018 | 96.79% |
| Native vLLM, cache-aware + random | 3.941 | 96.79% |
| Flame, DAS disabled | 3.004 | 86.95% |
| Flame, DAS + LRU | 3.967 | 96.79% |
| Flame, DAS + random | 3.947 | 96.79% |

The advantage demonstrated by the fresh pairs is over **round-robin placement**. The native cache-aware pilots show that equivalent locality can recover the same benefit. Flame's contribution is connecting cache residency to its task scheduler and keeping related work bound through sessions; the data does not establish a faster inference engine or superiority over an optimized native router.

### The workload and its limits

Both paths use two B200 GPUs, the same pinned BF16 Llama 3.1 8B Instruct checkpoint described below, vLLM 0.28.0, Torch 2.13.0+cu130, eager execution, Triton attention, tensor parallelism 1, prefix caching, 64 active sequences, 8,192 batched tokens, and disabled asynchronous scheduling. Both use the same synchronous KV-event journal instrumentation. Actual prompt-token echoes and output lengths are checked; the protocols and response framing differ.

| Setting | Cache-pressure diagnostic |
| --- | --- |
| Documents | Six; eight shuffled visits per document |
| Jobs | 48 jobs, each containing four known related questions |
| Input construction | Original first 7,936 tokens prepended once to the full original prompt, followed by two unique suffix tokens |
| Input lengths | 16,173–16,191 tokens; model context 16,384 |
| Output | 16 new tokens per request; 192 measured requests per case |
| Admission | One active job at a time |
| KV budget | 4,096 blocks × 16 tokens = **65,536 tokens per GPU** |
| Flame state | Memory-backed session-manager state; filesystem object cache with a 1 GB budget; KV tensors in GPU memory |
| Warmup | Two equally sized shifted traces; measured prefixes remain unseen |

The amplified documents fit the combined cache budget and exceed one replica's cache. This deliberately limited budget exposes the cost of duplicating prefixes across replicas; it is not the default capacity of a B200. More KV memory could let both replicas retain all documents and reduce the placement advantage.

An earlier 8K-token locality diagnostic did not establish a DAS-on advantage over DAS-off, and Flame's paired throughput was 5.2% below a cache-aware native reference. That result is retained in the downloadable summary. The 16K cache-pressure workload is a separate experiment with different admission and cache settings; its absolute throughput should not be compared with that earlier diagnostic.

All four questions are known before a job starts. Flame prequeues FIFO tasks and collects ordered results; native vLLM receives sequential HTTP requests while retaining the selected worker. This is a low-arrival document-query diagnostic, not an interactive-chat or maximum-throughput test. Sustained arrivals, concurrent hot documents, longer outputs, and streaming latency require separate measurements. These scores are not MLPerf results.

All 30 cases across the random exploration and fresh LRU confirmation passed request, placement, runtime-provenance, cache-event, and GPU-release validation. The raw archives were checksummed and independently revalidated locally. The temporary namespace and its GPU reservations were released after its retained benchmark data was removed.

[Download the paired scores, pilot controls, configuration, and provenance](/assets/data/flame-vllm-das-20261027.json). Full raw request and journal archives remain retained locally; the download is a curated score summary. Its settings and throughput values belong to this experiment and should not be compared directly with the earlier burst measurements below.

## Earlier adapter tuning: within 1% on finite bursts

Before the cache-pressure diagnostic, we compared standalone vLLM with a Flame Python service that embeds vLLM. After tuning the Flame adapter, its median completion throughput was **0.55% below standalone vLLM without document reuse and 0.86% below with prefix reuse**. Both met our target of at least 99% of the reference throughput across five fresh pairs per workload. Two reuse pairs missed that target; the worst was 2.03% lower. These are results for short, finite bursts, rather than a general 1% overhead guarantee.

Persistent worker placement improved cache reuse in both systems. Larger batches, asynchronous engine admission, and lossless input compression then brought Flame closer to a fixed vLLM reference. These earlier adapter measurements did not exercise eviction-aware DAS placement.

Both paths use two B200 GPUs, two single-GPU vLLM engines, the same model weights and token inputs, and the same principal engine settings. Standalone vLLM receives individual HTTP requests through a client that keeps each prefix on a stable replica. Flame receives batches through its task path into two persistent worker sessions.

The table shows median requests per second with the observed minimum–maximum across five trials per system. The percentage compares the two medians; the last column shows the range of ratios within the five pairs.

| Workload | Standalone vLLM requests/s | Flame requests/s | Flame vs vLLM median | Paired throughput ratios |
| --- | --- | --- | --- | --- |
| No document reuse | 7.628 [7.624–7.641] | 7.586 [7.579–7.589] | −0.55% | 99.29%–99.49% |
| Prefix reuse | 28.595 [28.570–28.624] | 28.350 [27.989–28.416] | −0.86% | 97.97%–99.37% |

![Median completion throughput and observed trial ranges for Flame and standalone vLLM.](/assets/images/serving-benchmark/gc-tuning.svg)

All 3,200 confirmation requests passed the input, coverage, output-length, and worker-placement checks. Every request generated 16 new tokens. Model loading, initial session setup, and warmup are outside timing; routing, request transfer, compression, decompression, inference, and completion are inside it.

### Keep the engine and workload comparable

The matched experiments use the public BF16 [Llama 3.1 8B Instruct checkpoint](https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct/tree/a2856192dd7c25b842431f39c179a6c2c2f627d1), pinned to revision `a2856192dd7c25b842431f39c179a6c2c2f627d1`. All inference processes use the same pinned runtime image. Adding Flame's SDK leaves the inference packages unchanged.

| Setting | Both paths |
| --- | --- |
| Inference runtime | vLLM 0.28.0; Torch 2.13.0+cu130 |
| Resources | Two B200 GPUs; one shared 20-CPU limit |
| Engine layout | Two replicas, tensor parallelism 1 each |
| Execution | BF16, eager execution, Triton attention |
| Engine limits | Context 32,768; 64 active sequences; 8,192 batched tokens |
| Prefix cache | Enabled |
| Generated output | 16 tokens per request, ignoring early EOS |

We construct two shuffled traces from news text. Each input contains an approximately 8K-token document prefix followed by a question. The first trace contains 64 documents with one question each: 64 requests with no document reuse. The second has four questions per document: 256 requests with prefix reuse. Each trace arrives as one finite burst. Because burst size and concurrency differ, comparisons belong **within each trace**; the rate difference between traces alone cannot isolate the benefit of reuse.

Each case starts fresh engines and runs two complete warmup rounds. Warmup shifts token IDs within the vocabulary, preserving input lengths and prefix relationships while keeping measured prefixes unseen. The final phase also pins each logical shard to the same physical GPU UUID in both systems and verifies that mapping from actual worker records.

Flame uses memory-backed session-manager state (`storage: none`) and a fixed RAM-backed object cache. The memory state is lost on a session-manager restart. This is an experimental configuration, not a production persistence recommendation.

### Prefix affinity helps both systems

Before tuning the adapter, we compared base routing with explicit prefix affinity. The base vLLM client alternates requests between two replica URLs. The base Flame client uses one global session with two workers and batches at most 32 prompts, with a 2 ms formation window.

Affinity uses the model's token IDs. We hash 256-token blocks, chaining each block to the preceding prefix and salting the identity with the model revision, through the first 1,024 tokens. A bounded client map assigns an unseen prefix to the shard with the least cumulative estimated prefill work and retains that assignment. It reads neither document labels nor future requests.

For standalone vLLM, the two shards are stable HTTP replica URLs. For Flame, they are two persistent sessions, each retaining one GPU worker and its own batch queue. Subsequent questions about a prefix reach the same worker, where vLLM can reuse resident KV blocks. The map does not consume live eviction events, so an assignment alone does not prove a cache hit; returned cached-token counts measure actual reuse.

These earlier measurements use batch limit 32 and three repetitions per configuration. Values are median [minimum–maximum]. The four displayed configurations were interleaved within a shared experiment on one physical GPU pair.

| Configuration | No reuse requests/s | Prefix reuse requests/s | Cached input tokens on reuse |
| --- | --- | --- | --- |
| vLLM, alternating replicas | 7.578 [7.559–7.582] | 15.974 [15.967–15.989] | 53.13% |
| Flame, global session and batches | 7.535 [7.533–7.540] | 15.036 [14.659–15.532] | 52.36% |
| vLLM, sticky-prefix client | 7.576 [7.568–7.579] | 28.359 [28.323–28.369] | 74.86% |
| Flame, sticky-prefix sessions and batches | 7.542 [7.540–7.542] | 26.073 [26.025–26.139] | 74.86% |

![Base routing and prefix affinity for Flame and standalone vLLM.](/assets/images/serving-benchmark/flame-vllm-prefix-affinity.svg)

On the reuse trace, affinity raises median throughput by 77.5% for vLLM and 73.4% for Flame. Both reach 74.86% cached input tokens. Flame still trails sticky vLLM by 8.1%, which motivates investigating admission after matching locality.

In these earlier burst comparisons, Flame's core data-aware scheduler remains enabled and unchanged, with affinity hints and publication disabled. The placement improvement comes from the explicit client map and persistent session bindings. A single session with two workers does not itself ensure that every request sharing a prefix reaches the same worker.

### Admit enough work to the engine

The original Flame adapter passes synchronous batches to `LLM.generate()`. Although the client submits a burst, later tasks wait until the current invocation completes. Standalone vLLM's HTTP server admits individual requests continuously. Equal GPU counts therefore do not imply equal engine admission.

We first screen six combinations of batch limit and formation wait. The selected configuration allows 128 prompts per session with a 10 ms formation window. The decoded payload budget rises from 2 to 4 MiB to hold the full inputs. A 128-prompt raw batch is about 3.1 MB; no document content is omitted. On the 64-request trace, the two session queues still distribute work across both GPUs.

We next screen synchronous and asynchronous vLLM APIs, each with raw or zlib-compressed inputs. The asynchronous adapter keeps one event loop and admits all requests in a batch concurrently, returning final outputs in input order. It still executes through Flame's session-manager and executor-manager task path. Invocations on a Flame worker remain serialized, and the adapter does not provide streaming first-token events.

Lossless zlib level 1 compression reduces the total encoded service inputs for the reuse burst from 6,210,432 to 387,795 bytes. The service reconstructs the same full token inputs before inference. This benefit depends on prompt compressibility; these constructed news inputs are particularly compressible. The native reference retains its HTTP protocol, so this comparison includes protocol differences.

Each selected configuration receives five fresh confirmation pairs per trace, excluding its screening pilots. We retain the unsuccessful stages:

| Flame configuration | Median difference without reuse | Median difference with reuse | Both medians within 1% |
| --- | --- | --- | --- |
| Batch 128 and 10 ms formation window | −0.51% | −2.22% | No |
| Add asynchronous API and zlib inputs | −0.60% | −1.01% | No |
| Final configuration with matched GPU shards and startup-heap freeze | −0.55% | −0.86% | Yes |

The asynchronous/compressed phase narrowly misses the strict 99% target on reuse. The final phase receives a different physical GPU pair and a fresh vLLM reference, so its absolute scores cannot establish the isolated effect of its additional changes. This is Flame adapter tuning against a fixed vLLM configuration, rather than an exhaustive search for the best configuration of each system.

### Control the Python startup heap

The final configuration freezes long-lived Python objects after worker initialization. Normal cyclic collection remains enabled for new request objects, and the startup heap is unfrozen before engine teardown. This changes the embedding worker process, separately from vLLM's engine-core GC policy.

Single-trial diagnostics compare normal collection with startup-heap freeze. Maximum per-worker GC pause totals inside inference fall from 8.80 ms to 4.59 ms. Those small observed pauses do not explain the whole throughput variation. Freeze is selected before the final diagnostics and held fixed for confirmation, rather than chosen from their scores.

An initial diagnostic probe was excluded because it called `gc.get_freeze_count()` per batch. That function [walks the permanent heap](https://github.com/python/cpython/blob/3.12/Modules/gcmodule.c#L1829), adding measurement overhead. The corrected observer caches the count at startup, and a regression test prevents that query in the reporting path. Excluded diagnostics contribute no performance scores here.

## Separate this experiment from MLPerf

The prefix-reuse tests are synthetic locality experiments. They do not constitute MLPerf results or establish Server latency compliance.

A separate development control uses the [MLPerf Inference v5.1.1 Llama 3.1 8B workload and LoadGen source](https://github.com/mlcommons/inference/tree/6776245e99dce0600cfc9a6fb61efd310f87de3d/language/llama3.1-8b), with cross-query prefix caching disabled. Its full-duration Offline runs cover the 13,368-sample performance pool and at least 600 seconds:

| Development Offline configuration | Completed requests/s | LoadGen performance result |
| --- | --- | --- |
| Standalone vLLM | 53.38 | VALID |
| Flame, batch 32 | 32.41 | VALID |
| Flame, batch 64 | 53.41 | VALID |

These are individual trials. The original Flame service uses vLLM 0.31.0 while the native path uses 0.28.0, and physical GPU assignments differ. They show why batch occupancy deserved investigation, but cannot isolate framework overhead or establish a repeatable performance advantage. Saved outputs pass the development ROUGE and output-length gates; this does not replace an official accuracy run, model-equivalence validation, or compliance testing.

## What the two experiments establish

The new cache-pressure diagnostic demonstrates a repeatable placement advantage: the experimental Flame DAS + LRU path exceeds round-robin native vLLM throughput by 16.8% across six fresh pairs. Native cache-aware pilots recover similar locality, so the gain is specific to the routing baseline and workload. The earlier finite-burst experiments show that a tuned Flame adapter can also reach at least 99% of standalone vLLM's median completion throughput in those two traces.

In the earlier burst tests, the native client measures completion latency from burst release, while Flame measures from each submission, including batch formation and queueing. Together with batch-level outputs, that difference prevents a claim of equivalent streaming latency. Sustained arrivals, longer and variable answers, hot-prefix queueing, eviction under concurrent load, worker restarts, and startup cost need separate measurements.

The earlier adapter phase validates 768 diagnostic requests and 3,200 independent confirmation requests. Frozen runtime sources, model and image revisions, batch histograms, exact input hashes, output token IDs, paired scores, and cleanup receipts are retained with the benchmark harness. Earlier native locality scores affected by concurrent HTTP-client initialization are excluded; the corrected client prepares one shared opener before timing. All 38 adapter harness tests pass. Both GPUs were released and the temporary pod deleted; that earlier experiment left production Flame configuration unchanged.

The next implementation step is to productize the cache-event bridge, cold placement, and bounded admission, then measure sustained load and streaming latency. These measurements come from development benchmarks. The full raw evidence is retained locally and is not yet available as a public archive.
