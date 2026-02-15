# Kubernetes Health Manager - Manual Deployment Instructions

## ⚠️ IMPORTANT: Run from Management Host
These commands must be executed from a host with:
- kubectl access to the cluster (kubeconfig configured)
- SSH access to cluster nodes
- ansible (optional, for automated deployment)

## 🚀 Option A: Automated Ansible Deployment
```bash
# From the kubeadm_ansible directory with ansible available:
ansible-playbook k8s-health-monitoring/playbooks/deploy-monitoring.yml

# This will:
# - Deploy kube-state-metrics to the cluster
# - Fix cAdvisor on all nodes
# - Set up automated health checks
```

## 🔧 Option B: Manual Step-by-Step Deployment

### Step 1: Deploy kube-state-metrics
```bash
# Run from host with kubectl access:
kubectl apply -f k8s-health-monitoring/monitoring/kube-state-metrics.yaml

# Wait for deployment to be ready:
kubectl wait --for=condition=available --timeout=300s deployment/kube-state-metrics -n kube-system

# Verify deployment:
kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-state-metrics
```

### Step 2: Fix cAdvisor on Each Node
```bash
# Run on each cluster node (kube501, kube502, kube503, kube511):
sudo bash k8s-health-monitoring/scripts/fix-cadvisor.sh

# Or via SSH from management host:
for node in kube501 kube502 kube503 kube511; do
    ssh debian@$node "sudo bash" < k8s-health-monitoring/scripts/fix-cadvisor.sh
done
```

### Step 3: Update Prometheus Configuration
```bash
# Add the contents of k8s-health-monitoring/monitoring/prometheus-k8s-scrape-configs.yml 
# to your prometheus.yml configuration file

# Then restart Prometheus to pick up the new scrape targets
```

### Step 4: Deploy Health Check Automation
```bash
# Run on management node or first control node:
sudo cp k8s-health-monitoring/scripts/health-check.sh /opt/k8s-monitoring/
sudo systemctl enable k8s-health-check.timer
sudo systemctl start k8s-health-check.timer
```

## 🔍 Verification Commands

### Check kube-state-metrics
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-state-metrics
kubectl logs -n kube-system -l app.kubernetes.io/name=kube-state-metrics
```

### Check cAdvisor on nodes
```bash
for node in kube501 kube502 kube503 kube511; do
    echo "=== $node ==="
    ssh debian@$node "systemctl status cadvisor"
done
```

### Verify metrics in Prometheus
```bash
# Check that new metrics are appearing:
curl -s "http://prometheus.home/api/v1/query?query=kube_node_info" | jq .
curl -s "http://prometheus.home/api/v1/query?query=container_memory_usage_bytes" | jq .
```

## 🎯 Expected Results

After successful deployment, you should see:

### In Prometheus Targets:
- `kube-state-metrics` - Providing K8s object metrics
- `kubernetes-cadvisor` - All 4 nodes providing container metrics
- `kubernetes-nodes` - Node metrics from kubelet

### New Metric Categories Available:
- `kube_*` metrics - Pod status, deployment health, service discovery
- `container_*` metrics - Container resource usage, restart counts  
- `kubernetes_*` labels - Proper labeling for K8s correlation

### Automated Monitoring:
- Health checks running every 30 minutes
- Proactive alerts for resource usage >75%
- Automatic service restart capability
- Comprehensive logging to Loki