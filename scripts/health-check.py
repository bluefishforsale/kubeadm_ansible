#!/usr/bin/env python3
"""
Kubernetes Health Manager - Automated Health Check
Monitors cluster health using Prometheus metrics and direct checks
"""

import requests
import json
import subprocess
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional

class K8sHealthManager:
    def __init__(self):
        self.prometheus_url = "http://prometheus.home"
        self.loki_url = "http://192.168.1.143:3100"
        self.k8s_api_url = "https://192.168.1.99:6443"
        self.cluster_nodes = ["kube501.home", "kube502.home", "kube503.home", "kube511.home"]
        self.health_report = {
            "timestamp": datetime.now().isoformat(),
            "overall_status": "HEALTHY",
            "issues": [],
            "warnings": [],
            "actions_taken": []
        }
    
    def query_prometheus(self, query: str) -> Optional[Dict]:
        """Query Prometheus and return parsed results"""
        try:
            response = requests.get(f"{self.prometheus_url}/api/v1/query", 
                                  params={"query": query}, 
                                  timeout=10)
            if response.status_code == 200:
                return response.json()
        except requests.RequestException as e:
            self.add_issue(f"Prometheus query failed: {str(e)}")
        return None
    
    def check_node_health(self) -> bool:
        """Check node-level health metrics"""
        print("🖥️  Checking Node Health...")
        
        # Check node_exporter up status
        result = self.query_prometheus("up{job='node_exporter'}")
        if not result:
            return False
            
        node_status = {}
        for metric in result['data']['result']:
            instance = metric['metric']['instance']
            status = int(metric['value'][1])
            node_status[instance] = status == 1
            
        # Check each cluster node
        all_healthy = True
        for node in self.cluster_nodes:
            if node in node_status:
                if node_status[node]:
                    print(f"  ✅ {node} - UP")
                else:
                    print(f"  ❌ {node} - DOWN")
                    self.add_issue(f"Node exporter down on {node}")
                    all_healthy = False
            else:
                print(f"  ⚠️  {node} - NO METRICS")
                self.add_warning(f"No metrics found for {node}")
                all_healthy = False
                
        # Check node resources (CPU, Memory, Disk)
        self.check_node_resources()
        return all_healthy
    
    def check_node_resources(self):
        """Check node resource utilization"""
        print("📊 Checking Node Resources...")
        
        # CPU usage (last 5 minutes average)
        cpu_query = '(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)) * 100'
        result = self.query_prometheus(cpu_query)
        
        if result:
            for metric in result['data']['result']:
                instance = metric['metric']['instance']
                if instance in self.cluster_nodes:
                    cpu_usage = float(metric['value'][1])
                    if cpu_usage > 90:
                        self.add_issue(f"High CPU usage on {instance}: {cpu_usage:.1f}%")
                    elif cpu_usage > 75:
                        self.add_warning(f"Elevated CPU usage on {instance}: {cpu_usage:.1f}%")
                    print(f"  💾 {instance} CPU: {cpu_usage:.1f}%")
        
        # Memory usage
        memory_query = '(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100'
        result = self.query_prometheus(memory_query)
        
        if result:
            for metric in result['data']['result']:
                instance = metric['metric']['instance']
                if instance in self.cluster_nodes:
                    memory_usage = float(metric['value'][1])
                    if memory_usage > 90:
                        self.add_issue(f"High memory usage on {instance}: {memory_usage:.1f}%")
                    elif memory_usage > 80:
                        self.add_warning(f"Elevated memory usage on {instance}: {memory_usage:.1f}%")
                    print(f"  🧠 {instance} Memory: {memory_usage:.1f}%")
    
    def check_kubernetes_api(self) -> bool:
        """Check Kubernetes API server health"""
        print("🎛️  Checking Kubernetes API Health...")
        
        try:
            # Check basic API health
            response = requests.get(f"{self.k8s_api_url}/healthz", 
                                  verify=False, timeout=5)
            if response.status_code == 200 and response.text.strip() == 'ok':
                print("  ✅ API Server - HEALTHY")
                return True
            else:
                self.add_issue(f"API server health check failed: {response.status_code}")
                return False
        except requests.RequestException as e:
            self.add_issue(f"Cannot reach Kubernetes API: {str(e)}")
            return False
    
    def check_container_metrics(self) -> bool:
        """Check if container metrics (cAdvisor) are available"""
        print("🐳 Checking Container Metrics...")
        
        # Check if cAdvisor is providing metrics
        result = self.query_prometheus("up{job='cadvisor'}")
        if not result:
            return False
            
        cadvisor_status = {}
        for metric in result['data']['result']:
            instance = metric['metric']['instance']
            status = int(metric['value'][1])
            cadvisor_status[instance] = status == 1
            
        all_healthy = True
        for node in self.cluster_nodes:
            if node in cadvisor_status:
                if cadvisor_status[node]:
                    print(f"  ✅ {node} cAdvisor - UP")
                else:
                    print(f"  ❌ {node} cAdvisor - DOWN")
                    self.add_issue(f"cAdvisor down on {node}")
                    all_healthy = False
            else:
                print(f"  ⚠️  {node} cAdvisor - NO METRICS")
                self.add_warning(f"cAdvisor not reporting from {node}")
                all_healthy = False
                
        return all_healthy
    
    def check_critical_logs(self):
        """Check Loki for critical log patterns"""
        print("📜 Checking Critical Logs...")
        
        # Define critical log patterns to search for
        critical_patterns = [
            'kubelet.*failed',
            'apiserver.*error',
            'etcd.*error',
            'scheduler.*failed',
            'controller.*error'
        ]
        
        # Check logs from last 15 minutes
        now = datetime.now()
        start_time = now - timedelta(minutes=15)
        
        for pattern in critical_patterns:
            try:
                query = f'{{job="node_exporter"}} |~ "{pattern}"'
                params = {
                    'query': query,
                    'start': int(start_time.timestamp() * 1000000000),
                    'end': int(now.timestamp() * 1000000000),
                    'limit': 10
                }
                
                response = requests.get(f"{self.loki_url}/loki/api/v1/query_range", 
                                      params=params, timeout=10)
                
                if response.status_code == 200:
                    data = response.json()
                    if data['data']['result']:
                        count = sum(len(stream['values']) for stream in data['data']['result'])
                        if count > 0:
                            self.add_warning(f"Found {count} critical log entries for pattern: {pattern}")
                            
            except requests.RequestException:
                pass  # Log query failed, but not critical
    
    def add_issue(self, message: str):
        """Add a critical issue to the report"""
        self.health_report["issues"].append(message)
        self.health_report["overall_status"] = "UNHEALTHY"
        print(f"  ❌ ISSUE: {message}")
    
    def add_warning(self, message: str):
        """Add a warning to the report"""
        self.health_report["warnings"].append(message)
        if self.health_report["overall_status"] == "HEALTHY":
            self.health_report["overall_status"] = "WARNING"
        print(f"  ⚠️  WARNING: {message}")
    
    def add_action(self, message: str):
        """Record an automated action taken"""
        self.health_report["actions_taken"].append(message)
        print(f"  🔧 ACTION: {message}")
    
    def run_health_check(self) -> Dict:
        """Run complete health check and return report"""
        print("🏥 Kubernetes Health Manager - Health Check Starting")
        print("=" * 60)
        
        # Run all health checks
        node_health = self.check_node_health()
        api_health = self.check_kubernetes_api()
        container_health = self.check_container_metrics()
        self.check_critical_logs()
        
        print("=" * 60)
        print(f"🎯 Overall Status: {self.health_report['overall_status']}")
        
        if self.health_report["issues"]:
            print("\n❌ CRITICAL ISSUES:")
            for issue in self.health_report["issues"]:
                print(f"   • {issue}")
                
        if self.health_report["warnings"]:
            print("\n⚠️  WARNINGS:")
            for warning in self.health_report["warnings"]:
                print(f"   • {warning}")
                
        if self.health_report["actions_taken"]:
            print("\n🔧 ACTIONS TAKEN:")
            for action in self.health_report["actions_taken"]:
                print(f"   • {action}")
        
        return self.health_report

if __name__ == "__main__":
    health_manager = K8sHealthManager()
    report = health_manager.run_health_check()
    
    # Exit with appropriate code
    if report["overall_status"] == "UNHEALTHY":
        sys.exit(1)
    elif report["overall_status"] == "WARNING":
        sys.exit(2)
    else:
        sys.exit(0)