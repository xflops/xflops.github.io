---
layout: docs
title: Python API Migration
description: Migrate historical Python examples to the current Flame APIs.
---

# Python API Migration

The former `flamepy.runner` and `flamepy.service` modules are not part of the current SDK. Historical articles may show those APIs for the Flame version they describe.

For Python functions and classes, use [`flamepy.app`](/docs/flamepy/app/). It packages the project and exposes remote calls through service declarations. For a separately deployed Python service with a Python-object request and response, use [`flamepy.serving`](/docs/flamepy/service/). For an explicit byte-level protocol, use [`flamepy.core`](/docs/flamepy/core/) and its `FlameService` interface; the application is responsible for serialization.

Consult the upstream [Python SDK guide](https://github.com/xflops/flame/blob/main/docs/sdk/python.md) and [service examples](https://github.com/xflops/flame/tree/main/examples) for current interfaces and deployment requirements.
