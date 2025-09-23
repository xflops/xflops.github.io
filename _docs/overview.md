---
layout: docs
title: XFLOPS/Flame Overview
description: Welcome to the XFLOPS! Learn about Flame, an distributed engine for AI Agents and Quant.
---

# Welcome to XFLOPS!

XFLOPS is a vibrant community focused on empowering members to build serverless platforms for elastic workloads, including AI/Agent systems, Big Data, and quantitative computing. Every project within XFLOPS is founded on decades of expertise in both batch and elastic workload management, ensuring robust and scalable solutions.

## What's Flame

**Flame** is a distributed engine for AI Agents and Quant, designed to handle the most demanding elastic workloads with unprecedented efficiency and scalability.

### Key Features of Flame

- **Elastic**: Scale the workloads dynamically based on demand with auto-scaling capabilities and resource optimization.
- **Security**: Session-based authentication and authorization for secure access to your elastic workloads which are running in microVMs, e.g. AI agents, Quant, etc.
- **Cost Effective**: Advanced scheduling algorithms that optimize resource utilization and workload distribution across the infrastructure.
- **Heterogeneous**: Support for various hardware configurations including GPUs, TPUs, and specialized accelerators for elastic workloads.
- **High Performance**: Optimized for maximum throughput and performance, ensuring your elastic workloads run at peak efficiency.
- **Cloud Native**: Designed by Cloud Native architecture, make it possible to be deployed on any cloud platform or on-premise.

## Quick Start

If you're ready to dive in immediately, here's a quick overview of what you'll need:

1. **Prerequisites**: Docker, Docker Compose and basic familiarity with container orchestration
2. **Installation**: Deploy Flame using docker compose for developer environment
3. **Configuration**: Set up your first AI workload configuration
4. **Deployment**: Launch your first distributed AI workload

## Architecture Overview

Flame follows a microservices architecture designed for cloud-native environments:

![]("/images/flame-arch.jpg")

## Getting Help

- **Issues**: If you find errors or have suggestions, please [open an issue](https://github.com/xflops/flame/issues) on GitHub
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
