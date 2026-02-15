#!/bin/bash
# Kubernetes Health Manager - Deployment Validation
# Tests deployment readiness without requiring direct cluster access

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "🏥 K8s Health Manager - Deployment Validation"
echo "============================================="

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VALIDATION_PASSED=0
VALIDATION_ISSUES=0

log_test() {
    echo -e "${BLUE}🧪 TEST: $1${NC}"
}

log_pass() {
    echo -e "${GREEN}✅ PASS: $1${NC}"
    ((VALIDATION_PASSED++))
}

log_fail() {
    echo -e "${RED}❌ FAIL: $1${NC}"
    ((VALIDATION_ISSUES++))
}

log_info() {
    echo -e "   ℹ️  $1"
}

# Test 1: File Structure
log_test "File Structure Validation"
required_files=(
    "monitoring/kube-state-metrics.yaml"
    "scripts/fix-cadvisor.sh"
    "scripts/health-check.sh"
    "playbooks/deploy-monitoring.yml"
    "monitoring/prometheus-k8s-scrape-configs.yml"
)

for file in "${required_files[@]}"; do
    if [ -f "$SCRIPT_DIR/$file" ]; then
        log_pass "File exists: $file"
    else
        log_fail "Missing file: $file"
    fi
done

# Test 2: YAML Syntax Validation
log_test "YAML Syntax Validation"

# Test kube-state-metrics YAML
if python3 -c "
import yaml
try:
    with open('$SCRIPT_DIR/monitoring/kube-state-metrics.yaml', 'r') as f:
        docs = list(yaml.safe_load_all(f))
    print('✅ kube-state-metrics.yaml: Valid YAML with', len(docs), 'documents')
except Exception as e:
    print('❌ kube-state-metrics.yaml:', str(e))
    exit(1)
" 2>/dev/null; then
    log_pass "kube-state-metrics.yaml syntax"
else
    log_fail "kube-state-metrics.yaml syntax"
fi

# Test 3: Script Executability
log_test "Script Executability"
scripts=(
    "scripts/fix-cadvisor.sh"
    "scripts/health-check.sh"
    "scripts/deploy-monitoring.sh"
)

for script in "${scripts[@]}"; do
    if [ -x "$SCRIPT_DIR/$script" ]; then
        log_pass "Executable: $script"
    else
        log_fail "Not executable: $script"
    fi
done

# Test 4: Kubernetes Resource Validation
log_test "Kubernetes Resource Definitions"

# Extract and validate each K8s resource
python3 -c "
import yaml
import sys

try:
    with open('$SCRIPT_DIR/monitoring/kube-state-metrics.yaml', 'r') as f:
        docs = list(yaml.safe_load_all(f))
    
    resources = {}
    for doc in docs:
        if doc and 'kind' in doc:
            kind = doc['kind']
            name = doc.get('metadata', {}).get('name', 'unnamed')
            resources[kind] = resources.get(kind, []) + [name]
    
    print('📋 Kubernetes Resources:')
    for kind, names in resources.items():
        print(f'   {kind}: {len(names)} resources ({names})')
    
    # Validate required resources
    required = ['ServiceAccount', 'ClusterRole', 'ClusterRoleBinding', 'Service', 'Deployment']
    for req in required:
        if req in resources:
            print(f'✅ Required resource present: {req}')
        else:
            print(f'❌ Missing required resource: {req}')
            sys.exit(1)
            
except Exception as e:
    print(f'❌ Resource validation failed: {e}')
    sys.exit(1)
"

if [ $? -eq 0 ]; then
    log_pass "All required K8s resources defined"
else
    log_fail "K8s resource validation failed"
fi

# Test 5: Health Check Script Logic
log_test "Health Check Script Validation"

# Test the health check script syntax
if bash -n "$SCRIPT_DIR/scripts/health-check.sh"; then
    log_pass "health-check.sh bash syntax"
else
    log_fail "health-check.sh bash syntax"
fi

# Test cAdvisor fix script syntax
if bash -n "$SCRIPT_DIR/scripts/fix-cadvisor.sh"; then
    log_pass "fix-cadvisor.sh bash syntax"
else
    log_fail "fix-cadvisor.sh bash syntax"
fi

# Test 6: Prometheus Configuration Validation
log_test "Prometheus Configuration"

if [ -f "$SCRIPT_DIR/monitoring/prometheus-k8s-scrape-configs.yml" ]; then
    # Count scrape jobs
    job_count=$(grep -c "job_name:" "$SCRIPT_DIR/monitoring/prometheus-k8s-scrape-configs.yml" || echo "0")
    if [ "$job_count" -gt 3 ]; then
        log_pass "Prometheus scrape configs ($job_count jobs defined)"
        log_info "Jobs include: kube-state-metrics, kubernetes-cadvisor, kubernetes-apiservers, etc."
    else
        log_fail "Insufficient Prometheus scrape configs ($job_count jobs)"
    fi
else
    log_fail "Missing Prometheus configuration"
fi

# Test 7: Deployment Readiness
log_test "Deployment Readiness Assessment"

# Check if this would work with current cluster status
echo ""
echo "📊 Current Cluster Status Check:"
curl -s -k "https://192.168.1.99:6443/healthz" 2>/dev/null | head -1 | grep -q "ok" && \
    log_pass "K8s API accessible" || log_fail "K8s API not accessible"

curl -s "http://prometheus.home/api/v1/query?query=up{job='node_exporter'}" 2>/dev/null | \
    grep -q "kube50[1-3]" && \
    log_pass "Node exporters responding" || log_fail "Node exporters not responding"

# Test 8: Expected Impact Assessment  
log_test "Impact Assessment"

echo ""
log_info "This deployment will:"
log_info "• Deploy kube-state-metrics to kube-system namespace"
log_info "• Install cAdvisor v0.49.1 on all cluster nodes"  
log_info "• Create systemd services for cAdvisor"
log_info "• Set up automated health monitoring"
log_info "• Add comprehensive K8s metrics collection"

echo ""
log_info "Estimated deployment time: 5-10 minutes"
log_info "Estimated resource usage: <100MB memory, <0.1 CPU across cluster"
log_info "Risk level: LOW (non-destructive additions only)"

# Final Results
echo ""
echo "============================================="
echo -e "🎯 VALIDATION SUMMARY"
echo "============================================="
echo "✅ Tests passed: $VALIDATION_PASSED"
echo "❌ Issues found: $VALIDATION_ISSUES"

if [ $VALIDATION_ISSUES -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🚀 DEPLOYMENT READY${NC}"
    echo "All validation tests passed. Deployment package is ready for execution."
    echo ""
    echo "Next steps:"
    echo "1. Run ansible-playbook deploy-monitoring.yml (dry run first)"  
    echo "2. Execute actual deployment"
    echo "3. Verify metrics collection"
    exit 0
else
    echo ""
    echo -e "${RED}⚠️  ISSUES DETECTED${NC}" 
    echo "Please resolve the above issues before deployment."
    exit 1
fi