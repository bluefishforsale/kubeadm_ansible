#!/bin/bash
# Kubernetes Health Manager - Fixed Deployment Validation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "🏥 K8s Health Manager - Deployment Validation"
echo "============================================="

PASS_COUNT=0
FAIL_COUNT=0

test_pass() {
    echo "✅ $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_fail() {
    echo "❌ $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

# Test file existence
echo ""
echo "📁 File Structure Check:"

[ -f "monitoring/kube-state-metrics.yaml" ] && test_pass "Found: kube-state-metrics.yaml" || test_fail "Missing: kube-state-metrics.yaml"
[ -f "scripts/fix-cadvisor.sh" ] && test_pass "Found: fix-cadvisor.sh" || test_fail "Missing: fix-cadvisor.sh"
[ -f "scripts/health-check.sh" ] && test_pass "Found: health-check.sh" || test_fail "Missing: health-check.sh"
[ -f "playbooks/deploy-monitoring.yml" ] && test_pass "Found: deploy-monitoring.yml" || test_fail "Missing: deploy-monitoring.yml"

# Test executability
echo ""
echo "🔧 Script Permissions:"
[ -x "scripts/fix-cadvisor.sh" ] && test_pass "Executable: fix-cadvisor.sh" || test_fail "Not executable: fix-cadvisor.sh"
[ -x "scripts/health-check.sh" ] && test_pass "Executable: health-check.sh" || test_fail "Not executable: health-check.sh"

# Basic content validation
echo ""
echo "📝 Content Validation:"
if grep -q "kube-state-metrics" monitoring/kube-state-metrics.yaml; then
    test_pass "kube-state-metrics.yaml contains expected content"
else
    test_fail "kube-state-metrics.yaml missing expected content"
fi

if grep -q "cadvisor" scripts/fix-cadvisor.sh; then
    test_pass "fix-cadvisor.sh contains cadvisor setup"
else
    test_fail "fix-cadvisor.sh missing cadvisor setup"
fi

# Bash syntax check
echo ""
echo "🔍 Script Syntax Check:"
bash -n scripts/fix-cadvisor.sh 2>/dev/null && test_pass "fix-cadvisor.sh syntax OK" || test_fail "fix-cadvisor.sh syntax error"
bash -n scripts/health-check.sh 2>/dev/null && test_pass "health-check.sh syntax OK" || test_fail "health-check.sh syntax error"

# Connectivity tests
echo ""
echo "🔗 Infrastructure Check:"
curl -s -k --connect-timeout 5 "https://192.168.1.99:6443/healthz" 2>/dev/null | grep -q "ok" && test_pass "K8s API accessible" || test_fail "K8s API not accessible"
curl -s --connect-timeout 5 "http://prometheus.home" >/dev/null 2>&1 && test_pass "Prometheus accessible" || test_fail "Prometheus not accessible"

# Current gaps analysis
echo ""
echo "📊 Monitoring Gaps Analysis:"
echo "   Checking what we'll deploy..."

# Check for kube-state-metrics
if curl -s "http://prometheus.home/api/v1/query?query=kube_node_info" 2>/dev/null | grep -q '"result":\[\]'; then
    echo "   ℹ️  kube-state-metrics: Missing (will deploy)"
else
    echo "   ℹ️  kube-state-metrics: Present"
fi

# Check cAdvisor on cluster nodes
cadvisor_missing=0
for node in kube501.home kube502.home kube503.home kube511.home; do
    if curl -s "http://prometheus.home/api/v1/query?query=up{instance='$node',job='cadvisor'}" 2>/dev/null | grep -q '"value":\[.*,"0"\]'; then
        cadvisor_missing=$((cadvisor_missing + 1))
    fi
done

if [ $cadvisor_missing -gt 0 ]; then
    echo "   ℹ️  cAdvisor: $cadvisor_missing nodes need fixing"
else
    echo "   ℹ️  cAdvisor: Working on all nodes"
fi

# Summary
echo ""
echo "============================================="
echo "🎯 VALIDATION SUMMARY"
echo "============================================="
echo "✅ Passed: $PASS_COUNT"
echo "❌ Failed: $FAIL_COUNT"

if [ $FAIL_COUNT -eq 0 ]; then
    echo ""
    echo "🚀 DEPLOYMENT READY!"
    echo ""
    echo "📦 What will be deployed:"
    echo "   • kube-state-metrics for K8s object monitoring"
    echo "   • cAdvisor fixes for container metrics"
    echo "   • Health monitoring automation"
    echo ""
    echo "🎯 Next step: Run actual deployment"
    exit 0
else
    echo ""
    echo "⚠️  Issues found. Please review above."
    exit 1
fi