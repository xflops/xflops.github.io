# XFLOPS Website

This repository contains the public website for XFLOPS and the documentation mirror for [Flame](https://github.com/xflops/flame).

## About Flame

Flame is a distributed engine for AI workloads. It provides mechanisms that show up repeatedly in agents, reinforcement learning, generated-code execution, and other elastic AI systems: sessions, task scheduling, executor reuse, object caching, secure runtime isolation, and multi-language service integration.

The website should stay aligned with the Flame repository. When product positioning, install commands, Runner behavior, or example paths change in `xflops/flame`, update the corresponding pages here.

## Website Structure

This site is built with Jekyll and includes:

- **Homepage**: Flame positioning, capabilities, and recent posts.
- **Documentation**:
  - Overview
  - Getting Started
  - Installation Guide
  - User Guide
  - flamepy Guide
  - flamepy.runner Guide
  - flamepy.service Guide
  - flamepy.core Guide
  - flame-rs Guide
  - flame_rs::client Guide
  - flame_rs::service Guide
- **Blog**: Technical walkthroughs and release-adjacent examples.

## Local Development

### Prerequisites

- Ruby 2.7 or later
- Bundler

### Setup

```bash
git clone https://github.com/xflops/xflops.github.io.git
cd xflops.github.io
bundle install
bundle exec jekyll serve
```

Open `http://localhost:4000`.

### Build

```bash
bundle exec jekyll build
```

The generated site is written to `_site/`.

## Project Structure

```text
.
├── _config.yml
├── _layouts/
├── _docs/
├── _blog/
├── assets/
├── images/
├── blog/
├── index.html
├── sitemap.xml
└── README.md
```

## Content Guidelines

- Keep public claims consistent with the current [Flame README](https://github.com/xflops/flame/blob/main/README.md).
- Prefer links to current upstream files under `https://github.com/xflops/flame/tree/main/...` or `blob/main/...`.
- Use `flamepy.runner.Runner` for Python scaling examples unless the page is intentionally documenting `flamepy.service` or `flamepy.core`.
- Use `flame-rs` for Rust client and service examples.
- Use `flmadm` profile flags explicitly: `--all`, `--control-plane`, `--worker`, `--cache`, or `--client`.
- Refer to current cluster configuration as `flame-cluster.yaml`.

## Deployment

The website is deployed by GitHub Pages from the main branch.

## Contact

- Email: [support@xflops.io](mailto:support@xflops.io)
- GitHub: [https://github.com/xflops](https://github.com/xflops)
- Slack: [https://xflops.slack.com](https://xflops.slack.com)

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
