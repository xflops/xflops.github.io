---
layout: docs
title: Documentation Overview
description: Welcome to the XFLOPS documentation. Learn about Flame, our distributed engine for AI Agents.
---

# Welcome to XFLOPS Documentation

Welcome to the comprehensive documentation for XFLOPS and the Flame project. This documentation will guide you through everything you need to know about building and deploying distributed AI workloads with our cloud-native platform.

## What is XFLOPS?

XFLOPS is an organization dedicated to helping customers build cloud-native platforms for high-performance workloads including AI, BigData, and HPC. Our platform is built upon decades of experience in both batch and elastic workload management.

## Introducing Flame

**Flame** is our flagship distributed engine for AI Agents, designed to handle the most demanding AI workloads with unprecedented efficiency and scalability.

### Key Features of Flame

- **Distributed AI Training**: Scale your AI model training across multiple nodes and clusters
- **Agent Orchestration**: Manage complex AI agent workflows and interactions
- **Resource Optimization**: Intelligent resource allocation for maximum efficiency
- **Fault Tolerance**: Built-in resilience and recovery mechanisms
- **Multi-Cloud Support**: Deploy across different cloud providers seamlessly
- **Heterogeneous Device Support**: Utilize GPUs, TPUs, and specialized accelerators

## Documentation Structure

Our documentation is organized into several key sections:

### 🚀 [Getting Started](/docs/getting-started/)
Begin your journey with Flame. Learn about installation, basic configuration, and your first deployment.

### 💡 [Use Cases](/docs/use-cases/)
Explore real-world applications and use cases where Flame excels, from large language model training to multi-agent systems.

### 📖 [User Guide](/docs/user-guide/)
Comprehensive guides for using Flame effectively, including configuration, deployment strategies, and best practices.

### 🔌 [API Reference](/docs/api-reference/)
Complete API documentation for integrating Flame into your applications and building custom extensions.

### 🌐 [Ecosystem](/docs/ecosystem/)
Discover the broader XFLOPS ecosystem, including integrations, plugins, and community contributions.

## Quick Start

If you're ready to dive in immediately, here's a quick overview of what you'll need:

1. **Prerequisites**: Kubernetes cluster, Docker, and basic familiarity with container orchestration
2. **Installation**: Deploy Flame using our Helm charts or direct Kubernetes manifests
3. **Configuration**: Set up your first AI workload configuration
4. **Deployment**: Launch your first distributed AI training job

## Architecture Overview

Flame follows a microservices architecture designed for cloud-native environments:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Flame Agent  │    │   Flame Agent  │    │   Flame Agent  │
│   (Node 1)     │    │   (Node 2)     │    │   (Node N)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │   Flame Core    │
                    │  Orchestrator   │
                    └─────────────────┘
                                 │
                    ┌─────────────────┐
                    │   Kubernetes    │
                    │   Infrastructure│
                    └─────────────────┘
```

## Getting Help

- **Documentation Issues**: If you find errors or have suggestions, please [open an issue](https://github.com/xflops/flame/issues) on GitHub
- **Community Support**: Join our [Slack community](http://xflops.slack.com) for real-time help
- **Email Support**: Contact us at [support@xflops.cn](mailto:support@xflops.cn)

## Contributing

We welcome contributions from the community! Whether it's improving documentation, reporting bugs, or contributing code, every contribution helps make Flame better for everyone.

- **Documentation**: Submit pull requests to improve our docs
- **Code**: Contribute to the [Flame project](https://github.com/xflops/flame)
- **Feedback**: Share your experiences and suggestions

## What's Next?

Ready to get started? We recommend beginning with the [Getting Started](/docs/getting-started/) guide, which will walk you through your first Flame deployment.

If you have specific use cases in mind, check out our [Use Cases](/docs/use-cases/) section to see examples of how others are using Flame in production.

---

*Last updated: {{ site.time | date: "%B %d, %Y" }}*
