---
layout: docs
title: Python Service Migration
description: Migrate older flamepy.service examples to current Flame APIs.
---

# Python Service Migration

The former `flamepy.service` module, including `FlameInstance` and its typed `Session`, is not part of the current SDK. Historical articles may show that API for the Flame version they describe.

For Python functions and classes, use [`flamepy.app`](/docs/flamepy/runner/). It handles project packaging and exposes remote calls through service declarations. For a separately deployed service with its own protocol, use [`flamepy.core`](/docs/flamepy/core/) and the current `FlameService` interface. Core sessions submit byte payloads, so the application is responsible for its request and response serialization.

Consult the upstream [Python SDK guide](https://github.com/xflops/flame/blob/main/docs/sdk/python.md) and [service examples](https://github.com/xflops/flame/tree/main/examples) for the current interface and deployment requirements.
