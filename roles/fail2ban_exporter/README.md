# fail2ban_exporter Role

Installs and configures fail2ban-exporter for Prometheus metrics collection of fail2ban statistics.

## Overview

fail2ban-exporter exposes fail2ban statistics as Prometheus metrics, enabling monitoring of:
- Banned IP addresses
- Total bans per jail
- Ban/unban events
- Jail status

## What This Role Does

1. Ensures fail2ban is installed and running
2. Creates prometheus system user
3. Downloads and installs fail2ban_exporter binary
4. Adds prometheus user to fail2ban group for socket access
5. Creates and enables systemd service
6. Verifies metrics endpoint accessibility

## Requirements

- Debian/Ubuntu system
- Internet access for downloading fail2ban_exporter
- sudo/root access

## Variables

### Defaults (see `defaults/main.yml`)

```yaml
fail2ban_exporter_version: "0.11.0"
fail2ban_exporter_bin_path: "/usr/local/bin/fail2ban_exporter"
fail2ban_exporter_user: "prometheus"
fail2ban_exporter_group: "prometheus"
fail2ban_exporter_port: 9191
fail2ban_exporter_web_path: "/metrics"
fail2ban_socket_path: "/var/run/fail2ban/fail2ban.sock"
```

## Usage

### Deploy fail2ban-exporter

```bash
ansible-playbook playbooks/fix-fail2ban-exporter.yml -i inventories/production/hosts.ini
```

### Diagnose issues

```bash
ansible-playbook playbooks/diagnose-fail2ban.yml -i inventories/production/hosts.ini
```

### Verify deployment

```bash
# Check service status
ansible k8s -i inventories/production/hosts.ini -m systemd -a "name=fail2ban_exporter" -b

# Check metrics
curl http://<node-ip>:9191/metrics
```

## Metrics Exposed

Sample metrics:
```
# HELP fail2ban_up Could fail2ban be reached
fail2ban_up 1

# HELP fail2ban_banned_total Number of banned IPs stored in database
fail2ban_banned_total{jail="sshd"} 42

# HELP fail2ban_failed_current Number of current failures
fail2ban_failed_current{jail="sshd"} 0
```

## Prometheus Configuration

Add to prometheus scrape config:

```yaml
scrape_configs:
  - job_name: 'fail2ban'
    static_configs:
      - targets:
        - 'kube501:9191'
        - 'kube502:9191'
        - 'kube503:9191'
        - 'kube511:9191'
```

## Troubleshooting

### Service fails to start

Check logs:
```bash
journalctl -u fail2ban_exporter -n 50
```

Common issues:
- fail2ban service not running
- Permissions on fail2ban socket
- Port 9191 already in use

### Permission denied on socket

Ensure prometheus user is in fail2ban group:
```bash
groups prometheus
# Should show: prometheus fail2ban
```

### No metrics returned

Verify fail2ban is running:
```bash
systemctl status fail2ban
fail2ban-client status
```

## Related Issues

- Fixes Issue #3: Investigate fail2ban-exporter status on k8s nodes

## References

- [fail2ban_exporter GitHub](https://github.com/jangrewe/fail2ban_exporter)
- [fail2ban Documentation](https://www.fail2ban.org/)
