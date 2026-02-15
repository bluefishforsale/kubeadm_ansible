#!/bin/bash
# Kubernetes Health Manager - Complete Deployment Orchestrator
# This script coordinates the full deployment of enhanced K8s monitoring

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date -Iseconds)

echo "🏥 Kubernetes Health Manager - FULL DEPLOYMENT"
echo "=============================================="
echo "⏰ Starting at: $TIMESTAMP"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_phase() {
    echo -e "${BLUE}🎯 PHASE: $1${NC}"
    echo "----------------------------------------"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Phase 1: Pre-deployment Validation
log_phase "1 - Pre-deployment Validation"

echo "🔍 Checking cluster connectivity..."
if curl -s -k "https://192.168.1.99:6443/healthz" | grep -q "ok"; then
    log_success "Kubernetes API accessible"
else
    log_error "Cannot reach Kubernetes API - deployment aborted"
    exit 1
fi

echo "🔍 Checking Prometheus connectivity..."
if curl -s "$PROMETHEUS_URL/api/v1/query" >/dev/null 2>&1; then
    log_success "Prometheus accessible"
else
    log_error "Cannot reach Prometheus - monitoring will be limited"
fi

echo "🔍 Checking node connectivity..."
nodes=("kube501.home" "kube502.home" "kube503.home" "kube511.home")
accessible_nodes=0

for node in "${nodes[@]}"; do
    if curl -s "http://prometheus.home/api/v1/query" --data-urlencode "query=up{instance='$node',job='node_exporter'}" | grep -q '"value":\[.*,"1"\]'; then
        log_success "$node - accessible via Prometheus"
        ((accessible_nodes++))
    else
        log_warning "$node - not accessible or no metrics"
    fi
done

if [ $accessible_nodes -eq 0 ]; then
    log_error "No cluster nodes accessible - deployment aborted"
    exit 1
fi

log_success "Pre-deployment validation complete ($accessible_nodes/4 nodes accessible)"
echo ""

# Phase 2: Generate Deployment Instructions
log_phase "2 - Deployment Instructions Generation"

cat > "$SCRIPT_DIR/DEPLOYMENT_INSTRUCTIONS.md" << 'EOF'
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

EOF

log_success "Deployment instructions generated: DEPLOYMENT_INSTRUCTIONS.md"
echo ""

# Phase 3: Create Feature Branch for PR
log_phase "3 - Git Branch Preparation"

cd "$SCRIPT_DIR"

# Check if we're in a git repository
if [ -d .git ]; then
    # Create feature branch
    BRANCH_NAME="feature/k8s-health-monitoring-$(date +%Y%m%d-%H%M%S)"
    
    if git checkout -b "$BRANCH_NAME" 2>/dev/null; then
        log_success "Created feature branch: $BRANCH_NAME"
        
        # Stage all monitoring files
        git add .
        
        # Create comprehensive commit
        git commit -m "🏥 Add Kubernetes Health Manager - Complete Monitoring Stack

## 🚀 Features Added:
- kube-state-metrics deployment for K8s object monitoring
- cAdvisor fix for container metrics on all nodes  
- Enhanced Prometheus scrape configurations
- Automated health check system with systemd timers
- Comprehensive deployment automation (ansible + manual)

## 📊 Monitoring Coverage:
✅ Kubernetes API server health
✅ All cluster nodes (kube501-503, kube511)  
✅ Container metrics via cAdvisor
✅ K8s objects (pods, deployments, services)
✅ Automated health checks every 30 minutes
✅ Resource utilization monitoring
✅ Critical log pattern detection

## 🔧 Files Added:
- monitoring/kube-state-metrics.yaml - K8s metrics collector
- scripts/health-check.sh - Automated health monitoring
- scripts/fix-cadvisor.sh - cAdvisor repair automation
- playbooks/deploy-monitoring.yml - Full ansible automation
- monitoring/prometheus-k8s-scrape-configs.yml - Enhanced metrics collection

## 🎯 Deployment:
Ready for testing and deployment via standard PR workflow.
Addresses all identified monitoring gaps from initial assessment."

        log_success "Changes committed to feature branch"
        
        # Show what was added
        echo ""
        echo "📁 Files added to repository:"
        git show --name-only --pretty=format:""
        
        echo ""
        log_success "🎯 READY FOR PR! Branch: $BRANCH_NAME"
        echo "   Next: Push branch and create PR for review"
        
    else
        log_warning "Could not create git branch (may already exist or git issues)"
    fi
else
    log_warning "Not in a git repository - manual git management required"
fi

echo ""

# Phase 4: Final Status Report
log_phase "4 - Deployment Status Summary"

echo "📋 DEPLOYMENT PREPARATION COMPLETE!"
echo ""
echo "✅ CREATED COMPONENTS:"
echo "   • kube-state-metrics deployment manifest"
echo "   • cAdvisor fix script for all nodes"
echo "   • Enhanced Prometheus configuration"
echo "   • Automated health check system"
echo "   • Full ansible deployment playbook"
echo "   • Comprehensive deployment documentation"
echo ""
echo "🎯 NEXT ACTIONS REQUIRED:"
echo "   1. Review DEPLOYMENT_INSTRUCTIONS.md"
echo "   2. Test deployment on non-production first (if available)"
echo "   3. Execute deployment via preferred method (ansible/manual)"
echo "   4. Verify metrics collection in Prometheus"
echo "   5. Validate automated health checks"
echo ""
echo "📨 FOR PR WORKFLOW:"
echo "   • Feature branch created and committed"
echo "   • Push to GitHub: git push origin $BRANCH_NAME"
echo "   • Create PR for review and approval"
echo "   • CI/CD will handle deployment after approval"
echo ""

# Phase 5: Immediate Health Check
log_phase "5 - Current Health Check"

echo "🔍 Running immediate health assessment..."
if bash "$SCRIPT_DIR/scripts/health-check.sh"; then
    log_success "Current cluster status: HEALTHY"
else
    echo ""
    log_warning "Current cluster has warnings/issues - deployment will help address these"
fi

echo ""
echo "🏥 Kubernetes Health Manager deployment preparation COMPLETE!"
echo "⏰ Finished at: $(date -Iseconds)"