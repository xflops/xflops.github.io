---
layout: blog
title: "Evaluating Flame Serving: Data-Aware Scheduling and Inference Overhead"
date: 2026-10-24
last_modified_at: 2026-10-27
author: "Klaus Ma"
description: "Two controlled evaluations of Flame serving: a 0.55–0.86% median throughput difference with matched prefix placement, and a 16.8% DAS gain over round-robin vLLM under cache pressure."
categories: ["Flame", "Inference", "Benchmarks"]
tags: ["flamepy", "vllm", "inference", "prefix-caching", "data-aware-scheduling", "das"]
# Logo source: https://github.com/vllm-project/media-kit/blob/main/vLLM-Full-Logo.svg
thumbnail: "/images/vllm-logo.svg"
thumbnail_alt: "vLLM logo"
thumbnail_fit: "contain"
---

*Evaluation updated October 27, 2026.*

## Abstract

This report evaluates two aspects of Flame serving with an embedded vLLM engine: the end-to-end throughput difference when prefix placement is controlled, and the benefit of data-aware scheduling (DAS) when replicas have limited KV-cache capacity. In the matched-placement study, a prefix-matching client assigns related requests to stable native vLLM replicas or persistent Flame worker sessions. After adapter tuning, Flame's median throughput is 0.55% below native vLLM without document reuse and 0.86% below with reuse, across five fresh pairs per workload. In the cache-pressure study, an experimental integration of DAS with live KV-residency metadata and LRU cold placement achieves 16.8% higher throughput than native vLLM with round-robin job routing across six fresh pairs; the paired 95% bootstrap interval is +16.0% to +17.8%. Native cache-aware routing produces similar observed throughput in single descriptive pilots. The results support a small net serving-path cost under matched placement and a measurable locality benefit relative to round-robin routing in the evaluated workload. They do not isolate DAS scheduling overhead or establish maximum serving capacity.

## 1. Evaluation objectives

Prefix caching reduces repeated prefill computation when requests share an input prefix. With multiple model replicas, this benefit depends on routing requests to workers that retain the corresponding KV blocks. Flame adds sessions, task transport, scheduling, and result collection around the inference engine. An evaluation must therefore distinguish the cost of this serving path from the benefit of its placement decisions.

The two studies address separate questions:

| Study | Placement control | Evaluation objective | Principal result |
| --- | --- | --- | --- |
| A: matched prefix placement | The same prefix-matching rule selects native vLLM replicas and persistent Flame worker sessions | Measure the net serving-path difference with locality controlled | Flame median throughput is 0.55% lower without reuse and 0.86% lower with reuse |
| B: DAS under cache pressure | Flame uses live KV-residency attributes and LRU cold placement; native vLLM uses round-robin job routing | Measure the benefit of data-aware placement across jobs | Flame paired throughput is 16.8% higher |

Study A approximates cache-local placement through a client-side prefix-to-worker map. It does not consume live eviction events, and it does not exercise eviction-aware DAS decisions. Its residual throughput difference includes protocol, admission, serialization, and worker effects. Study B evaluates an experimental application of DAS to current KV residency. The studies use different workloads and admission settings; their absolute throughput values are not directly comparable.

## 2. Placement mechanisms

### 2.1. Prefix-matching placement

The matched-placement client derives routing identities from the model's token IDs. It hashes 256-token blocks, chains each block to the preceding prefix, and salts the identity with the model revision through the first 1,024 tokens. A bounded map assigns an unseen prefix to the shard with the least cumulative estimated prefill work and retains that assignment. The client uses neither document labels nor future requests.

Native vLLM shards are stable HTTP replica URLs. Flame shards are persistent sessions, each retaining a GPU worker and a batch queue. Repeated questions about a prefix are consequently directed to the same model replica. This simulates the locality sought by KV-cache-aware scheduling, but an assignment does not establish current cache residency. Returned cached-token counts provide the reuse measurement.

### 2.2. DAS with KV-residency metadata

In Study B, the prototype connects vLLM GPU-cache events to Flame executor attributes. Each worker observes KV blocks being stored, removed, or cleared. A bridge publishes resident-prefix keys and retracts keys when their required blocks disappear. Jobs provide affinity keys consisting of four parent-chained 256-token blocks covering the first 1,024 tokens.

DAS selects an eligible idle executor with the greatest overlap between job affinity and published resident prefixes. When all overlap scores are zero and affinity is nonempty, the cold-LRU candidate prefers the executor that has been idle longest. Cache-hit preference takes precedence over idle age. The LRU rule applies to cold worker selection and does not modify vLLM's KV-block eviction policy.

A Flame session binds the four related tasks in a job to the selected worker. Closing the session releases that binding while preserving the worker and its local vLLM engine. Native reference clients also retain a worker for all four requests in a job. The principal placement difference is therefore reuse across jobs, rather than within-job affinity.

Prefix attributes contain routing metadata; KV tensors remain in GPU memory. Full request inputs are transferred to the selected worker, and every request generates 16 new tokens. No application response cache is used. The cache-event bridge and cold-LRU scheduler change are experimental and have not been deployed as production defaults.

## 3. Experimental methodology

### 3.1. Common inference configuration

Both studies compare two native vLLM replicas with a Flame service embedding the same inference engine. The matched configurations use the public BF16 [Llama 3.1 8B Instruct checkpoint](https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct/tree/a2856192dd7c25b842431f39c179a6c2c2f627d1), pinned to revision `a2856192dd7c25b842431f39c179a6c2c2f627d1`. The inference runtime image is pinned, and installing the Flame SDK leaves the inference packages unchanged.

| Setting | Configuration |
| --- | --- |
| Hardware | Two B200 GPUs; shared 20-CPU limit |
| Inference runtime | vLLM 0.28.0; Torch 2.13.0+cu130 |
| Engine layout | Two replicas; tensor parallelism 1 per replica |
| Execution | BF16, eager execution, Triton attention |
| Engine limits | 64 active sequences; 8,192 batched tokens |
| Prefix caching | Enabled |
| Generated output | 16 tokens per request, ignoring early EOS |

Each case starts fresh engines and executes two complete warmup rounds. Warmup shifts token IDs within the model vocabulary while preserving input lengths and prefix relationships, leaving measured prefixes unseen. Model loading and warmup are excluded from measured phase duration. Inputs, generated output lengths, and actual worker placement are validated.

### 3.2. Study A: matched-placement bursts

Study A uses two shuffled news-text traces. Each input contains an approximately 8K-token document prefix followed by a question. The no-reuse trace contains 64 documents with one question each, for 64 requests. The reuse trace contains four questions per document, for 256 requests. Each trace is submitted as a finite burst. Burst size and concurrency differ between traces, so their throughput difference does not isolate the effect of reuse.

The model context limit is 32,768 tokens. Native vLLM receives individual HTTP requests through the prefix-matching client. Flame receives batches through two persistent worker sessions. The final adapter uses a batch limit of 128, a 10 ms formation window, asynchronous engine admission within each batch, and lossless zlib level 1 input compression. Calls on a Flame worker remain serialized, and the adapter returns batch-level completions without streaming first-token events.

Flame uses memory-backed session-manager state (`storage: none`) and a fixed RAM-backed object cache. Initial session setup is excluded from timing. Routing, batch formation, request transfer, compression, decompression, inference, and completion are included. The final phase pins logical shards to the same physical GPU UUIDs in both systems and verifies that mapping from worker records.

Each final configuration is evaluated in five fresh pairs per workload, excluding screening pilots. Results are reported as median requests/s with the observed minimum–maximum. The reported percentage difference compares the two medians; individual paired ratios are reported separately.

### 3.3. Study B: document reuse under cache pressure

Study B uses six documents with eight shuffled visits per document. Each visit is a job containing four known related questions, producing 48 jobs and 192 measured requests per case. One job is active at a time. Flame prequeues FIFO tasks and collects results in order; native vLLM receives sequential HTTP requests while retaining the selected worker.

| Setting | Cache-pressure configuration |
| --- | --- |
| Input construction | Original first 7,936 tokens prepended once to the full original prompt, followed by two unique suffix tokens |
| Input lengths | 16,173–16,191 tokens |
| Model context | 16,384 tokens |
| KV budget | 4,096 blocks × 16 tokens = 65,536 tokens per GPU |
| Asynchronous scheduling | Disabled in both paths |
| Instrumentation | Identical synchronous KV-event journal instrumentation |
| Flame state | Memory-backed session-manager state; filesystem object cache with a `1G` budget |

The amplified document set fits the aggregate cache budget but exceeds one replica's cache. The deliberately limited budget exposes the effect of duplicating prefixes across replicas; it is not the default KV capacity of a B200. Actual prompt-token echoes and output lengths are checked. Phase duration includes job routing, session operations, task transfer, generation, result collection, and residency-metadata handling. Protocols and response framing differ between the systems.

The initial experiment contains six descriptive pilots and six fresh Flame-random/native-round-robin pairs. Following a random-placement regression, LRU is selected for a separate confirmation of six entirely fresh LRU/round-robin pairs. Each confirmation uses three Flame-first and three native-first orders fixed before launch. No pilot or random-placement timing enters the LRU estimate.

Tables report arithmetic mean requests/s and measured cached-input fractions. The comparison statistic is the geometric mean of paired run-level throughput ratios. Percentile bootstrap intervals use 20,000 resamples of the six log ratios, with seeds 637 and 639 for the random and LRU confirmations, respectively. Requests within a run are not treated as independent statistical replicates.

## 4. Results

### 4.1. Matched prefix placement

The final Study A configuration produces median throughput differences of −0.55% without reuse and −0.86% with reuse. Both medians are within 1% of the native reference. Two reuse pairs fall below 99% of native throughput; the largest individual deficit is 2.03%.

| Workload | Native vLLM requests/s | Flame requests/s | Difference between medians | Individual paired ratios |
| --- | --- | --- | --- | --- |
| No document reuse | 7.628 [7.624–7.641] | 7.586 [7.579–7.589] | −0.55% | 99.29%–99.49% |
| Prefix reuse | 28.595 [28.570–28.624] | 28.350 [27.989–28.416] | −0.86% | 97.97%–99.37% |

![Study A: median completion throughput and observed trial ranges for Flame and native vLLM with matched prefix placement.](/assets/images/serving-benchmark/gc-tuning.svg)

*Figure 1. Matched-placement throughput. Bars show medians and whiskers show observed ranges across five fresh trials per system and workload.*

These results indicate a small net throughput difference for the tuned Flame serving path under the evaluated burst conditions. They include the effects of batching, compression, and worker tuning, and do not measure DAS scheduling cost in isolation.

### 4.2. DAS placement under cache pressure

In the fresh LRU confirmation, Flame achieves a mean of 3.931 requests/s compared with 3.364 requests/s for native round-robin routing. The geometric mean paired gain is 16.8%, with a 95% bootstrap interval of +16.0% to +17.8%. All six pairs favor Flame; individual gains range from 15.6% to 18.5%.

| Configuration | Mean requests/s | Mean phase duration | Cached input tokens |
| --- | ---: | ---: | ---: |
| Native vLLM, round-robin job routing | 3.364 | 57.070 s | 90.56% |
| Flame, DAS + LRU cold placement | 3.931 | 48.847 s | 96.79% |

![Study B: six fresh paired runs. Flame DAS plus LRU averages 3.93 requests/s versus 3.36 for round-robin vLLM, with 96.79% versus 90.56% cached input. The paired gain is 16.8%, with a 95% bootstrap interval of 16.0% to 17.8%.](/assets/images/serving-benchmark/das-kv-placement.svg)

*Figure 2. DAS under cache pressure. The left panel shows mean throughput and observed ranges; the right panel shows the six paired gains and their aggregate estimate with a 95% bootstrap interval.*

All six LRU runs achieve 96.79% cache reuse and a 96/96 request split across the GPUs. The increased cached-input fraction is consistent with reduced repeated prefill work across document visits. Both paths retain within-job affinity, and Flame's session and task costs remain included in phase duration.

### 4.3. Random cold placement

Random cold placement yields a geometric mean paired gain of 11.7%, with a 95% bootstrap interval of +3.6% to +17.1%. One run exhibits a 160/32 request split, 89.13% cached input, and a 6.7% throughput deficit relative to its matched reference: 3.127 versus 3.351 requests/s. This regression is included in the reported estimate.

The observed variability motivates the independent LRU confirmation. The results document more consistent placement and reuse in those six LRU runs; the two confirmations are not a paired statistical comparison between LRU and random policies.

### 4.4. Native cache-aware controls

In the initial six-arm exploration, native cache-aware routers consume the same resident-prefix metadata as DAS. Both prioritize cache overlap. On a cold miss, the LRU router selects the least recently released worker, while the random router selects randomly. These controls are single descriptive pilots and do not enter either confirmation interval.

| Pilot configuration | Requests/s | Cached input tokens |
| --- | ---: | ---: |
| Native vLLM, round-robin | 3.362 | 90.56% |
| Native vLLM, cache-aware + LRU | 4.018 | 96.79% |
| Native vLLM, cache-aware + random | 3.941 | 96.79% |
| Flame, DAS disabled | 3.004 | 86.95% |
| Flame, DAS + LRU | 3.967 | 96.79% |
| Flame, DAS + random | 3.947 | 96.79% |

The cache-aware native pilots achieve similar observed throughput and cache reuse to Flame DAS. These observations support the interpretation that locality accounts for the advantage over round-robin routing. The pilots do not establish statistical equivalence or a throughput advantage over an optimized native router.

### 4.5. Placement and adapter sensitivity in Study A

A preliminary Study A experiment evaluates base routing and explicit prefix affinity using batch limit 32 and three repetitions per configuration. The four configurations are interleaved on one physical GPU pair. Values are median [minimum–maximum].

| Configuration | No reuse requests/s | Prefix reuse requests/s | Cached input tokens on reuse |
| --- | --- | --- | --- |
| Native vLLM, alternating replicas | 7.578 [7.559–7.582] | 15.974 [15.967–15.989] | 53.13% |
| Flame, global session and batches | 7.535 [7.533–7.540] | 15.036 [14.659–15.532] | 52.36% |
| Native vLLM, sticky-prefix client | 7.576 [7.568–7.579] | 28.359 [28.323–28.369] | 74.86% |
| Flame, sticky-prefix sessions and batches | 7.542 [7.540–7.542] | 26.073 [26.025–26.139] | 74.86% |

![Preliminary Study A measurements: base routing and explicit prefix affinity for Flame and native vLLM.](/assets/images/serving-benchmark/flame-vllm-prefix-affinity.svg)

*Figure 3. Preliminary routing comparison. Values are medians and observed ranges across three repetitions per configuration.*

Prefix affinity increases median reuse throughput by 77.5% for native vLLM and 73.4% for Flame. Both affinity-enabled paths reach 74.86% cached input, while Flame initially remains 8.1% below the sticky native reference. In these tests, Flame's core DAS policy remains enabled, but task-affinity hints and executor publication are disabled. Placement is determined by the client map and persistent sessions.

The original synchronous adapter calls `LLM.generate()` on complete batches, whereas native vLLM admits individual HTTP requests continuously. Adapter screening therefore examines both batch occupancy and engine admission. The selected batch configuration uses 128 prompts per session and a 10 ms formation window. Its decoded payload budget increases from 2 to 4 MiB to accommodate a raw batch of approximately 3.1 MB without omitting input content.

The asynchronous adapter retains one event loop and admits requests within each batch concurrently, returning final outputs in input order. Lossless zlib level 1 compression reduces encoded reuse-trace inputs from 6,210,432 to 387,795 bytes. Native vLLM retains its HTTP protocol; compression is therefore part of the measured protocol difference. The benefit depends on the compressibility of the constructed news inputs.

Each selected stage receives five fresh confirmation pairs per trace, excluding screening pilots:

| Flame configuration | Median difference without reuse | Median difference with reuse |
| --- | --- | --- |
| Batch 128; 10 ms formation window | −0.51% | −2.22% |
| Asynchronous API; zlib inputs | −0.60% | −1.01% |
| Matched GPU shards; startup-heap freeze | −0.55% | −0.86% |

The final phase uses a different physical GPU pair and a fresh native reference. Its absolute throughput cannot isolate the effect of its additional changes. The evaluation tunes Flame against a fixed native configuration and is not an exhaustive optimization of both systems.

The final worker configuration freezes long-lived Python objects after initialization while retaining cyclic collection for new request objects. Freeze is selected before the final diagnostics and held fixed during confirmation; the startup heap is unfrozen before teardown. In single-trial diagnostics, maximum per-worker GC pause totals during inference decrease from 8.80 to 4.59 ms. These pauses do not explain the full throughput variation. An initial probe is excluded because it invokes `gc.get_freeze_count()` per batch; that function [walks the permanent heap](https://github.com/python/cpython/blob/3.12/Modules/gcmodule.c#L1829). The corrected observer caches the startup count, and a regression test prevents that query in the reporting path. Excluded probes contribute no performance scores.

## 5. Validity and limitations

The findings are conditional on the evaluated configurations. Study A measures short finite bursts with particularly compressible inputs. Study B uses amplified synthetic documents, a deliberately limited KV budget, one active job, and short outputs. Additional KV capacity could allow both replicas to retain the complete document set and reduce the placement benefit. Neither study establishes maximum throughput under sustained arrivals.

An earlier 8K-token locality diagnostic did not establish a DAS-on advantage over DAS-off, and Flame's paired throughput was 5.2% below a cache-aware native reference. That result is included in the downloadable summary. The different admission, cache, and workload settings preclude direct comparison of its absolute throughput with Study B.

The six-pair bootstrap intervals characterize run-level variation for a fixed trace. They do not quantify variation across document distributions, hardware types, or production traffic. The native cache-aware controls are single pilots. Attribute retraction was not evaluated in an on/off ablation, so its individual performance contribution remains unmeasured. The matched-placement study likewise does not isolate the cost of DAS's scoring and scheduling operations.

Study B assumes that all four questions are known before a job starts. Its FIFO task submission and sequential native HTTP protocol differ from interactive conversations. In Study A, native completion latency is measured from burst release, while Flame latency is measured from submission with batch formation and queueing. Batch-level completion and these differing origins prevent a claim of equivalent streaming latency. Concurrent hot prefixes, variable output lengths, eviction under sustained load, worker restarts, and startup costs require further evaluation.

### 5.1. MLPerf development control

The two locality studies are not MLPerf results and do not establish Server latency compliance. A separate development control uses the [MLPerf Inference v5.1.1 Llama 3.1 8B workload and LoadGen source](https://github.com/mlcommons/inference/tree/6776245e99dce0600cfc9a6fb61efd310f87de3d/language/llama3.1-8b), with cross-query prefix caching disabled. Its full-duration Offline trials cover the 13,368-sample performance pool and at least 600 seconds:

| Development Offline configuration | Completed requests/s | LoadGen performance result |
| --- | --- | --- |
| Native vLLM | 53.38 | VALID |
| Flame, batch 32 | 32.41 | VALID |
| Flame, batch 64 | 53.41 | VALID |

These are individual trials. The original Flame service uses vLLM 0.31.0, whereas the native path uses 0.28.0, and physical GPU assignments differ. The results motivate the batch-occupancy investigation but cannot isolate framework overhead or establish a repeatable advantage. Saved outputs pass the development ROUGE and output-length gates; an official accuracy run, model-equivalence validation, and compliance testing remain separate requirements.

## 6. Validation and reproducibility

The final Study A phase validates 768 diagnostic requests and 3,200 independent confirmation requests. All 38 adapter harness tests pass. Earlier native locality scores affected by concurrent HTTP-client initialization are excluded; the corrected client prepares one shared opener before timing.

All 30 cases in the Study B exploration and fresh LRU confirmation pass request, placement, runtime-provenance, cache-event, and GPU-release checks. Actual prompt tokens, output lengths, KV capacity, publication/retraction events, and source and binary identities are validated. The raw archives are checksummed and independently revalidated locally. The temporary namespace and its GPU reservations are released after the benchmark data is retained and its temporary storage removed.

[The public score summary](/assets/data/flame-vllm-das-20261027.json) contains the Study B paired scores, descriptive controls, configuration, source and binary provenance, and the earlier 8K diagnostic. Full request and journal archives remain retained locally and are not yet available as a public archive. Study A runtime sources, paired scores, input hashes, output token IDs, batch histograms, and cleanup receipts are also retained with the development harness.

## 7. Conclusion

The matched-placement study observes a 0.55–0.86% median throughput deficit for a tuned Flame serving path relative to native vLLM in two finite-burst workloads. The cache-pressure study observes a 16.8% paired throughput gain from the experimental DAS + LRU integration relative to round-robin native vLLM, with a 95% bootstrap interval of +16.0% to +17.8%. These findings separate a small net serving-path difference under matched locality from the benefit of data-aware placement under limited cache capacity. Similar observed performance in native cache-aware pilots identifies routing and locality as the relevant advantage in the latter comparison. Further work is required to establish behavior under sustained concurrency and streaming latency constraints.
