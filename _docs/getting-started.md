---
layout: docs
title: Getting Started with Flame
description: Learn how to install and configure Flame for your first distributed AI workload deployment.
---

# Getting Started with Flame

This guide will walk you through installing and configuring Flame for your first distributed AI workload deployment on bare metal or virtual machines. By the end of this guide, you'll have a working Flame installation and understand the basic concepts.

## Prerequisites

Before you begin, ensure you have the following:

- **Operating System**: Linux (Ubuntu 20.04+, CentOS 8+, etc.)
- **Dependencies**: Rust toolchain, Git, and Python 3.
- **Root Access**: For system-wide installation.

## Installation

Flame is installed using the `flmadm` tool, which manages the installation of all components.

### 1. Install flmadm

First, you need to install the `flmadm` CLI tool.

```bash
# Clone the repository and enter the directory
git clone https://github.com/xflops/flame.git && cd flame

# Build flmadm
cargo build --release -p flmadm

# Install to system path
sudo cp target/release/flmadm /usr/local/bin/
```

### 2. Install Flame Cluster

For a quick start, install all components on a single machine:

```bash
sudo flmadm install --all --enable
```

This will install the Control Plane, Worker, and Client components, and start the necessary systemd services.

For more detailed installation options, including multi-node setups, see the [Installation Guide](/docs/installation.md).

## Verification

After installation, verify that the services are running:

```bash
# Check service status
sudo systemctl status flame-session-manager
sudo systemctl status flame-executor-manager
```

You can also use the `flmping` tool to verify the cluster functionality:

```bash
# Add flame binaries to your PATH for this session
export PATH=$PATH:/usr/local/flame/bin

# Run a simple ping test
flmping
```

You should see output indicating successful task execution:

```
Session <1> was created in <3 ms>, start to run <10> tasks in the session:
...
<10> tasks was completed in <473 ms>.
```

## Your First Workload

Now that your cluster is running, let's submit a simple workload to understand how Flame distributes tasks.

### 1. Create a Simple Python Task

Create a file named `hello_flame.py`:

```python
#!/usr/bin/env python3
"""A simple Flame workload example."""

import flame

def task_function(task_id: int) -> str:
    """A simple task that returns a greeting."""
    import socket
    hostname = socket.gethostname()
    return f"Hello from Flame! Task {task_id} executed on {hostname}"

if __name__ == "__main__":
    # Create a session with 5 tasks
    session = flame.Session()
    
    # Submit tasks
    for i in range(5):
        session.submit(task_function, i)
    
    # Wait for results and print them
    results = session.wait()
    for result in results:
        print(result)
    
    print(f"\nCompleted {len(results)} tasks successfully!")
```

### 2. Run the Workload

```bash
# Ensure PATH is set (assuming /usr/local/flame/bin is in your PATH)
python3 hello_flame.py
```

### 3. Check Session Status

```bash
# List sessions to see your workload
flmctl list -s
```

You should see your session in the output, showing the completed tasks.

## Next Steps

Congratulations! You now have a working Flame installation. Here's what you can explore next:

1. **User Guide**: Dive deeper into [configuration and best practices](/docs/user-guide/)
2. **API Reference**: Learn about the [Flame API](/docs/api-reference/) for programmatic access
3. **Ecosystem**: Explore [integrations and extensions](/docs/ecosystem/)

## Troubleshooting

### Common Issues

**Services not starting:**
```bash
# Check logs
sudo journalctl -u flame-session-manager -f
tail -f /usr/local/flame/logs/fsm.log
```

**Build failures:**
Ensure you have the latest Rust toolchain installed:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Getting Help

If you encounter issues not covered here:

- Check the [Flame GitHub repository](https://github.com/xflops/flame) for known issues
- Join our [Slack community](http://xflops.slack.com) for real-time support
- Open an issue on GitHub with detailed information about your problem
