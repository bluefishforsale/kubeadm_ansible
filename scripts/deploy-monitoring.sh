#!/bin/bash
# Kubernetes Health Manager - Manual Deployment Script
# Run this script on a node with kubectl access to the cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORING_DIR="$(dirname "$SCRIPT_DIR")/monitoring"

echo "🏥 Kubernetes Health Manager - Complete Deployment"
echo "=================================================="

# Check kubectl access
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl and configure access to the cluster."
    exit 1
fi

# Test cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

echo "✅ kubectl access verified"

# Deploy kube-state-metrics
echo ""
echo "🔍 Deploying kube-state-metrics..."
if kubectl apply -f "$MONITORING_DIR/kube-state-metrics.yaml"; then
    echo "✅ kube-state-metrics deployed successfully"
    
    echo "⏳ Waiting for kube-state-metrics to be ready..."
    if kubectl wait --for=condition=available --timeout=300s deployment/kube-state-metrics -n kube-system; then
        echo "✅ kube-state-metrics is ready"
    else
        echo "⚠️  kube-state-metrics deployment may still be starting"
    fi
else
    echo "❌ Failed to deploy kube-state-metrics"
    exit 1
fi

# Verify the deployment
echo ""
echo "🔍 Verifying kube-state-metrics..."
if kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-state-metrics | grep Running; then
    echo "✅ kube-state-metrics pod is running"
else
    echo "⚠️  kube-state-metrics pod status:"
    kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-state-metrics
fi

# Check if metrics are available
echo ""
echo "🔍 Testing kube-state-metrics endpoint..."
if kubectl port-forward -n kube-system svc/kube-state-metrics 8080:8080 &
then
    PORT_FORWARD_PID=$!
    sleep 5
    
    if curl -s http://localhost:8080/metrics | head -5; then
        echo "✅ kube-state-metrics endpoint is responding"
    else
        echo "⚠️  kube-state-metrics endpoint check failed"
    fi
    
    kill $PORT_FORWARD_PID 2>/dev/null || true
fi

echo ""
echo "📊 Current cluster metrics status:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-state-metrics
kubectl get svc -n kube-system -l app.kubernetes.io/name=kube-state-metrics

echo ""
echo "🎯 Next Steps:"
echo "1. Configure Prometheus to scrape kube-state-metrics service"
echo "2. Deploy/fix cAdvisor on all cluster nodes"
echo "3. Verify metrics collection in Prometheus"
echo ""
echo "✅ kube-state-metrics deployment complete!"