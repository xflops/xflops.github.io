---
layout: docs
title: Getting Started with Flame
description: Learn how to install and configure Flame for your first distributed AI workload deployment.
---

# Getting Started with Flame

This guide will walk you through installing and configuring Flame for your first distributed AI workload deployment. By the end of this guide, you'll have a working Flame installation and understand the basic concepts.

## Prerequisites

Before you begin, ensure you have the following:

- **Kubernetes Cluster**: A working Kubernetes cluster (version 1.20 or later)
- **kubectl**: Configured to communicate with your cluster
- **Helm**: Version 3.0 or later (optional, for Helm-based installation)
- **Docker**: For building and running containers locally (optional)
- **Storage**: Persistent storage provisioner configured in your cluster

### Supported Kubernetes Distributions

- **Cloud Providers**: AWS EKS, Google GKE, Azure AKS
- **On-Premises**: OpenShift, Rancher, VMware Tanzu
- **Local Development**: Minikube, Docker Desktop, Kind

## Installation Methods

Flame can be installed using several methods. Choose the one that best fits your environment:

### Method 1: Helm Installation (Recommended)

Helm provides the easiest way to install and manage Flame:

```bash
# Add the XFLOPS Helm repository
helm repo add xflops https://charts.xflops.cn
helm repo update

# Install Flame
helm install flame xflops/flame \
  --namespace flame-system \
  --create-namespace \
  --set global.imageRegistry=ghcr.io/xflops
```

### Method 2: Direct Kubernetes Manifests

For environments where Helm is not available:

```bash
# Create namespace
kubectl create namespace flame-system

# Apply the core components
kubectl apply -f https://raw.githubusercontent.com/xflops/flame/main/deploy/manifests/core.yaml

# Apply the operator
kubectl apply -f https://raw.githubusercontent.com/xflops/flame/main/deploy/manifests/operator.yaml
```

### Method 3: Operator Installation

Using the Flame Operator for advanced management:

```bash
# Install the Flame Operator
kubectl apply -f https://raw.githubusercontent.com/xflops/flame/main/deploy/manifests/operator.yaml

# Wait for the operator to be ready
kubectl wait --for=condition=ready pod -l app=flame-operator -n flame-system
```

## Verification

After installation, verify that all components are running correctly:

```bash
# Check all pods in the flame-system namespace
kubectl get pods -n flame-system

# Check services
kubectl get services -n flame-system

# Check custom resources
kubectl get crd | grep flame
```

You should see output similar to:

```
NAME                                    READY   STATUS    RESTARTS   AGE
flame-operator-7d8f9c8b9-abc12         1/1     Running   0          2m
flame-core-6d8f9c8b9-def34             1/1     Running   0          2m
flame-api-server-8d8f9c8b9-ghi56       1/1     Running   0          2m

NAME                    TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
flame-api-server        ClusterIP   10.96.123.45    <none>        8080/TCP  2m
flame-core              ClusterIP   10.96.123.46    <none>        9090/TCP  2m

NAME
flameworkloads.flame.xflops.cn
flameagents.flame.xflops.cn
flameclusters.flame.xflops.cn
```

## Basic Configuration

### 1. Configure Resource Limits

Set appropriate resource limits for your environment:

```yaml
# flame-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: flame-config
  namespace: flame-system
data:
  config.yaml: |
    resources:
      limits:
        cpu: "4"
        memory: "8Gi"
      requests:
        cpu: "1"
        memory: "2Gi"
    
    scheduling:
      maxConcurrentWorkloads: 10
      defaultTimeout: "1h"
```

Apply the configuration:

```bash
kubectl apply -f flame-config.yaml
```

### 2. Configure Storage

Set up persistent storage for your workloads:

```yaml
# storage-config.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: flame-storage
  namespace: flame-system
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  storageClassName: your-storage-class
```

### 3. Configure Authentication

Set up authentication for the Flame API:

```yaml
# auth-config.yaml
apiVersion: v1
kind: Secret
metadata:
  name: flame-auth
  namespace: flame-system
type: Opaque
data:
  api-key: <base64-encoded-api-key>
  admin-token: <base64-encoded-admin-token>
```

## Your First Workload

Now let's deploy your first AI workload with Flame:

### 1. Create a Simple Workload

```yaml
# first-workload.yaml
apiVersion: flame.xflops.cn/v1alpha1
kind: FlameWorkload
metadata:
  name: hello-flame
  namespace: default
spec:
  type: Training
  replicas: 2
  
  template:
    spec:
      containers:
      - name: training
        image: pytorch/pytorch:latest
        command: ["python", "-c"]
        args:
        - |
          import torch
          import torch.distributed as dist
          
          # Initialize distributed training
          dist.init_process_group(backend='nccl')
          
          print(f"Hello from Flame! Rank: {dist.get_rank()}")
          print(f"World size: {dist.get_world_size()}")
          
          # Clean up
          dist.destroy_process_group()
        
        resources:
          requests:
            nvidia.com/gpu: 1
            memory: "4Gi"
            cpu: "2"
          limits:
            nvidia.com/gpu: 1
            memory: "8Gi"
            cpu: "4"
```

### 2. Deploy the Workload

```bash
kubectl apply -f first-workload.yaml
```

### 3. Monitor the Workload

```bash
# Check workload status
kubectl get flameworkloads

# Check pods
kubectl get pods -l flame.xflops.cn/workload=hello-flame

# View logs
kubectl logs -l flame.xflops.cn/workload=hello-flame -c training
```

## Understanding the Components

### Flame Core

The central orchestrator that manages all workloads and resources:

- **Scheduler**: Distributes workloads across available nodes
- **Resource Manager**: Tracks and allocates cluster resources
- **Workload Controller**: Manages the lifecycle of AI workloads

### Flame Agents

Lightweight agents that run on each node:

- **Resource Monitoring**: Tracks local resource usage
- **Workload Execution**: Runs AI workloads and manages containers
- **Health Reporting**: Reports node status back to the core

### Flame API Server

Provides a RESTful API for managing Flame resources:

- **Workload Management**: Create, update, and delete workloads
- **Cluster Information**: Query cluster status and resources
- **Authentication**: Secure access to the Flame API

## Next Steps

Congratulations! You now have a working Flame installation. Here's what you can explore next:

1. **Use Cases**: Check out our [Use Cases](/docs/use-cases/) section for real-world examples
2. **User Guide**: Dive deeper into [configuration and best practices](/docs/user-guide/)
3. **API Reference**: Learn about the [Flame API](/docs/api-reference/) for programmatic access
4. **Ecosystem**: Explore [integrations and extensions](/docs/ecosystem/)

## Troubleshooting

### Common Issues

**Pods stuck in Pending state:**
```bash
# Check events
kubectl describe pod <pod-name>

# Check resource availability
kubectl describe node <node-name>
```

**Workload not starting:**
```bash
# Check workload status
kubectl describe flameworkload <workload-name>

# Check operator logs
kubectl logs -l app=flame-operator -n flame-system
```

**Storage issues:**
```bash
# Check PVC status
kubectl get pvc

# Check storage class
kubectl get storageclass
```

### Getting Help

If you encounter issues not covered here:

- Check the [Flame GitHub repository](https://github.com/xflops/flame) for known issues
- Join our [Slack community](http://xflops.slack.com) for real-time support
- Open an issue on GitHub with detailed information about your problem

---

*Ready to explore more? Check out our [Use Cases](/docs/use-cases/) section to see what you can build with Flame!*
