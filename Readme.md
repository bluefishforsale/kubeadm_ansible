# Kubernetes HA Cluster with kubeadm

Ansible automation to deploy a highly-available Kubernetes cluster using kubeadm, HAProxy, Keepalived, and Flannel CNI on Proxmox VMs.

## Project Structure

```
kubeadm_ansible/
├── ansible.cfg
├── site.yml                          # Master playbook
├── group_vars/
│   └── all/
│       └── vault.yml                 # Encrypted secrets
├── inventories/
│   └── production/
│       ├── hosts.ini
│       └── group_vars/
│           ├── all.yml
│           ├── k8s.yml
│           ├── k8s_controller.yml
│           └── k8s_worker.yml
├── playbooks/
│   ├── create_vms.yml
│   ├── setup_cluster.yml
│   └── reset_cluster.yml
├── roles/
│   ├── proxmox_vm/
│   ├── kubernetes_repo/
│   ├── kubernetes_install/
│   ├── containerd/
│   ├── haproxy_keepalived/
│   ├── kubeadm_init/
│   ├── kubeadm_join/
│   ├── nvidia_gpu/
│   └── metrics_server/
├── k8s-health-monitoring/            # Health monitoring & GitOps
│   ├── monitoring/
│   ├── playbooks/
│   └── scripts/
└── .github/workflows/                # GitOps CI/CD workflows
    ├── validate.yml
    ├── deploy.yml
    └── manual-operations.yml
```

## Infrastructure Created

**VMs:** Creates Debian-based VMs on Proxmox (cloned from template ID 9999)

- **Control plane:** 3 nodes (kube501-503) - 4 cores, 2GB RAM each
- **Workers:** 1-3 nodes (kube511-513) - 8 cores, 8GB RAM each (optional GPU passthrough)

**Network Configuration:**

- **VM subnet:** 192.168.1.0/24
- **Kubernetes VIP:** 192.168.1.99 (HAProxy + Keepalived)
- **Pod CIDR:** 10.244.0.0/16 (Flannel)
- **Service CIDR:** 10.96.0.0/12
- **Kubernetes version:** 1.32.0

## Requirements

- Ansible 2.9+
- SSH access to Proxmox host
- Template VM with ID 9999 (Debian-based)
- Hostnames resolvable: `kube50[1-3].home`, `kube51[1-3].home`

## Critical Configuration Requirements

**Cgroup Driver:**
Kubernetes (kubelet) and the container runtime (containerd) **must** use the same cgroup driver. This project configures both to use `systemd`.

- **Containerd:** `SystemdCgroup = true` in `/etc/containerd/config.toml`
- **Kubelet:** `cgroupDriver: systemd` in `/var/lib/kubelet/config.yaml`

*Note: Mismatched cgroup drivers will cause the kubelet to fail startup and the node will not become Ready.*

## Quick Start

1. **Setup direnv and vault:**

```bash
direnv allow .

# Edit vault (group_vars/all/vault.yml)
# Required variables:
#   - kubernetes_version: "1.32.0-1.1"
#   - vip: "192.168.1.99"
#   - pod_network_cidr: "10.244.0.0/16"
#   - pod_services_cidr: "10.96.0.0/12"
#   - sandbox_image: "registry.k8s.io/pause:3.10"
#   - domain_suffixes: ["", ".home", ".local"]
#   - keepalived_auth_pass: "<secure-random-string>"

ansible-vault edit group_vars/all/vault.yml
```

2. **Edit inventory** - Update `inventories/production/hosts.ini`

3. **Validate:**

```bash
ansible-playbook site.yml --syntax-check
```

4. **Deploy cluster:**

```bash
# Full deployment
ansible-playbook site.yml

# Or use tags for specific stages
ansible-playbook site.yml --tags vms
ansible-playbook site.yml --tags k8s
ansible-playbook site.yml --tags ha
ansible-playbook site.yml --tags init
ansible-playbook site.yml --tags join
ansible-playbook site.yml --tags gpu
ansible-playbook site.yml --tags metrics
```

5. **Alternative: Use individual playbooks:**

```bash
ansible-playbook playbooks/create_vms.yml
ansible-playbook playbooks/setup_cluster.yml
```

---

## 🚀 GitOps CI/CD Workflow (NEW)

This repository now includes automated GitOps workflows for infrastructure management via GitHub Actions.

### ✨ Features

- **🔍 Automated PR validation** - Syntax checking, linting, security scanning
- **🚀 Production deployment** - Automatic deployment on merge to main
- **🛠️ Manual operations** - Health checks, service restarts, cluster maintenance
- **📊 Monitoring integration** - Deployment verification and health monitoring
- **🔔 Discord notifications** - Real-time deployment status alerts

### 🎯 Quick GitOps Setup

**1. Run the setup script:**
```bash
bash setup-gitops.sh
```

**2. Set up GitHub runner:**
```bash
# On your management host (node005 or dedicated VM)
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64.tar.gz -L https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64.tar.gz
tar xzf ./actions-runner-linux-x64.tar.gz
./config.sh --url https://github.com/bluefishforsale/kubeadm_ansible --token YOUR_TOKEN
sudo ./svc.sh install && sudo ./svc.sh start
```

**3. Configure GitHub secrets:**
- `ANSIBLE_SSH_PRIVATE_KEY` - SSH key for cluster access
- `ANSIBLE_VAULT_PASSWORD` - Ansible vault password  
- `DISCORD_WEBHOOK` - Discord webhook URL (optional)

### 🔄 GitOps Workflow

**Development Process:**
1. Create feature branch → Make changes
2. Open Pull Request → Automated validation runs
3. Review & merge → Automatic deployment to production
4. Monitor deployment → Discord notifications + verification

**Emergency Operations:**
- Go to **Actions** tab → **Manual Operations** → **Run workflow**
- Available operations: health-check, restart-services, cluster-status, rollback

### 📋 Available Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| **validate.yml** | Pull Request | Ansible lint, K8s validation, security scan |
| **deploy.yml** | Push to main | Production deployment with verification |
| **manual-operations.yml** | Manual dispatch | Health checks, maintenance, emergency ops |

See [.github/workflows/README.md](.github/workflows/README.md) for detailed documentation.

---

## Manual Deployment (Legacy)

### Cluster Reset

```bash
ansible-playbook playbooks/reset_cluster.yml
```

### Debugging Commands

**Check cluster status:**

```bash
ansible k8s -a 'uptime'
```

**Container runtime:**

```bash
watch sudo crictl ps -a
watch sudo crictl logs -f containerid
```

**Kubelet logs:**

```bash
sudo journalctl -fu kubelet
```

**Etcd logs:**

```bash
sudo kubectl logs --kubeconfig /etc/kubernetes/admin.conf -n kube-system etcd-kube501
```

**API health:**

```bash
watch sudo curl -s --cacert /etc/kubernetes/pki/ca.crt --cert /etc/kubernetes/pki/apiserver-kubelet-client.crt --key /etc/kubernetes/pki/apiserver-kubelet-client.key https://192.168.1.99:6443/healthz
```

**Etcd health:**

```bash
watch curl -s http://127.0.0.1:2381/health
```

**API server binding:**

```bash
sudo ss -plant | grep 6443 | grep LIST
```

**Etcd member list:**

```bash
kubectl exec -n kube-system -it etcd-kube501 -- etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list
```

---

## 🏥 Kubernetes Health Monitoring

Comprehensive monitoring stack for cluster health management:

- **kube-state-metrics** - Kubernetes object monitoring
- **cAdvisor fixes** - Container metrics collection  
- **Automated health checks** - Proactive monitoring every 30 minutes
- **Prometheus integration** - Enhanced metrics collection
- **Automated recovery** - Service restart capabilities

Deploy monitoring stack:
```bash
# Via GitOps (recommended)
git checkout feature/k8s-health-monitoring-* 
# Open PR → Auto-deployment on merge

# Via Ansible (manual)
ansible-playbook k8s-health-monitoring/playbooks/deploy-monitoring.yml
```

---

**🎉 Your infrastructure is now fully GitOps enabled with professional CI/CD workflows!**