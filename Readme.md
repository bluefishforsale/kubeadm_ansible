# Kubernetes HA Cluster with kubeadm

Ansible automation to deploy a highly-available Kubernetes cluster using kubeadm, HAProxy, Keepalived, and Flannel CNI on Proxmox VMs.

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

**Control machine:**

- Ansible 2.9+
- SSH access to Proxmox host

**Proxmox:**

- Template VM with ID 9999 (Debian-based)
- SSH keys at `https://github.com/bluefishforsale.keys`

**DNS:**

- Hostnames resolvable: `kube50[1-3].home`, `kube51[1-3].home`

## Quick Start

1. **Setup direnv and vault:**

```bash
# Allow direnv to load environment variables
direnv allow .

# Edit vault_secrets.yaml with your variables (currently unencrypted)
# Then encrypt it:
ansible-vault encrypt vault_secrets.yaml

# To edit encrypted vault:
ansible-vault edit vault_secrets.yaml

# To decrypt temporarily for viewing:
ansible-vault decrypt vault_secrets.yaml --output vault_secrets_plain.yaml
```

2. **Edit `inventory.ini`** - Update IPs and hostnames

3. **Validate playbooks:**

```bash
ansible-playbook --extra-vars @vault_secrets.yaml --syntax-check 01_kube_apt_repo.yaml
ansible-playbook --extra-vars @vault_secrets.yaml --syntax-check 02_install_kubernetes.yaml
ansible-playbook --extra-vars @vault_secrets.yaml --syntax-check 03_containerd_and_networking.yaml
ansible-playbook --extra-vars @vault_secrets.yaml --syntax-check 04_configure_ha_proxy_keepalived.yaml
ansible-playbook --extra-vars @vault_secrets.yaml --syntax-check 05_initialize_master.yaml
ansible-playbook --extra-vars @vault_secrets.yaml --syntax-check 06_join_other_nodes.yaml
ansible-playbook --extra-vars @vault_secrets.yaml --syntax-check 07_configure_gpu_node.yaml
```

4. **Dry-run (optional):**

```bash
ansible-playbook --extra-vars @vault_secrets.yaml 01_kube_apt_repo.yaml --check
ansible-playbook --extra-vars @vault_secrets.yaml 02_install_kubernetes.yaml --check
ansible-playbook --extra-vars @vault_secrets.yaml 03_containerd_and_networking.yaml --check
ansible-playbook --extra-vars @vault_secrets.yaml 04_configure_ha_proxy_keepalived.yaml --check
ansible-playbook --extra-vars @vault_secrets.yaml 05_initialize_master.yaml --check
```

5. **Deploy cluster:**

```bash
ansible-playbook --extra-vars @vault_secrets.yaml 00_create_vms.yaml
ansible-playbook --extra-vars @vault_secrets.yaml 01_kube_apt_repo.yaml
ansible-playbook --extra-vars @vault_secrets.yaml 02_install_kubernetes.yaml
ansible-playbook --extra-vars @vault_secrets.yaml 03_containerd_and_networking.yaml
ansible-playbook --extra-vars @vault_secrets.yaml 04_configure_ha_proxy_keepalived.yaml
ansible-playbook --extra-vars @vault_secrets.yaml 05_initialize_master.yaml
ansible-playbook --extra-vars @vault_secrets.yaml 06_join_other_nodes.yaml
ansible-playbook --extra-vars @vault_secrets.yaml 07_configure_gpu_node.yaml
ansible-playbook --extra-vars @vault_secrets.yaml 20_metrics_server_certs_secrets.yaml
```

## Cluster Reset

```bash
ansible -i inventory.ini k8s -b -m shell a 'sudo crictl stopp $(sudo crictl ps -a -q)'
ansible -i inventory.ini k8s -b -m shell a 'sudo crictl rmp $(sudo crictl ps -a -q)'
ansible -i inventory.ini k8s -b -m shell a 'sudo kill -9 $(pgrep container* )'
ansible -i inventory.ini k8s -b -m shell -a 'sudo kill -9 $(pgrep kube*)'
ansible -i inventory.ini k8s -b -a 'sudo systemctl stop kubelet containerd'
ansible -i inventory.ini k8s -b -a 'sudo ip link delete flannel.1'
ansible -i inventory.ini k8s -b -a 'sudo rm -rf /etc/cni/net.d /var/lib/cni /var/lib/etcd /var/lib/kubelet /etc/kubernetes /var/lib/containerd'
ansible -i inventory.ini k8s -b -a 'sudo kubeadm reset --force'
ansible -i inventory.ini k8s -b -a 'sudo ipvsadm --clear'
```

## Debugging Commands

**Check cluster status:**

```bash
ansible -i inventory.ini k8s -b -a 'uptime'
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
