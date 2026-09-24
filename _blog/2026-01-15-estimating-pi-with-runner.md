---
layout: blog
title: "Running Monte Carlo Pi with Flame App (Python)"
date: 2026-01-15
author: "Klaus Ma"
categories: ["Flame", "Quant"]
tags: ["flamepy", "app", "pi", "monte-carlo", "distributed-computing"]
---

## Motivation

Monte Carlo estimation splits naturally into independent batches. Flame's
`flamepy.app` API packages the local Python project, registers a temporary
application, runs decorated services on remote executors, and cleans up when
the application is destroyed.

## Pi example

The current [`examples/pi/python/main.py`](https://github.com/xflops/flame/blob/main/examples/pi/python/main.py)
initializes an application before declaring the service:

```python
import math
import numpy as np
import flamepy.app as app

app.init("pi-example")


@app.service()
def estimate_batch(num_samples: int) -> int:
    x = np.random.rand(num_samples)
    y = np.random.rand(num_samples)
    return int(np.sum(x * x + y * y <= 1.0))


num_batches = 10
samples_per_batch = 1_000_000
try:
    futures = [estimate_batch(samples_per_batch) for _ in range(num_batches)]
    insides = app.get(futures)
finally:
    app.destroy()

pi_estimate = 4.0 * sum(insides) / (num_batches * samples_per_batch)
print(f"Estimated PI: {pi_estimate:.10f}; actual PI: {math.pi:.10f}")
```

Calls to `estimate_batch` return futures. `app.get` waits for the batch and
returns the counts. `app.destroy` releases the temporary application even if
one of the calls fails. A future can also be passed into another service call
without first retrieving its value locally.

Run the complete example from `examples/pi/python` in a Flame console with a
running cluster:

```shell
uv run main.py
```

The estimate varies with random sampling. More batches increase total samples
and provide more opportunities for parallel execution when executors are
available.

## References

- [Pi App example](https://github.com/xflops/flame/tree/main/examples/pi/python)
- [App setup tutorial](https://github.com/xflops/flame/blob/main/docs/tutorials/app-setup.md)
