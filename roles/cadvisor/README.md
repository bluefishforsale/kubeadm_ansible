# cAdvisor Role

Deploys cAdvisor as a Kubernetes DaemonSet for container metrics collection.

## Overview

cAdvisor (Container Advisor) provides container users an understanding of the resource usage and performance characteristics of their running containers. It exposes Prometheus metrics on port 8080.

## What This Role Does

1. Creates `monitoring` namespace (if not exists)
2. Deploys cAdvisor as a DaemonSet (runs on all nodes)
3. Creates a headless Service for Prometheus service discovery
4. Waits for all cAdvisor pods to become ready

## Requirements

- Kubernetes cluster initialized
- `kubernetes.core` Ansible collection installed
- Access to `/etc/kubernetes/admin.conf` on master node

## Metrics Exposed

- Container CPU usage
- Container memory usage  
- Container network I/O
- Container filesystem usage
- Container restart counts

## Prometheus Integration

cAdvisor metrics are accessible at `http://<node-ip>:8080/metrics` on each node.

Configure Prometheus to scrape cAdvisor endpoints:

```yaml
scrape_configs:
  - job_name: 'kubernetes-cadvisor'
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
            - monitoring
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: keep
        regex: cadvisor
```

## Usage

### Deploy cAdvisor

```bash
ansible-playbook playbooks/deploy-cadvisor.yml -i inventories/production/hosts.ini
```

### Verify Deployment

```bash
kubectl get pods -n monitoring -l app=cadvisor
kubectl get daemonset -n monitoring cadvisor
```

### Check Metrics

```bash
# From any k8s node:
curl http://localhost:8080/metrics
```

## Troubleshooting

### Pods not starting

Check pod events:
```bash
kubectl describe pod -n monitoring -l app=cadvisor
```

### No metrics showing

Verify cAdvisor is listening:
```bash
kubectl exec -n monitoring -it <cadvisor-pod> -- wget -O- http://localhost:8080/metrics
```

## Related Issues

- Fixes Issue #2: Fix cAdvisor on all k8s nodes
