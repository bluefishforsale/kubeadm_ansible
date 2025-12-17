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
└── roles/
    ├── proxmox_vm/
    ├── kubernetes_repo/
    ├── kubernetes_install/
    ├── containerd/
    ├── haproxy_keepalived/
    ├── kubeadm_init/
    ├── kubeadm_join/
    ├── nvidia_gpu/
    └── metrics_server/
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

## Cluster Reset

```bash
ansible-playbook playbooks/reset_cluster.yml
```

## Debugging Commands

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
