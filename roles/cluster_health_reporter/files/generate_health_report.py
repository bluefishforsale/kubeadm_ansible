#!/usr/bin/env python3
"""
Kubernetes Cluster Health Reporter
Queries Prometheus and generates health summaries
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Any
import requests

class ClusterHealthReporter:
    def __init__(self, prometheus_url: str, report_type: str = "daily"):
        self.prometheus_url = prometheus_url.rstrip('/')
        self.report_type = report_type
        self.timestamp = datetime.now()
        
    def query_prometheus(self, query: str) -> Dict:
        """Query Prometheus and return results"""
        try:
            response = requests.get(
                f"{self.prometheus_url}/api/v1/query",
                params={'query': query},
                timeout=30
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"Error querying Prometheus: {e}", file=sys.stderr)
            return {"status": "error", "data": {"result": []}}
    
    def query_prometheus_range(self, query: str, start: datetime, end: datetime) -> Dict:
        """Query Prometheus range and return results"""
        try:
            response = requests.get(
                f"{self.prometheus_url}/api/v1/query_range",
                params={
                    'query': query,
                    'start': start.timestamp(),
                    'end': end.timestamp(),
                    'step': '1h' if self.report_type == 'daily' else '1d'
                },
                timeout=30
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"Error querying Prometheus range: {e}", file=sys.stderr)
            return {"status": "error", "data": {"result": []}}
    
    def get_node_status(self) -> List[Dict]:
        """Get status of all cluster nodes"""
        result = self.query_prometheus('up{job="node-exporter"}')
        nodes = []
        
        for item in result.get('data', {}).get('result', []):
            node = item['metric'].get('instance', 'unknown')
            status = "UP" if item['value'][1] == '1' else "DOWN"
            nodes.append({"node": node, "status": status})
        
        return nodes
    
    def get_resource_usage(self) -> Dict:
        """Get current resource usage across cluster"""
        queries = {
            'cpu': '100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)',
            'memory': '(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100',
            'disk': '(1 - (node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes{fstype!="tmpfs"})) * 100'
        }
        
        usage = {}
        for metric, query in queries.items():
            result = self.query_prometheus(query)
            usage[metric] = []
            for item in result.get('data', {}).get('result', []):
                usage[metric].append({
                    'node': item['metric'].get('instance', 'unknown'),
                    'value': float(item['value'][1])
                })
        
        return usage
    
    def get_pod_status(self) -> Dict:
        """Get pod status summary"""
        queries = {
            'running': 'count(kube_pod_status_phase{phase="Running"})',
            'pending': 'count(kube_pod_status_phase{phase="Pending"})',
            'failed': 'count(kube_pod_status_phase{phase="Failed"})',
            'total': 'count(kube_pod_info)'
        }
        
        status = {}
        for phase, query in queries.items():
            result = self.query_prometheus(query)
            value = result.get('data', {}).get('result', [])
            status[phase] = int(value[0]['value'][1]) if value else 0
        
        return status
    
    def get_alerts(self) -> List[Dict]:
        """Get current active alerts"""
        try:
            response = requests.get(
                f"{self.prometheus_url}/api/v1/alerts",
                timeout=30
            )
            response.raise_for_status()
            data = response.json()
            
            alerts = []
            for alert in data.get('data', {}).get('alerts', []):
                if alert.get('state') == 'firing':
                    alerts.append({
                        'name': alert.get('labels', {}).get('alertname', 'Unknown'),
                        'severity': alert.get('labels', {}).get('severity', 'info'),
                        'summary': alert.get('annotations', {}).get('summary', ''),
                        'since': alert.get('activeAt', '')
                    })
            
            return alerts
        except Exception as e:
            print(f"Error getting alerts: {e}", file=sys.stderr)
            return []
    
    def generate_daily_report(self) -> str:
        """Generate daily health summary"""
        nodes = self.get_node_status()
        usage = self.get_resource_usage()
        pods = self.get_pod_status()
        alerts = self.get_alerts()
        
        # Build report
        report = []
        report.append("=" * 60)
        report.append(f"Kubernetes Cluster Health Report - Daily")
        report.append(f"Generated: {self.timestamp.strftime('%Y-%m-%d %H:%M:%S')}")
        report.append("=" * 60)
        report.append("")
        
        # Node Status
        report.append("## Node Status")
        for node in nodes:
            status_emoji = "✅" if node['status'] == "UP" else "❌"
            report.append(f"  {status_emoji} {node['node']}: {node['status']}")
        report.append("")
        
        # Resource Usage
        report.append("## Resource Usage")
        for metric, data in usage.items():
            report.append(f"### {metric.upper()}")
            for item in data:
                value = item['value']
                emoji = "🟢" if value < 70 else "🟡" if value < 85 else "🔴"
                report.append(f"  {emoji} {item['node']}: {value:.1f}%")
            report.append("")
        
        # Pod Status
        report.append("## Pod Status")
        total = pods.get('total', 0)
        running = pods.get('running', 0)
        pending = pods.get('pending', 0)
        failed = pods.get('failed', 0)
        report.append(f"  Total: {total}")
        report.append(f"  Running: {running}")
        report.append(f"  Pending: {pending}")
        report.append(f"  Failed: {failed}")
        report.append("")
        
        # Active Alerts
        report.append("## Active Alerts")
        if alerts:
            for alert in alerts:
                severity_emoji = {
                    'critical': '🔴',
                    'warning': '🟡',
                    'info': '🔵'
                }.get(alert['severity'], '⚪')
                report.append(f"  {severity_emoji} {alert['name']}: {alert['summary']}")
        else:
            report.append("  ✅ No active alerts")
        report.append("")
        
        report.append("=" * 60)
        
        return "\n".join(report)
    
    def generate_weekly_report(self) -> str:
        """Generate weekly health analysis"""
        # For weekly, include trend analysis
        end_time = datetime.now()
        start_time = end_time - timedelta(days=7)
        
        report = []
        report.append("=" * 60)
        report.append(f"Kubernetes Cluster Health Report - Weekly")
        report.append(f"Period: {start_time.strftime('%Y-%m-%d')} to {end_time.strftime('%Y-%m-%d')}")
        report.append("=" * 60)
        report.append("")
        
        # Include daily summary
        report.append(self.generate_daily_report())
        report.append("")
        
        # Add weekly trends (simplified for now)
        report.append("## Weekly Summary")
        report.append("  - Average uptime: Check Prometheus for detailed metrics")
        report.append("  - Resource trends: See Grafana dashboards")
        report.append("  - Incident summary: Review alert history")
        report.append("")
        
        report.append("=" * 60)
        
        return "\n".join(report)
    
    def save_report(self, report: str, output_path: str):
        """Save report to file"""
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, 'w') as f:
            f.write(report)
        print(f"Report saved to: {output_path}")
    
    def send_to_discord(self, report: str, webhook_url: str):
        """Send report to Discord webhook"""
        if not webhook_url:
            print("Discord webhook not configured, skipping notification")
            return
        
        # Discord has 2000 char limit, truncate if needed
        content = report if len(report) < 1990 else report[:1990] + "\n... (truncated)"
        
        payload = {
            "content": f"```\n{content}\n```"
        }
        
        try:
            response = requests.post(webhook_url, json=payload, timeout=10)
            response.raise_for_status()
            print("Report sent to Discord successfully")
        except Exception as e:
            print(f"Error sending to Discord: {e}", file=sys.stderr)

def main():
    parser = argparse.ArgumentParser(description='Generate Kubernetes cluster health report')
    parser.add_argument('--type', choices=['daily', 'weekly'], default='daily',
                       help='Report type (daily or weekly)')
    parser.add_argument('--prometheus-url', required=True,
                       help='Prometheus server URL')
    parser.add_argument('--output', required=True,
                       help='Output file path')
    parser.add_argument('--discord-webhook', default='',
                       help='Discord webhook URL for notifications')
    
    args = parser.parse_args()
    
    reporter = ClusterHealthReporter(args.prometheus_url, args.type)
    
    if args.type == 'daily':
        report = reporter.generate_daily_report()
    else:
        report = reporter.generate_weekly_report()
    
    reporter.save_report(report, args.output)
    reporter.send_to_discord(report, args.discord_webhook)

if __name__ == '__main__':
    main()
