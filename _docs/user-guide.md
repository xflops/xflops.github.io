---
layout: docs
title: User Guide
description: Comprehensive guide for using Flame effectively, including configuration, deployment strategies, and best practices.
---

# User Guide

This comprehensive guide covers everything you need to know to use Flame effectively in production environments. From basic configuration to advanced deployment strategies, you'll find practical guidance to help you get the most out of Flame.

## Table of Contents

1. [Configuration Management](#configuration-management)
2. [Deployment Strategies](#deployment-strategies)
3. [Resource Management](#resource-management)
4. [Monitoring and Observability](#monitoring-and-observability)
5. [Security Best Practices](#security-best-practices)
6. [Performance Optimization](#performance-optimization)
7. [Troubleshooting](#troubleshooting)

## Configuration Management

### Environment Configuration

Flame can be configured through various methods depending on your deployment environment:

#### 1. ConfigMap-based Configuration

```yaml
# flame-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: flame-config
  namespace: flame-system
data:
  config.yaml: |
    # Global settings
    global:
      imageRegistry: "ghcr.io/xflops"
      imagePullPolicy: "IfNotPresent"
      imagePullSecrets: []
    
    # Resource management
    resources:
      limits:
        cpu: "8"
        memory: "16Gi"
      requests:
        cpu: "2"
        memory: "4Gi"
    
    # Scheduling configuration
    scheduling:
      maxConcurrentWorkloads: 20
      defaultTimeout: "2h"
      maxRetries: 3
      backoffLimit: 5
    
    # Storage configuration
    storage:
      defaultStorageClass: "fast-ssd"
      persistentVolumeSize: "100Gi"
      accessMode: "ReadWriteMany"
    
    # Networking
    networking:
      serviceType: "ClusterIP"
      ingressEnabled: false
      loadBalancerIP: ""
    
    # Security
    security:
      enableRBAC: true
      enableNetworkPolicies: true
      podSecurityPolicies: true
```

#### 2. Helm Values Configuration

```yaml
# values.yaml
global:
  imageRegistry: "ghcr.io/xflops"
  imagePullPolicy: "IfNotPresent"

flame:
  core:
    replicaCount: 3
    resources:
      limits:
        cpu: "4"
        memory: "8Gi"
      requests:
        cpu: "1"
        memory: "2Gi"
    
    config:
      maxConcurrentWorkloads: 20
      defaultTimeout: "2h"
      enableMetrics: true
      enableTracing: true
  
  agent:
    replicaCount: 5
    resources:
      limits:
        cpu: "2"
        memory: "4Gi"
      requests:
        cpu: "0.5"
        memory: "1Gi"
    
    config:
      heartbeatInterval: "30s"
      resourceUpdateInterval: "1m"
      maxConcurrentWorkloads: 10
  
  apiServer:
    replicaCount: 2
    resources:
      limits:
        cpu: "2"
        memory: "4Gi"
      requests:
        cpu: "0.5"
        memory: "1Gi"
    
    config:
      enableSwagger: true
      corsEnabled: true
      rateLimit:
        enabled: true
        requestsPerSecond: 100
```

### Workload Configuration

#### Basic Workload Definition

```yaml
apiVersion: flame.xflops.cn/v1alpha1
kind: FlameWorkload
metadata:
  name: example-workload
  namespace: default
  labels:
    app: example
    environment: production
  annotations:
    flame.xflops.cn/priority: "high"
    flame.xflops.cn/auto-scaling: "true"
spec:
  type: Training  # Training, Inference, or Hybrid
  replicas: 4
  
  # Scheduling preferences
  scheduling:
    nodeSelector:
      node-type: gpu
    tolerations:
    - key: "nvidia.com/gpu"
      operator: "Exists"
      effect: "NoSchedule"
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: "nvidia.com/gpu"
              operator: "Exists"
  
  # Template for pods
  template:
    metadata:
      labels:
        app: example
        workload: example-workload
    spec:
      containers:
      - name: main
        image: your-image:latest
        command: ["python", "train.py"]
        args:
        - "--epochs=100"
        - "--batch-size=64"
        - "--learning-rate=0.001"
        
        env:
        - name: FLAME_WORKLOAD_ID
          value: "$(FLAME_WORKLOAD_ID)"
        - name: FLAME_RANK
          value: "$(FLAME_RANK)"
        - name: FLAME_WORLD_SIZE
          value: "$(FLAME_WORLD_SIZE)"
        
        resources:
          requests:
            nvidia.com/gpu: 1
            memory: "8Gi"
            cpu: "4"
          limits:
            nvidia.com/gpu: 1
            memory: "16Gi"
            cpu: "8"
        
        ports:
        - containerPort: 8080
          name: http
        - containerPort: 9090
          name: metrics
        
        volumeMounts:
        - name: data
          mountPath: /data
        - name: models
          mountPath: /models
        - name: logs
          mountPath: /logs
        
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
        
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
      
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: data-pvc
      - name: models
        persistentVolumeClaim:
          claimName: models-pvc
      - name: logs
        emptyDir: {}
      
      restartPolicy: "Never"
      terminationGracePeriodSeconds: 60
```

## Deployment Strategies

### 1. Rolling Update Strategy

For workloads that need zero-downtime updates:

```yaml
apiVersion: flame.xflops.cn/v1alpha1
kind: FlameWorkload
metadata:
  name: rolling-update-workload
spec:
  type: Inference
  replicas: 5
  
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  
  template:
    spec:
      containers:
      - name: inference
        image: inference-model:v2.0
        # ... other configuration
```

### 2. Blue-Green Deployment

For critical workloads requiring safe rollbacks:

```yaml
apiVersion: flame.xflops.cn/v1alpha1
kind: FlameWorkload
metadata:
  name: blue-green-workload
spec:
  type: Inference
  replicas: 3
  
  strategy:
    type: BlueGreen
    blueGreen:
      autoPromotion: false
      promotionTimeout: "10m"
      scaleDownDelay: "5m"
  
  template:
    spec:
      containers:
      - name: inference
        image: inference-model:v2.0
        # ... other configuration
```

### 3. Canary Deployment

For gradual rollout and testing:

```yaml
apiVersion: flame.xflops.cn/v1alpha1
kind: FlameWorkload
metadata:
  name: canary-workload
spec:
  type: Inference
  replicas: 10
  
  strategy:
    type: Canary
    canary:
      initialReplicas: 2
      maxReplicas: 8
      stepWeight: 25
      stepInterval: "5m"
      autoPromotion: true
  
  template:
    spec:
      containers:
      - name: inference
        image: inference-model:v2.0
        # ... other configuration
```

## Resource Management

### Resource Quotas and Limits

```yaml
# resource-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: flame-quota
  namespace: flame-system
spec:
  hard:
    requests.cpu: "100"
    requests.memory: "200Gi"
    requests.nvidia.com/gpu: "50"
    limits.cpu: "200"
    limits.memory: "400Gi"
    limits.nvidia.com/gpu: "100"
    persistentvolumeclaims: "100"
    services: "50"
    pods: "200"
```

### Priority Classes

```yaml
# priority-classes.yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: flame-high-priority
value: 1000000
globalDefault: false
description: "High priority for critical Flame workloads"

---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: flame-normal-priority
value: 100000
globalDefault: true
description: "Normal priority for Flame workloads"

---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: flame-low-priority
value: 10000
globalDefault: false
description: "Low priority for batch Flame workloads"
```

### GPU Management

```yaml
# gpu-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gpu-config
  namespace: flame-system
data:
  gpu-config.yaml: |
    gpu:
      # GPU sharing configuration
      sharing:
        enabled: true
        maxWorkloadsPerGPU: 4
        memoryFraction: 0.25
      
      # GPU monitoring
      monitoring:
        enabled: true
        metrics:
          - utilization
          - memory_used
          - temperature
          - power_draw
      
      # GPU scheduling
      scheduling:
        strategy: "binpack"  # binpack, spread, or custom
        preemption: true
        gangScheduling: true
```

## Monitoring and Observability

### Metrics Collection

Flame provides comprehensive metrics for monitoring workload performance:

```yaml
# monitoring-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: monitoring-config
  namespace: flame-system
data:
  monitoring.yaml: |
    metrics:
      enabled: true
      port: 9090
      path: /metrics
      
      # Custom metrics
      custom:
        - name: workload_duration
          type: histogram
          buckets: [1, 5, 10, 30, 60, 300, 600, 1800, 3600]
        
        - name: gpu_utilization
          type: gauge
          labels: ["node", "gpu_id", "workload"]
        
        - name: resource_allocation
          type: gauge
          labels: ["resource_type", "node", "workload"]
    
    # Prometheus integration
    prometheus:
      enabled: true
      scrapeInterval: "15s"
      retention: "30d"
    
    # Grafana dashboards
    grafana:
      enabled: true
      dashboards:
        - name: "Flame Overview"
          url: "https://grafana.com/dashboards/12345"
        - name: "Workload Performance"
          url: "https://grafana.com/dashboards/12346"
```

### Logging Configuration

```yaml
# logging-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: logging-config
  namespace: flame-system
data:
  logging.yaml: |
    logging:
      level: "info"  # debug, info, warn, error
      format: "json"  # json, text
      
      # Output configuration
      outputs:
        - type: "stdout"
          enabled: true
        
        - type: "file"
          enabled: true
          path: "/var/log/flame"
          maxSize: "100MB"
          maxBackups: 5
          maxAge: "30d"
        
        - type: "fluentd"
          enabled: false
          endpoint: "fluentd:24224"
      
      # Structured logging
      structured:
        enabled: true
        fields:
          - name: "workload_id"
            value: "$(FLAME_WORKLOAD_ID)"
          - name: "node_name"
            value: "$(NODE_NAME)"
          - name: "pod_name"
            value: "$(POD_NAME)"
```

## Security Best Practices

### RBAC Configuration

```yaml
# rbac-config.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: flame-admin
rules:
- apiGroups: ["flame.xflops.cn"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: flame-user
rules:
- apiGroups: ["flame.xflops.cn"]
  resources: ["flameworkloads", "flameagents"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: flame-admin-binding
subjects:
- kind: ServiceAccount
  name: flame-admin
  namespace: flame-system
roleRef:
  kind: ClusterRole
  name: flame-admin
  apiGroup: rbac.authorization.k8s.io
```

### Network Policies

```yaml
# network-policies.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: flame-network-policy
  namespace: flame-system
spec:
  podSelector:
    matchLabels:
      app: flame
  
  policyTypes:
  - Ingress
  - Egress
  
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: flame-system
    ports:
    - protocol: TCP
      port: 8080
    - protocol: TCP
      port: 9090
  
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 53
  - to: []
    ports:
    - protocol: TCP
      port: 443
    - protocol: TCP
      port: 80
```

## Performance Optimization

### Workload Optimization

1. **Resource Allocation**
   - Use resource requests and limits appropriately
   - Monitor actual resource usage and adjust
   - Implement horizontal pod autoscaling

2. **Container Optimization**
   - Use multi-stage Docker builds
   - Optimize base images
   - Implement proper health checks

3. **Storage Optimization**
   - Use appropriate storage classes
   - Implement data locality
   - Use caching strategies

### Cluster Optimization

1. **Node Management**
   - Use node pools for different workload types
   - Implement proper taints and tolerations
   - Use node affinity for workload placement

2. **Network Optimization**
   - Use appropriate CNI plugins
   - Implement network policies
   - Optimize inter-node communication

## Troubleshooting

### Common Issues and Solutions

#### 1. Workload Stuck in Pending

```bash
# Check workload status
kubectl describe flameworkload <workload-name>

# Check pod events
kubectl describe pod <pod-name>

# Check resource availability
kubectl describe node <node-name>

# Check quota limits
kubectl describe resourcequota -n <namespace>
```

#### 2. GPU Issues

```bash
# Check GPU availability
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, gpu: .status.allocatable."nvidia.com/gpu"}'

# Check GPU driver status
kubectl get pods -n kube-system -l app=nvidia-device-plugin

# Check GPU metrics
kubectl top nodes
```

#### 3. Performance Issues

```bash
# Check resource usage
kubectl top pods -l app=flame

# Check metrics
kubectl port-forward svc/flame-metrics 9090:9090

# Check logs
kubectl logs -l app=flame -f
```

### Debugging Tools

1. **Flame CLI**
   ```bash
   # Install Flame CLI
   curl -L https://github.com/xflops/flame/releases/latest/download/flame-cli-linux-amd64 -o flame
   chmod +x flame
   sudo mv flame /usr/local/bin/
   
   # Debug workload
   flame debug workload <workload-name>
   
   # Check cluster status
   flame status
   ```

2. **Kubernetes Debug Tools**
   ```bash
   # Debug pod
   kubectl debug <pod-name> -it --image=busybox
   
   # Check events
   kubectl get events --sort-by=.metadata.creationTimestamp
   
   # Check resource usage
   kubectl top nodes
   kubectl top pods
   ```

## Next Steps

This user guide covers the essential aspects of using Flame in production. For more advanced topics:

- **API Reference**: Complete API documentation for programmatic access
- **Use Cases**: Real-world examples and implementation patterns
- **Ecosystem**: Integrations and extensions for Flame

---

*Need help with a specific configuration or facing an issue? Check out our [troubleshooting section](#troubleshooting) or join our [community](http://xflops.slack.com) for support.*
