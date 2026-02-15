#!/bin/bash
# Fix cAdvisor on Kubernetes nodes
# Run this script on each cluster node (kube501, kube502, kube503, kube511)

set -e

CADVISOR_VERSION="v0.49.1"
CADVISOR_URL="https://github.com/google/cadvisor/releases/download/${CADVISOR_VERSION}/cadvisor-${CADVISOR_VERSION}-linux-amd64"

echo "🐳 Fixing cAdvisor on $(hostname)"
echo "================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root (use sudo)"
   exit 1
fi

# Stop existing cAdvisor if running
if systemctl is-active --quiet cadvisor; then
    echo "🛑 Stopping existing cAdvisor service..."
    systemctl stop cadvisor
fi

# Download cAdvisor binary
echo "📥 Downloading cAdvisor ${CADVISOR_VERSION}..."
if wget -O /usr/local/bin/cadvisor "$CADVISOR_URL"; then
    chmod +x /usr/local/bin/cadvisor
    echo "✅ cAdvisor binary downloaded and installed"
else
    echo "❌ Failed to download cAdvisor"
    exit 1
fi

# Create systemd service
echo "⚙️  Creating systemd service..."
cat > /etc/systemd/system/cadvisor.service << 'EOF'
[Unit]
Description=cAdvisor
Documentation=https://github.com/google/cadvisor
After=network.target docker.service containerd.service
Wants=docker.service containerd.service

[Service]
Type=simple
ExecStart=/usr/local/bin/cadvisor \
    --listen_ip="0.0.0.0" \
    --port=8080 \
    --housekeeping_interval=30s \
    --max_housekeeping_interval=35s \
    --event_storage_event_limit=default=0 \
    --event_storage_age_limit=default=0 \
    --disable_metrics=accelerator,cpu_topology,disk,memory_numa,tcp,udp,percpu,sched,process,hugetlb,referenced_memory,resctrl,cpuset,advtcp,memory_numa \
    --docker_only \
    --store_container_labels=false \
    --whitelisted_container_labels=io.kubernetes.container.name,io.kubernetes.pod.name,io.kubernetes.pod.namespace
Restart=always
RestartSec=10
User=root

# Resource limits
MemoryLimit=200M
CPUQuota=20%

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start cAdvisor
echo "🔄 Reloading systemd and starting cAdvisor..."
systemctl daemon-reload
systemctl enable cadvisor
systemctl start cadvisor

# Wait for service to start
sleep 5

# Check if cAdvisor is running
if systemctl is-active --quiet cadvisor; then
    echo "✅ cAdvisor is running successfully"
    
    # Test the metrics endpoint
    echo "🔍 Testing metrics endpoint..."
    if curl -s http://localhost:8080/metrics | head -5 > /dev/null; then
        echo "✅ cAdvisor metrics endpoint is responding"
    else
        echo "⚠️  cAdvisor metrics endpoint test failed"
    fi
    
    echo ""
    echo "📊 Service Status:"
    systemctl status cadvisor --no-pager -l
    
else
    echo "❌ cAdvisor failed to start"
    echo "📋 Service logs:"
    journalctl -u cadvisor --no-pager -l
    exit 1
fi

echo ""
echo "🎯 cAdvisor Fix Complete on $(hostname)!"
echo "📊 Metrics available at: http://$(hostname):8080/metrics"