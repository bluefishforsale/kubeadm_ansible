#!/bin/bash
# Kubernetes Health Manager - Automated Health Check (Shell Version)
# Monitors cluster health using curl and basic shell commands

set -e

PROMETHEUS_URL="http://prometheus.home"
K8S_API_URL="https://192.168.1.99:6443"
TIMESTAMP=$(date -Iseconds)

echo "🏥 Kubernetes Health Manager - Health Check Starting"
echo "============================================================"
echo "⏰ Timestamp: $TIMESTAMP"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

OVERALL_STATUS="HEALTHY"
ISSUES_COUNT=0
WARNINGS_COUNT=0

log_issue() {
    echo -e "${RED}  ❌ ISSUE: $1${NC}"
    OVERALL_STATUS="UNHEALTHY"
    ((ISSUES_COUNT++))
}

log_warning() {
    echo -e "${YELLOW}  ⚠️  WARNING: $1${NC}"
    if [ "$OVERALL_STATUS" = "HEALTHY" ]; then
        OVERALL_STATUS="WARNING"
    fi
    ((WARNINGS_COUNT++))
}

log_success() {
    echo -e "${GREEN}  ✅ $1${NC}"
}

log_info() {
    echo "  ℹ️  $1"
}

# Function to query Prometheus
query_prometheus() {
    local query="$1"
    curl -s "${PROMETHEUS_URL}/api/v1/query" --data-urlencode "query=${query}" 2>/dev/null | \
    python3 -c "import sys, json; data=json.load(sys.stdin); print(json.dumps(data.get('data', {}), indent=2))" 2>/dev/null || echo "{}"
}

# Check Kubernetes API Health
check_k8s_api() {
    echo "🎛️  Checking Kubernetes API Health..."
    
    if response=$(curl -s -k "${K8S_API_URL}/healthz" --connect-timeout 5 2>/dev/null); then
        if [ "$response" = "ok" ]; then
            log_success "API Server - HEALTHY"
            return 0
        else
            log_issue "API server returned: $response"
            return 1
        fi
    else
        log_issue "Cannot reach Kubernetes API at $K8S_API_URL"
        return 1
    fi
}

# Check Node Health via Prometheus
check_node_health() {
    echo "🖥️  Checking Node Health..."
    
    # Check if prometheus is accessible
    if ! curl -s "$PROMETHEUS_URL/api/v1/query" >/dev/null 2>&1; then
        log_issue "Cannot reach Prometheus at $PROMETHEUS_URL"
        return 1
    fi
    
    # Query node exporter status
    local response=$(query_prometheus "up{job='node_exporter'}")
    
    if [ "$response" = "{}" ]; then
        log_issue "No response from Prometheus for node_exporter metrics"
        return 1
    fi
    
    # Check specific nodes
    local nodes=("kube501.home" "kube502.home" "kube503.home" "kube511.home")
    
    for node in "${nodes[@]}"; do
        local node_status=$(echo "$response" | grep -o "\"instance\":\"$node\"" -A 10 | grep -o '"value":\[.*,"[01]"\]' | cut -d'"' -f4 || echo "missing")
        
        case $node_status in
            "1")
                log_success "$node - UP"
                ;;
            "0")
                log_issue "Node exporter down on $node"
                ;;
            *)
                log_warning "No metrics found for $node"
                ;;
        esac
    done
}

# Check Container Metrics (cAdvisor)
check_container_metrics() {
    echo "🐳 Checking Container Metrics..."
    
    local response=$(query_prometheus "up{job='cadvisor'}")
    
    if [ "$response" = "{}" ]; then
        log_warning "No cAdvisor metrics available"
        return 1
    fi
    
    local nodes=("kube501.home" "kube502.home" "kube503.home" "kube511.home")
    
    for node in "${nodes[@]}"; do
        local cadvisor_status=$(echo "$response" | grep -o "\"instance\":\"$node\"" -A 10 | grep -o '"value":\[.*,"[01]"\]' | cut -d'"' -f4 || echo "missing")
        
        case $cadvisor_status in
            "1")
                log_success "$node cAdvisor - UP"
                ;;
            "0")
                log_issue "cAdvisor down on $node"
                ;;
            *)
                log_warning "cAdvisor not reporting from $node"
                ;;
        esac
    done
}

# Check Node Resource Usage
check_node_resources() {
    echo "📊 Checking Node Resources..."
    
    # Check CPU usage
    local cpu_response=$(query_prometheus '(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)) * 100')
    
    if [ "$cpu_response" != "{}" ]; then
        local nodes=("kube501.home" "kube502.home" "kube503.home" "kube511.home")
        for node in "${nodes[@]}"; do
            local cpu_usage=$(echo "$cpu_response" | grep -o "\"instance\":\"$node\"" -A 10 | grep -o '"value":\[.*,"[0-9.]*"\]' | cut -d'"' -f4 || echo "unknown")
            
            if [ "$cpu_usage" != "unknown" ]; then
                local cpu_int=$(echo "$cpu_usage" | cut -d'.' -f1)
                log_info "$node CPU: ${cpu_usage}%"
                
                if [ "$cpu_int" -gt 90 ]; then
                    log_issue "High CPU usage on $node: ${cpu_usage}%"
                elif [ "$cpu_int" -gt 75 ]; then
                    log_warning "Elevated CPU usage on $node: ${cpu_usage}%"
                fi
            fi
        done
    fi
    
    # Check Memory usage
    local memory_response=$(query_prometheus '(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100')
    
    if [ "$memory_response" != "{}" ]; then
        local nodes=("kube501.home" "kube502.home" "kube503.home" "kube511.home")
        for node in "${nodes[@]}"; do
            local memory_usage=$(echo "$memory_response" | grep -o "\"instance\":\"$node\"" -A 10 | grep -o '"value":\[.*,"[0-9.]*"\]' | cut -d'"' -f4 || echo "unknown")
            
            if [ "$memory_usage" != "unknown" ]; then
                local memory_int=$(echo "$memory_usage" | cut -d'.' -f1)
                log_info "$node Memory: ${memory_usage}%"
                
                if [ "$memory_int" -gt 90 ]; then
                    log_issue "High memory usage on $node: ${memory_usage}%"
                elif [ "$memory_int" -gt 80 ]; then
                    log_warning "Elevated memory usage on $node: ${memory_usage}%"
                fi
            fi
        done
    fi
}

# Check for kube-state-metrics
check_kube_state_metrics() {
    echo "🔍 Checking Kubernetes State Metrics..."
    
    local response=$(query_prometheus "up{job='kube-state-metrics'}")
    
    if [ "$response" = "{}" ] || [ "$(echo "$response" | grep -c '"result":\[\]')" -eq 1 ]; then
        log_warning "kube-state-metrics not deployed - missing K8s object metrics"
        return 1
    else
        log_success "kube-state-metrics - Available"
        return 0
    fi
}

# Main health check execution
main() {
    check_k8s_api
    check_node_health
    check_container_metrics
    check_node_resources
    check_kube_state_metrics
    
    echo ""
    echo "============================================================"
    echo -e "🎯 Overall Status: ${OVERALL_STATUS}"
    echo "📊 Issues: $ISSUES_COUNT | Warnings: $WARNINGS_COUNT"
    echo ""
    
    if [ "$ISSUES_COUNT" -gt 0 ]; then
        echo -e "${RED}❌ CRITICAL ISSUES DETECTED - Requires immediate attention${NC}"
        exit 1
    elif [ "$WARNINGS_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  WARNINGS DETECTED - Consider addressing${NC}"
        exit 2
    else
        echo -e "${GREEN}✅ CLUSTER HEALTHY - All systems operational${NC}"
        exit 0
    fi
}

main "$@"