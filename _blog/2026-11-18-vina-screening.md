---
layout: blog
title: "Screening 100 Compounds with AutoDock Vina on Flame"
date: 2026-11-18
description: "Screen 100 ABL1 library compounds and an imatinib reference with AutoDock Vina, reusing initialized engines across Flame executors on two Linux workers."
categories: ["Flame", "Scientific Computing"]
tags: ["flamepy", "autodock-vina", "virtual-screening", "sessions"]
# Logo source: https://vina.scripps.edu/wp-content/uploads/sites/55/2020/12/vina_logo.png
thumbnail: "/images/autodock-vina-logo.png"
thumbnail_alt: "AutoDock Vina logo"
thumbnail_fit: "contain"
---

A virtual screen of 100 distinct ABL1 library compounds and an imatinib reference was conducted with AutoDock Vina on Flame. All 101 tasks completed successfully across nine Python service instances on two Linux workers. The run produced 101 docked poses and a ranked score table.

The implementation used the same docking class for local and distributed execution, with changes confined to client submission and result collection. The session remained open after completion to support subsequent batches. Executor instances retained initialized Vina engines, resulting in 92 invocations that reused receptor state.

## Execution model

Vina provided molecular search, scoring and affinity maps. Flame provided service execution, resource allocation, task scheduling and remote result delivery. Docking logic remained in the VinaScreen class, and worker placement was handled by the scheduler.

| Workflow concern | How this example handles it with Flame | Evidence from the screen |
| --- | --- | --- |
| Distribute a ligand library | Submit one remote method call per ligand; Flame schedules the tasks across workers. | 101 tasks ran on two worker nodes. |
| Retain initialized engines | Construct Vina and its maps once per service instance, then reuse that instance on its executor. | Nine engine instances served 101 calls, including 92 warm invocations. |
| Continue a screen | Keep the service session open and submit another ligand batch through its handle. | The 101-task session was retained with --keep. |
| Assign resources | Request one CPU and 2 GiB per executor and configure Vina with cpu=1. | The client used the same service declaration for every ligand. |
| Inspect progress | Track the application, session and task states through Flame. | The retained session records 101 successful tasks; the screenshots below show it in progress. |

Vina's Python API already allows an initialized engine to be reused locally. Flame carries that pattern across executor processes on multiple machines. Engine initialization occurred nine times in this run, rather than once for every ligand. The recorded setup total was 24.41 seconds; docking dominated the work.

Remote calls return futures, so the client can collect finished ligands without waiting for submission order. This example adds incremental ranked CSV files, pose files and a provenance manifest around those results. Those scientific output formats belong to the example code, while Flame handles dispatch and result delivery.

### Local and distributed execution

The same VinaScreen class runs locally and on Flame. Its constructor and dock method contain no Flame API calls. Local execution creates the class directly:

```python
screen = VinaScreen(job.receptor, job.center, job.box_size, cpu=1)
results = [screen.dock(name, pdbqt) for name, pdbqt in job.ligands]
```

Distributed execution used app.init, app.service and a remote service handle, followed by future collection. The molecular search implementation and ligand inputs were unchanged. The distributed client is shown in the service configuration section.

### Session lifecycle and executor scaling

Batch completion does not close a Flame session. An open service handle accepts further screen.dock calls, allowing subsequent ligand batches to use the same application and session. This run used --keep to retain both for inspection. Reattachment from another client requires the existing session reference; calling Screen.remote creates a new service session.

Executor allocation is adjusted according to session demand, configured limits and available cluster resources. A single service handle submits work that can run across multiple executor instances, without client management of an actor pool. The session remains available for subsequent submissions, while in-memory engine state is retained for the lifetime of each executor instance.

Ray separates persistence from replica scaling. A [detached named actor](https://docs.ray.io/en/latest/ray-core/actors/named-actors.html) can outlive its creating driver, but does not automatically replicate when its method queue grows. The [Ray cluster autoscaler](https://docs.ray.io/en/latest/cluster/kubernetes/user-guides/configuring-autoscaling.html) can provision nodes for requested actors; that is distinct from creating additional actor instances. [Ray Data autoscaling actor pools](https://docs.ray.io/en/latest/data/api/doc/ray.data.ActorPoolStrategy.html) are a closer comparison for scaling execution capacity. For this workflow, Flame brings continued submissions and elastic executor allocation together under one session.

### Setup reuse and overhead

Receptor loading and map construction occurred once per executor instance. Nine initializations supported 101 tasks, including 92 warm invocations. This amortized setup across ligand calls. The recorded timings cover Vina setup and docking; scheduling, serialization and transport overhead were not measured independently.

## Screening inputs and preparation

The receptor and reference ligand were taken from the AutoDock Vina 1IEP tutorial system for c-Abl and imatinib. The library comprised 20 reported actives and 80 decoys from [DUD-E ABL1](https://dude.docking.org/targets/abl1/). Imatinib was excluded from the library and included separately as the reference.

Preparation downloaded hash-pinned SDF archives, selected records in a deterministic order, and converted them to PDBQT with pinned RDKit and Meeko versions. Parent-connectivity identities prevented protonation, tautomer and stereochemical variants from inflating the count. Normalization was applied to copies for identity checks; the docking molecules retained their supplied 3D coordinates and explicit-hydrogen states.

[Meeko requires molecules with 3D coordinates and explicit hydrogens](https://apidocmeeko.readthedocs.io/en/latest/lig_overview.html). The preparation script rejects missing inputs instead of inventing conformers or protonation states. A manifest records the source URLs and hashes, selected identities, tool versions, skipped records and prepared-file hashes. Two preparations produced byte-identical manifests.

## Service configuration

![Flame client, session manager, executor managers and executors]({{ '/assets/images/vina-screening/architecture.jpg' | relative_url }})

*Conceptual Flame architecture. This run placed the control plane in Kubernetes and ran host Python services on two Linux workers; the diagram illustrates the client, session-manager and executor-manager roles.*

A Vina engine loads the receptor and computes its maps in the service constructor. Its dock method changes the ligand, runs the search and returns the best pose and score. Computing maps before loading a ligand covers all Vina atom types, which is useful for a varied library. [Vina’s Python scripting documentation](https://autodock-vina.readthedocs.io/en/latest/docking_python.html) describes this behavior.

The Python client creates a remote class service and submits one call per compound. Vina receives cpu=1 to match the executor’s CPU request, rather than using its default of all available host CPUs.

```python
from pathlib import Path
from flamepy import app
from engine import VinaScreen, load_job

job = load_job(ligand_dir=Path("data/screening/ligands"))
app.init("vina-screen-001", python_version="3.12")
Screen = app.service(resreq="cpu=1,mem=2g", warmup=1)(VinaScreen)
screen = Screen.remote(
    job.receptor, job.center, job.box_size,
    exhaustiveness=8, n_poses=1, seed=1, cpu=1,
)
futures = [screen.dock(name, pdbqt) for name, pdbqt in job.ligands]
for future in app.select(futures):
    result = future.get()
    # Persist the score, best pose, timing and any ligand error.
```

The service instance lives on its executor. For this screen, changing the ligand did not reconstruct the engine or recompute the receptor maps. Ordinary ligand errors return structured error rows so the remaining compounds can finish; initialization and infrastructure failures are handled separately.

## Reproduction procedure

The [complete example](https://github.com/xflops/flame/tree/main/examples/vina) includes the docking engine, preparation script and result collector. Run the following commands from `examples/vina` in a Flame checkout. Use an isolated Python 3.12 environment for preparation. The listed dependencies are required for ligand preparation; submission of prepared PDBQT files does not require them. Use a fresh preparation output directory.

```shell
uv run --no-project --python 3.12 \
  --with rdkit==2025.9.3 --with meeko==0.6.1 \
  --with numpy==2.2.6 --with scipy==1.15.3 --with gemmi==0.7.3 \
  python prepare.py --output data/screening
```

Submission requires a configured Flame cluster and the Flame SDK in the Python 3.12 client environment. Executors need Python 3.12 on Linux x86_64 and access to install `vina==1.2.7` from the example package. See the [installation guide]({{ "/docs/installation/" | relative_url }}) and the [example requirements](https://github.com/xflops/flame/tree/main/examples/vina#requirements) for setup. Use a fresh results directory for each run:

```shell
python3.12 main.py \
  --ligands data/screening/ligands \
  --output results/abl1-screen-001 \
  --app-name vina-screen-001 \
  --keep
```

The client verifies the manifest before application registration. Each ligand is submitted as an independent task, with a resource request of one CPU and 2 GiB per executor. The defaults used for this run are search exhaustiveness 8 and seed 1; `VINA_EXHAUSTIVENESS` and `VINA_SEED` override them. Exhaustiveness 8 is a workload setting, not a validated pose-recovery protocol for the 1IEP reference. A new application name deploys the package; an existing name reuses its registration. Dependency changes therefore require a new application name for this procedure.

## Execution monitoring

![Flame application list with the screening application enabled]({{ '/assets/images/vina-screening/applications.png' | relative_url }})

*Application view during the screen. The screening application is enabled and uses the Host runtime.*

![Screening session with 53 succeeded, 9 running and 39 pending tasks]({{ '/assets/images/vina-screening/session-progress.png' | relative_url }})

*Session progress captured during execution: 53 succeeded, 9 running and 39 pending. This is an intermediate snapshot; the final result was 101 of 101 succeeded.*

![Nine screening executors distributed across two Linux workers]({{ '/assets/images/vina-screening/executors.png' | relative_url }})

*Executor view during the screen. Nine entries belong to the screening session across the two workers; the tenth belongs to the earlier session.*

The client connected over Tailscale. Some new status connections timed out during execution. The existing session was retained and no tasks were resubmitted. The original client collected all results, and --keep left the application and session open after completion.

## Results and timing

The completed run used Python 3.12, Vina 1.2.7 and NumPy 2.5.5 on the docking services. Each observed service instance recorded its hostname, process ID, instance ID, runtime versions and invocation count.

| Measurement | Observed value |
| --- | --- |
| Library compounds and reference | 100 + 1 |
| Successful tasks and saved poses | 101 |
| Ligand errors or unknown outcomes | 0 |
| Worker nodes | 2 |
| Engine instances observed | 9 |
| Invocations reusing an initialized engine | 92 |
| First result after submission began | 56.02 s |
| Screening and result collection | 25 min 23.48 s |
| Total client run including initialization | 25 min 38.87 s |
| Engine setup summed once per instance | 24.41 s |
| Map construction within that setup total | 21.16 s |

Setup time includes map construction and must not be added to it again. The sum of per-ligand docking durations was 3 h 34 min 6.81 s, with work overlapping across executors. That aggregate is not a measured serial baseline, so this run does not establish a speedup factor.

The top five scores were:

| Rank | Compound | Source group | Vina score in kcal/mol |
| --- | --- | --- | --- |
| 1 | CHEMBL20252 | DUD-E active | -13.702 |
| 2 | CHEMBL205723 | DUD-E active | -13.324 |
| 3 | Imatinib reference | Reference | -13.257 |
| 4 | CHEMBL230178 | DUD-E active | -12.711 |
| 5 | CHEMBL378024 | DUD-E active | -12.652 |

These are docking scores under this receptor and search configuration, not measured binding affinities. The subset deliberately includes 20 reported actives, DUD-E decoys are not experimentally confirmed negatives, and the 1IEP receptor differs from the original DUD-E benchmark setup. The results demonstrate a screening workflow; they are not a prospective hit-rate or enrichment estimate.

## Output artifacts and provenance

The output directory contains results.csv ranked by score, poses/<ligand>.pdbqt for each best pose, failures.csv for ligand errors or uncertain client outcomes, and run.json for the configuration, manifest, timings and observed engine instances.

Outputs are updated as compounds finish. The run record separates worker engine setup, map construction and ligand docking from client wall time. Instance IDs prevent setup time from being counted once per ligand and make the 92 warm invocations visible.

The retained application and session provide an execution record for inspection. The ranked scores, docked poses and manifest support subsequent molecular review and validation. The same submission model supports additional prepared ligand batches.
