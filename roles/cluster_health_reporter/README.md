# cluster_health_reporter Role

Automated Kubernetes cluster health reporting with daily and weekly summaries.

## Overview

This role sets up automated health reporting for the Kubernetes cluster by:
- Querying Prometheus for cluster metrics
- Generating daily and weekly health summaries
- Sending notifications to Discord
- Storing historical reports

## Features

### Daily Reports (Default: 8:00 AM)
- Node status (UP/DOWN)
- Current resource usage (CPU, Memory, Disk) per node
- Pod status summary (Running, Pending, Failed)
- Active alerts

### Weekly Reports (Default: Monday 9:00 AM)
- All daily report metrics
- Week-over-week trends
- Incident summary
- Resource forecasting data

### Automated Management
- Cron-based scheduling
- Historical report retention (90 days default)
- Log rotation
- Discord webhook integration

## Requirements

- Python 3 with requests library
- Access to Prometheus server
- Master node for script execution
- (Optional) Discord webhook URL for notifications

## Variables

### Defaults (see `defaults/main.yml`)

```yaml
# Prometheus configuration
prometheus_url: "http://192.168.1.143:9090"

# Discord webhook (set via vault or override)
discord_webhook_url: ""

# Report storage
report_storage_path: "/var/lib/cluster-health-reports"

# Schedules
daily_report_hour: "8"       # 8 AM
daily_report_minute: "0"
weekly_report_day: "1"       # Monday
weekly_report_hour: "9"      # 9 AM
weekly_report_minute: "0"

# Health thresholds
cpu_warning_threshold: 80
memory_warning_threshold: 85
disk_warning_threshold: 90

# Report retention
report_retention_days: 90
```

### Setting Discord Webhook

Option 1 - Via group_vars:
```yaml
# group_vars/all/vault.yml
discord_webhook_url: "https://discord.com/api/webhooks/..."
```

Option 2 - Via command line:
```bash
ansible-playbook playbooks/setup-health-reporting.yml \
  -e "discord_webhook_url=https://discord.com/api/webhooks/..."
```

## Usage

### Deploy Health Reporting

```bash
ansible-playbook playbooks/setup-health-reporting.yml -i inventories/production/hosts.ini
```

### Run Manual Report

```bash
# Daily report
ssh master-node
/usr/local/bin/generate_health_report.py \
  --type daily \
  --prometheus-url http://192.168.1.143:9090 \
  --output /tmp/report.txt

# Weekly report
/usr/local/bin/generate_health_report.py \
  --type weekly \
  --prometheus-url http://192.168.1.143:9090 \
  --output /tmp/weekly-report.txt \
  --discord-webhook "https://discord.com/api/webhooks/..."
```

### View Reports

```bash
# View latest reports
ls -lth /var/lib/cluster-health-reports/ | head -10

# Read a report
cat /var/lib/cluster-health-reports/daily-2026-02-14.txt
```

### Check Logs

```bash
tail -f /var/log/cluster-health-reports.log
```

## Report Format

### Daily Report Example

```
============================================================
Kubernetes Cluster Health Report - Daily
Generated: 2026-02-14 08:00:00
============================================================

## Node Status
  ✅ kube501:9100: UP
  ✅ kube502:9100: UP
  ✅ kube503:9100: UP
  ✅ kube511:9100: UP

## Resource Usage
### CPU
  🟢 kube501:9100: 45.2%
  🟢 kube502:9100: 52.1%
  🟡 kube503:9100: 78.5%
  🟢 kube511:9100: 38.9%

### MEMORY
  🟢 kube501:9100: 62.3%
  🟢 kube502:9100: 58.7%
  🟢 kube503:9100: 71.2%
  🟡 kube511:9100: 82.1%

## Pod Status
  Total: 47
  Running: 45
  Pending: 1
  Failed: 1

## Active Alerts
  🟡 PodCrashLooping: nginx pod restarting
  🔴 NodeDiskPressure: kube503 disk >90%

============================================================
```

## Customization

### Change Report Schedule

Edit role variables or override:
```yaml
# Run daily report at 6 AM
daily_report_hour: "6"

# Run weekly report on Friday at 5 PM
weekly_report_day: "5"
weekly_report_hour: "17"
```

### Customize Thresholds

```yaml
cpu_warning_threshold: 70
memory_warning_threshold: 80
disk_warning_threshold: 85
```

### Add Custom Metrics

Edit `generate_health_report.py` and add new Prometheus queries.

## Integration with Heartbeat

The health reports can be integrated with Boss's heartbeat checks:

```python
# In HEARTBEAT.md
- Check /var/lib/cluster-health-reports/daily-latest.txt
- Alert on critical status indicators
- Trend analysis for capacity planning
```

## Troubleshooting

### Reports not generating

Check cron logs:
```bash
grep "cluster health report" /var/log/syslog
```

Check script logs:
```bash
tail -f /var/log/cluster-health-reports.log
```

### Discord notifications not working

Test webhook manually:
```bash
curl -X POST "https://discord.com/api/webhooks/..." \
  -H "Content-Type: application/json" \
  -d '{"content": "Test message"}'
```

### Prometheus connection issues

Test connectivity:
```bash
curl http://192.168.1.143:9090/api/v1/query?query=up
```

## Related Issues

- Implements Issue #4: Set up automated cluster health reporting

## Future Enhancements

- Slack integration
- Email reports
- Grafana snapshot embedding
- Alert trend analysis
- Capacity forecasting
- Anomaly detection
