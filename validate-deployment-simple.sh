#!/bin/bash
# Kubernetes Health Manager - Simple Deployment Validation
# Tests deployment readiness without external dependencies

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "🏥 K8s Health Manager - Deployment Validation"
echo "============================================="

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

test_pass() {
    echo -e "${GREEN}✅ $1${NC}"
    ((PASS_COUNT++))
}

test_fail() {
    echo -e "${RED}❌ $1${NC}"
    ((FAIL_COUNT++))
}

test_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Test file existence
echo ""
echo "📁 File Structure Check:"
required_files=(
    "monitoring/kube-state-metrics.yaml"
    "scripts/fix-cadvisor.sh"
    "scripts/health-check.sh"
    "playbooks/deploy-monitoring.yml"
)

for file in "${required_files[@]}"; do
    if [ -f "$SCRIPT_DIR/$file" ]; then
        test_pass "Found: $file"
    else
        test_fail "Missing: $file"
    fi
done

# Test script executability
echo ""
echo "🔧 Script Permissions:"
for script in scripts/*.sh; do
    if [ -x "$SCRIPT_DIR/$script" ]; then
        test_pass "Executable: $script"
    else
        test_fail "Not executable: $script"
    fi
done

# Basic YAML structure validation
echo ""
echo "📝 YAML Structure Check:"
if grep -q "apiVersion.*v1" "$SCRIPT_DIR/monitoring/kube-state-metrics.yaml"; then
    test_pass "kube-state-metrics.yaml has valid K8s apiVersion"
else
    test_fail "kube-state-metrics.yaml missing apiVersion"
fi

if grep -q "kind.*Deployment" "$SCRIPT_DIR/monitoring/kube-state-metrics.yaml"; then
    test_pass "kube-state-metrics.yaml contains Deployment"
else
    test_fail "kube-state-metrics.yaml missing Deployment"
fi

# Test bash syntax
echo ""
echo "🔍 Script Syntax Check:"
for script in scripts/*.sh; do
    if bash -n "$SCRIPT_DIR/$script" 2>/dev/null; then
        test_pass "Syntax OK: $script"
    else
        test_fail "Syntax error: $script"
    fi
done

# Test current cluster connectivity
echo ""
echo "🔗 Cluster Connectivity:"
if curl -s -k --connect-timeout 5 "https://192.168.1.99:6443/healthz" 2>/dev/null | grep -q "ok"; then
    test_pass "Kubernetes API accessible"
else
    test_fail "Kubernetes API not accessible"
fi

if curl -s --connect-timeout 5 "http://prometheus.home/api/v1/query?query=up" 2>/dev/null | grep -q '"status":"success"'; then
    test_pass "Prometheus API accessible"
else
    test_fail "Prometheus API not accessible"
fi

# Check existing monitoring gaps
echo ""
echo "📊 Current Monitoring Gaps (what we'll fix):"
kube_state_result=$(curl -s "http://prometheus.home/api/v1/query?query=kube_node_info" 2>/dev/null)
if echo "$kube_state_result" | grep -q '"result":\[\]'; then
    test_info "Missing: kube-state-metrics (will be deployed)"
else
    test_info "Present: kube-state-metrics already exists"
fi

cadvisor_result=$(curl -s "http://prometheus.home/api/v1/query?query=up{job='cadvisor',instance~='kube.*'}" 2>/dev/null)
if echo "$cadvisor_result" | grep -q '"value":\[.*,"0"\]' || echo "$cadvisor_result" | grep -q '"result":\[\]'; then
    test_info "Missing: cAdvisor on cluster nodes (will be fixed)"
else
    test_info "Present: cAdvisor working on cluster nodes"
fi

# Summary
echo ""
echo "============================================="
echo -e "🎯 VALIDATION RESULTS"
echo "============================================="
echo "✅ Passed: $PASS_COUNT"
echo "❌ Failed: $FAIL_COUNT"

if [ $FAIL_COUNT -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🚀 DEPLOYMENT PACKAGE VALIDATED${NC}"
    echo ""
    echo "📦 Ready to deploy:"
    echo "   • kube-state-metrics for K8s object monitoring"
    echo "   • cAdvisor fixes for container metrics"  
    echo "   • Automated health monitoring system"
    echo ""
    echo "🎯 Deployment methods available:"
    echo "   1. ansible-playbook playbooks/deploy-monitoring.yml"
    echo "   2. Manual step-by-step via DEPLOYMENT_INSTRUCTIONS.md"
    echo ""
    exit 0
else
    echo ""
    echo -e "${RED}⚠️  VALIDATION ISSUES FOUND${NC}"
    echo "Please fix the above issues before deployment."
    exit 1
fi