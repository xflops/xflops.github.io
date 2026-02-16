---
layout: doc
title: Installation Guide
description: Step-by-step guide for installing and configuring the X-FLOPS FLM service.
---

# Installation Guide

This guide details the installation process for the X-FLOPS FLM (Federated Learning Manager) service. We prioritize a secure and robust deployment using the `flmadm` utility.

## Prerequisites

Before beginning the installation, ensure your environment meets the following requirements:

### Operating System
- **Ubuntu 20.04 LTS** or newer
- **CentOS/RHEL 8** or newer

### Software
- **Python 3.8+**: Required for the core service.
- **pip**: Python package installer.
- **Root/Sudo Access**: Required for service configuration and port binding.

### Network
- **Port 8080 (TCP)**: Default API port (configurable).
- **Port 5432 (TCP)**: If using external PostgreSQL (recommended for production).

## Installation

We recommend installing the FLM service within a virtual environment to isolate dependencies.

### 1. Create a Virtual Environment

```bash
python3 -m venv /opt/xflops/venv
source /opt/xflops/venv/bin/activate
```

### 2. Install the Package

Install the core package using pip. This includes the `flmadm` administrative tool.

```bash
pip install xflops-flm
```

### 3. Initialize Configuration

Run the initialization command to generate default configuration files and directory structures.

```bash
sudo flmadm init --user xflops --group xflops
```

> **Note:** This command creates the `xflops` system user if it does not exist, ensuring the service runs with least privilege.

## Configuration

The main configuration file is located at `/etc/xflops/flm.conf`.

### Security Recommendations

Ensure the configuration file is readable only by the service user and root.

```bash
sudo chown root:xflops /etc/xflops/flm.conf
sudo chmod 640 /etc/xflops/flm.conf
```

### Database Setup

For production environments, update the `database_uri` in `flmadm.conf`.

```ini
[database]
# Format: postgresql://user:password@host:port/dbname
uri = postgresql://flm_user:secure_password@localhost:5432/flm_db
pool_size = 20
max_overflow = 10
```

> **Warning:** Never commit configuration files containing real passwords to version control. Use environment variables where possible.

## Service Management

The installation process automatically registers a systemd service unit.

### Starting the Service

```bash
sudo systemctl start xflops-flm
```

### Enabling on Boot

```bash
sudo systemctl enable xflops-flm
```

### Checking Status

```bash
sudo systemctl status xflops-flm
```

## Troubleshooting

If the service fails to start, check the following locations for error details.

### Logs

Logs are written to `/var/log/xflops/flm.log` by default.

```bash
tail -f /var/log/xflops/flm.log
```

### Common Issues

1.  **Port Conflict (Address already in use)**
    - **Error**: `OSError: [Errno 98] Address already in use`
    - **Fix**: Check if another service is using port 8080: `sudo lsof -i :8080`. Modify `flm.conf` to use a different port if necessary.

2.  **Permission Denied**
    - **Error**: `PermissionError: [Errno 13] Permission denied: '/var/lib/xflops/data'`
    - **Fix**: Ensure the `xflops` user owns the data directory: `sudo chown -R xflops:xflops /var/lib/xflops`.

3.  **Database Connection Failed**
    - **Error**: `OperationalError: connection to server at "localhost" failed`
    - **Fix**: Verify PostgreSQL is running and the credentials in `flm.conf` are correct. Check firewall rules for port 5432.
