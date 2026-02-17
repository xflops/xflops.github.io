# Flame User Guide

## Cluster Management with flmadm

`flmadm` is the administration CLI for Flame, designed for installing, configuring, and managing Flame clusters on bare-metal servers or VMs. It handles the full lifecycle of the cluster, including installation, upgrades, and uninstallation.

### Installation & Management

To install `flmadm`:
```bash
cd /path/to/flame
cargo build --release -p flmadm
sudo cp target/release/flmadm /usr/local/bin/
```

Use `flmadm` to manage the cluster:
- **Install**: `sudo flmadm install --all`
- **Uninstall**: `sudo flmadm uninstall`
- **Upgrade**: `sudo flmadm install --force --skip-build`

## Worker Node Configuration

Worker nodes require a `flm.conf` configuration file to connect to the control plane.

Example `flm.conf`:

```ini
[cluster]
leader_address = "http://control-plane-node:8080"
role = "worker"

[executor]
slots = 4
```

Ensure `leader_address` points to the Flame Session Manager on the control plane node.

## Using flmctl

`flmctl` is the user-facing CLI for submitting jobs and managing sessions.

### Common Commands

- **List resources**:
  ```bash
  flmctl list --session
  flmctl list --application
  flmctl list --executor
  ```

- **View resource details**:
  ```bash
  flmctl view --session <session-id>
  flmctl view --application <app-name>
  flmctl view --task <task-id>
  ```

- **Create resources**:
  ```bash
  flmctl create --app <app-name> --slots <slots>
  ```

- **Close session**:
  ```bash
  flmctl close --session <session-id>
  ```

## Troubleshooting

### Common Issues

1. **Service Fails to Start**:
   - Check logs: `journalctl -u flame-session-manager` or `journalctl -u flame-executor-manager`
   - Verify configuration syntax in `/usr/local/flame/conf/flm.conf`

2. **Worker Cannot Join**:
   - Verify network connectivity: `nc -zv <control-plane-ip> 8080`
   - Check firewall rules allow traffic on port 8080 (Session Manager) and 9090 (Executor Manager)
   - Ensure `leader_address` in `flm.conf` is correct and reachable

3. **Job Submission Fails**:
   - Check if Session Manager is running: `systemctl status flame-session-manager`
   - Verify client connectivity to Session Manager port 8080
