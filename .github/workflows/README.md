# GitOps CI/CD Workflows

This directory contains GitHub Actions workflows for automated infrastructure deployment and management.

## 🚀 Workflows Overview

### 1. `validate.yml` - PR Validation
**Trigger:** Pull requests to main/master
**Purpose:** Validate changes before merge

**What it does:**
- Ansible syntax checking and linting
- Kubernetes manifest validation  
- Security scanning for secrets/hardcoded values
- Dry-run testing with mock inventory
- Generates deployment readiness summary

### 2. `deploy.yml` - Production Deployment  
**Trigger:** Push to main/master, manual dispatch
**Purpose:** Deploy changes to production infrastructure

**What it does:**
- Connects to homelab infrastructure via self-hosted runner
- Runs ansible playbooks against production inventory
- Verifies deployment success
- Sends Discord notifications
- Supports manual playbook selection and dry-run mode

### 3. `manual-operations.yml` - Ad-hoc Operations
**Trigger:** Manual dispatch only
**Purpose:** Manual infrastructure operations and maintenance

**Operations available:**
- `health-check` - Run health diagnostics
- `restart-services` - Restart specific services  
- `update-monitoring` - Deploy monitoring stack updates
- `cluster-status` - Get comprehensive cluster status
- `backup-config` - Backup critical configurations
- `roll-back` - Revert recent deployments

## 🔧 Setup Requirements

### 1. GitHub Secrets Required

Add these secrets to your repository settings:

```bash
# SSH key for ansible connections
ANSIBLE_SSH_PRIVATE_KEY=<your-ssh-private-key>

# Ansible vault password  
ANSIBLE_VAULT_PASSWORD=<your-vault-password>

# Discord webhook for notifications
DISCORD_WEBHOOK=<your-discord-webhook-url>
```

### 2. Self-Hosted Runner Setup

The deployment workflows require a self-hosted GitHub runner with:

**Network Access:**
- Access to homelab network (192.168.1.0/24)
- SSH connectivity to all target hosts
- Internet access for GitHub API

**Software Requirements:**
- Ubuntu 20.04+ (recommended)
- Python 3.11+
- Git
- Network connectivity to infrastructure

**Installation:**
```bash
# On your runner host (could be node005 or dedicated VM)
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz
./config.sh --url https://github.com/bluefishforsale/kubeadm_ansible --token YOUR_TOKEN
./run.sh

# To run as a service:
sudo ./svc.sh install
sudo ./svc.sh start
```

### 3. Repository Environment Setup

Create a `production` environment in GitHub:
- Settings → Environments → New environment
- Name: `production`  
- Add protection rules (optional):
  - Required reviewers
  - Deployment branches restriction

## 🎯 GitOps Workflow

### Normal Development Flow:
1. **Create feature branch** with changes
2. **Open Pull Request** → Triggers `validate.yml`
3. **Review validation results** in PR checks
4. **Merge PR** → Triggers `deploy.yml`
5. **Monitor deployment** via GitHub Actions + Discord
6. **Verify changes** in infrastructure

### Emergency Operations:
1. **Go to Actions tab**
2. **Select "Manual Operations" workflow**  
3. **Click "Run workflow"**
4. **Choose operation and parameters**
5. **Monitor execution**

## 📊 Monitoring Integration

The workflows integrate with your existing monitoring:

**Health Checks:**
- Pre/post deployment cluster validation
- Service status verification
- Monitoring stack health confirmation

**Notifications:**
- Discord alerts on deployment success/failure
- Deployment summaries in GitHub
- Failed deployment troubleshooting info

## 🛡️ Security Features

**Secrets Management:**
- All sensitive data in GitHub secrets
- Vault passwords handled securely
- SSH keys properly protected

**Validation:**
- Secret scanning in PRs
- Ansible lint validation
- Kubernetes manifest security checks

**Access Control:**
- Production environment protection
- Self-hosted runner network isolation
- Audit trail in GitHub Actions

## 🔧 Customization

**Add New Playbooks:**
1. Update `deploy.yml` workflow inputs
2. Add playbook to choices list
3. Test via manual dispatch

**Add New Operations:**
1. Update `manual-operations.yml` inputs
2. Add operation logic in workflow
3. Test with dry-run mode

**Modify Validation:**
1. Update `validate.yml` checks
2. Add new linting rules
3. Customize security scans

## 📚 Troubleshooting

**Common Issues:**

**Runner connectivity:**
```bash
# Test from runner host
ssh debian@kube501 "echo 'Connection OK'"
ansible all -i inventories/production/hosts.ini -m ping
```

**Vault password issues:**
```bash
# Test vault decryption
ansible-vault view group_vars/all/vault.yml
```

**Deployment failures:**
- Check runner logs in Actions tab  
- Verify network connectivity
- Confirm SSH key access
- Check ansible inventory syntax

## 🎉 Benefits

This GitOps setup provides:

✅ **Automated validation** of all infrastructure changes  
✅ **Consistent deployment** process across all environments  
✅ **Audit trail** of all infrastructure modifications  
✅ **Easy rollbacks** and emergency operations  
✅ **Integration** with existing monitoring and notifications  
✅ **Security scanning** and best practices enforcement  
✅ **Self-service operations** for common tasks  

Your infrastructure is now managed as code with professional CI/CD! 🚀