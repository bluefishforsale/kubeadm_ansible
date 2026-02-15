#!/bin/bash
# Test script to validate ansible deployment readiness
# Run this from your ansible management host (where you normally run kubeadm_ansible)

set -e

echo "🤖 Testing Ansible Deployment for K8s Health Manager"
echo "=================================================="

# Check environment
echo "🔍 Environment Check:"
echo ""

# Check ansible
if command -v ansible-playbook &> /dev/null; then
    echo "✅ ansible-playbook: $(ansible-playbook --version | head -1)"
else
    echo "❌ ansible-playbook: NOT FOUND"
    exit 1
fi

# Check inventory
if [ -f "inventories/production/hosts.ini" ]; then
    echo "✅ inventory: Found"
else
    echo "❌ inventory: inventories/production/hosts.ini not found"
    exit 1
fi

# Check ansible vault password
if [ -n "$ANSIBLE_VAULT_PASSWORD" ]; then
    echo "✅ vault password: Set in environment"
else
    echo "⚠️  vault password: Not set (may be needed)"
fi

echo ""
echo "🎯 Target Hosts:"
ansible k8s_controller --list-hosts -i inventories/production/hosts.ini | grep -v "hosts (" || echo "Could not list controller hosts"
ansible k8s --list-hosts -i inventories/production/hosts.ini | grep -v "hosts (" || echo "Could not list k8s hosts"

echo ""
echo "🔌 Connectivity Test:"
ansible k8s -i inventories/production/hosts.ini -m ping | head -10

echo ""
echo "📋 Playbook Syntax Check:"
ansible-playbook k8s-health-monitoring/playbooks/deploy-monitoring.yml --syntax-check

echo ""
echo "🧪 DRY RUN (what would happen):"
ansible-playbook k8s-health-monitoring/playbooks/deploy-monitoring.yml --check --diff

echo ""
echo "✅ TEST COMPLETE!"
echo ""
echo "🚀 To actually deploy, run:"
echo "   ansible-playbook k8s-health-monitoring/playbooks/deploy-monitoring.yml"
echo ""
echo "📊 What this will do:"
echo "   1. Deploy kube-state-metrics to kube-system namespace"
echo "   2. Install/fix cAdvisor on all cluster nodes"
echo "   3. Set up automated health checking"
echo "   4. Create monitoring directories and services"