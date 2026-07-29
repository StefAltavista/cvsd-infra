# CVSD Infrastructure on Amazon EKS

Infrastructure-as-code and Kubernetes deployment repository for the CVSD voting application. This repository provisions an Amazon EKS cluster, deploys the five application components, exposes the public frontends through ingress-nginx, creates Route 53 records, and obtains HTTPS certificates from Let's Encrypt.

The project is split across two repositories:

| Repository | Responsibility |
| --- | --- |
| [`cvsd-app`](https://github.com/StefAltavista/cvsd-app) | Source code and Docker builds for `vote`, `result`, and `worker` |
| [`cvsd-infra`](https://github.com/StefAltavista/cvsd-infra) | AWS infrastructure, Kubernetes manifests, ingress, DNS, TLS, and EKS deployment workflow |

## Architecture

The application contains three custom services and two backing services:

- `vote`: Python web frontend that writes votes to Redis.
- `worker`: .NET background process that moves votes from Redis to PostgreSQL.
- `result`: Node.js web frontend that reads results from PostgreSQL.
- `redis`: temporary vote queue.
- `postgres`: persistent vote database.

```text
                                  INTERNET
                                     |
                  +------------------+------------------+
                  |                                     |
        vote.<name>.ironlabs.online       result.<name>.ironlabs.online
                  |                                     |
                  +------------------+------------------+
                                     |
                         Route 53 Alias A records
                                     |
                          AWS Network Load Balancer
                                     |
                    ingress-nginx controller (2 Pods)
                                     |
                     voting-app-ingress (host routing)
                          /                      \
                         /                        \
                vote-service                  result-service
                     |                              |
                vote Pods (2)                 result Pods (2)
                     |                              |
                     v                              v
              redis-service <--- worker ---> postgres-service
                     |                              |
               Redis StatefulSet             PostgreSQL StatefulSet
                     |                              |
                5 GiB EBS                       10 GiB EBS
```

Only `vote` and `result` are publicly addressable. Redis, PostgreSQL, and the worker remain internal to the `voting-app` namespace. The public hostnames still route to internal `ClusterIP` Services; ingress-nginx is the controlled entry point into the cluster.

## AWS infrastructure with Terraform

The primary Terraform root is in [`terraform/`](terraform/). It creates the network, EKS platform, worker capacity, IAM integration, and EKS add-ons.

### Network layout

The VPC spans two Availability Zones. Subnets are network ranges, not EC2 instances: the EC2 worker nodes are launched into the private subnets by the EKS managed node group.

```text
AWS Region: us-east-1

+-----------------------------------------------------------------------+
| VPC 10.0.0.0/16                                                       |
|                                                                       |
|  Availability Zone A                 Availability Zone B               |
|  +-----------------------------+     +-----------------------------+   |
|  | Public subnet               |     | Public subnet               |   |
|  | 10.0.101.0/24               |     | 10.0.102.0/24               |   |
|  | - NLB network interface     |     | - NLB network interface     |   |
|  | - single NAT Gateway        |     |                             |   |
|  +-----------------------------+     +-----------------------------+   |
|                                                                       |
|  +-----------------------------+     +-----------------------------+   |
|  | Private subnet              |     | Private subnet              |   |
|  | 10.0.1.0/24                 |     | 10.0.2.0/24                 |   |
|  | EKS worker node(s)          |     | EKS worker node(s)          |   |
|  | default route -> NAT in A   |     | default route -> NAT in A   |   |
|  +-----------------------------+     +-----------------------------+   |
|                                                                       |
|  EKS schedules Pods across the available worker nodes.                |
+-----------------------------------------------------------------------+
```

The internet-facing Network Load Balancer uses both public subnets. The single NAT Gateway provides outbound Internet access for resources in the private subnets; it is not part of the inbound user path. A single NAT reduces cost, although it also creates an Availability Zone dependency for outbound traffic.

### Terraform resources and defaults

| Component | Current configuration |
| --- | --- |
| VPC | `10.0.0.0/16` across two Availability Zones |
| Public subnets | `10.0.101.0/24`, `10.0.102.0/24` |
| Private subnets | `10.0.1.0/24`, `10.0.2.0/24` |
| NAT | One NAT Gateway shared by both private subnets |
| EKS cluster | `eks-<student_name>` with a public API endpoint |
| Kubernetes version | `1.34` by default; configurable with `k8s_version` |
| Managed node group | `t3.medium`, Amazon Linux 2023, desired `2`, minimum `2`, maximum `4` |
| Worker placement | EC2 instances in the private subnets |
| Storage IAM | EKS Pod Identity role with `AmazonEBSCSIDriverPolicyV2` |

The cluster creator receives administrator access. The node security group also permits all traffic between members of the same node security group so Pods and system components on different nodes can communicate. This is an AWS security group rule associated with the worker nodes, not a separate Kubernetes firewall.

### EKS managed node group

The managed node group is the EKS-managed pool of EC2 worker instances. EKS manages their lifecycle and connects them to the cluster, while Kubernetes decides which node runs each Pod. With the current defaults, the group starts two EC2 instances and can scale between two and four; this does not mean that every application Pod is duplicated in every Availability Zone.

## EKS add-ons

The add-ons are declared in Terraform and installed and managed through EKS as part of the cluster deployment.

| Add-on | Purpose |
| --- | --- |
| `vpc-cni` | Assigns VPC-routable IP addresses to Pods and implements Pod networking on AWS. |
| `kube-proxy` | Programs node networking rules so Kubernetes Service traffic reaches the correct Pods. |
| `coredns` | Provides internal DNS, allowing names such as `redis-service` and `postgres-service` to resolve inside the cluster. |
| `eks-pod-identity-agent` | Lets supported Kubernetes workloads obtain AWS permissions through EKS Pod Identity. |
| `aws-ebs-csi-driver` | Dynamically creates and attaches Amazon EBS volumes for Kubernetes persistent volume claims. |

The first three are core cluster networking and service-discovery components. The Pod Identity agent and EBS CSI driver are required by this design so the storage controller can provision EBS volumes without storing AWS credentials in Kubernetes.

## Kubernetes resources

All application resources are deployed to the `voting-app` namespace. The manifests are organized by responsibility:

```text
kubernetes/
|-- namespace.yaml
|-- config/
|   |-- app-config.yaml
|   `-- app-secrets.example.yaml
|-- storage/
|   `-- gp3-storage-class.yaml
|-- postgres/
|   |-- statefulset.yaml
|   `-- service.yaml
|-- redis/
|   |-- statefulset.yaml
|   `-- service.yaml
|-- vote/
|   |-- deployment.yaml
|   `-- service.yaml
|-- result/
|   |-- deployment.yaml
|   `-- service.yaml
|-- worker/
|   `-- deployment.yaml
|-- ingress/
|   `-- voting-app-ingress.yaml
`-- cert-manager/
    `-- cluster-issuers.yaml
```

### Workloads and Services

| Component | Kubernetes workload | Replicas | Network access | Persistent storage |
| --- | --- | ---: | --- | --- |
| Vote | Deployment | 2 | Internal `vote-service`; public through Ingress | No |
| Result | Deployment | 2 | Internal `result-service`; public through Ingress | No |
| Worker | Deployment | 1 | No Service; initiates connections to Redis and PostgreSQL | No |
| Redis | StatefulSet | 1 | Internal headless and `redis-service` Services | 5 GiB gp3 EBS |
| PostgreSQL | StatefulSet | 1 | Internal headless and `postgres-service` Services | 10 GiB gp3 EBS |

Vote and Result use rolling updates, readiness/liveness/startup probes, and two replicas. Their topology spread constraints ask Kubernetes to distribute matching replicas across different node hostnames when possible. Result uses `ClientIP` session affinity because it serves Socket.IO connections. The worker uses one replica and a `Recreate` strategy, and therefore does not need a Kubernetes Service.

Init containers prevent the application Deployments from starting before their dependencies respond. Configuration is provided by `voting-app-config`; PostgreSQL credentials are read from the `voting-app-secrets` Secret.

### Persistent storage

The `gp3` StorageClass uses the EBS CSI driver with encrypted `ext4` volumes, delayed binding (`WaitForFirstConsumer`), volume expansion, and a `Delete` reclaim policy. Delayed binding lets Kubernetes select a volume Availability Zone that matches the node chosen for the StatefulSet Pod.

Redis persistence is enabled with AOF so queued votes can survive a Pod restart. PostgreSQL stores the final application data. Because both volumes are `ReadWriteOnce` EBS volumes and both StatefulSets have one replica, this setup provides persistence but not database-level high availability.

## Ingress and the Network Load Balancer

[`scripts/ingress-up.sh`](scripts/ingress-up.sh) installs the ingress-nginx Helm chart using [`helm/ingress-nginx-values.yaml`](helm/ingress-nginx-values.yaml). The values create:

- one ingress-nginx controller Deployment;
- two replicas of that controller Pod;
- one Kubernetes `LoadBalancer` Service; and
- one public AWS Network Load Balancer (NLB) attached to the two public subnets.

NLB stands for **Network Load Balancer**. It forwards network connections to ingress-nginx; ingress-nginx then performs HTTP host-based routing. There are two controller Pods for availability, but only one controller installation and one application Ingress resource.

```text
HTTPS request
     |
     v
AWS NLB
     |
     v
one of the ingress-nginx controller Pods
     |
     +-- Host: vote.<name>.ironlabs.online   --> vote-service   --> vote Pod
     |
     `-- Host: result.<name>.ironlabs.online --> result-service --> result Pod
```

The NLB has cross-zone load balancing enabled. `externalTrafficPolicy: Local` preserves the original client IP and avoids an extra node-to-node hop when forwarding traffic to the controller.

## Route 53 DNS

DNS is managed from the separate [`terraform-dns/`](terraform-dns/) Terraform root. Keeping it separate allows the NLB to exist before its generated hostname and canonical hosted zone ID are passed into the DNS configuration.

The configuration looks up an existing public hosted zone, `ironlabs.online`, and creates two Alias A records:

```text
vote.<name>.ironlabs.online   -----+
                                      +--> ingress-nginx AWS NLB
result.<name>.ironlabs.online -----+
```

The NLB's canonical hosted zone ID is the AWS identifier Route 53 needs to construct an Alias target. It is not the ID of `ironlabs.online`; [`scripts/dns-up.sh`](scripts/dns-up.sh) obtains it directly from the load balancer API.

## TLS with cert-manager and Let's Encrypt

[`scripts/tls-up.sh`](scripts/tls-up.sh) installs cert-manager with its custom resource definitions, applies the Let's Encrypt staging and production `ClusterIssuer` resources, and then applies the application Ingress. The Ingress requests one certificate containing both public hostnames and stores it in the `voting-app-tls` Kubernetes Secret.

Certificate ownership is validated with the ACME HTTP-01 challenge:

```text
1. Ingress requests a certificate from Let's Encrypt
2. cert-manager creates a temporary HTTP challenge route
3. Let's Encrypt requests http://<hostname>/.well-known/acme-challenge/...
4. Route 53 sends the request to the NLB and ingress-nginx
5. cert-manager serves the expected token
6. Let's Encrypt validates the hostname and issues the certificate
7. ingress-nginx uses the resulting TLS Secret for HTTPS
```

HTTP-01 is a standard ACME validation method. In this deployment it requires working public DNS, a reachable ingress controller, and port 80 access before certificate issuance can complete. This dependency is why DNS is configured before TLS and why the application Ingress is applied during the TLS phase.

## Prerequisites

Install and configure:

- AWS CLI with permission to create VPC, EC2, EKS, IAM, EBS, ELB, and Route 53 resources;
- Terraform;
- `kubectl`;
- Helm;
- Bash;
- an existing public Route 53 hosted zone (the current default is `ironlabs.online`); and
- access to the Docker images referenced by the manifests.

Before deploying, create the real application Secret from the example and replace the placeholder password:

```bash
cp kubernetes/config/app-secrets.example.yaml kubernetes/config/app-secrets.yaml
```

Do not commit `kubernetes/config/app-secrets.yaml`. For a production system, use a dedicated secret-management solution instead of a plaintext local manifest.

### Name and domain customization

The deployment scripts accept a lowercase name used for AWS resource names and DNS labels. `AWS_REGION` defaults to `us-east-1`, and `DOMAIN` defaults to `ironlabs.online`.

The current application Ingress contains the explicit `stef.ironlabs.online` hostnames, and the ClusterIssuers contain a project email address. If you use another name or domain, update these files before deployment:

- `kubernetes/ingress/voting-app-ingress.yaml`
- `kubernetes/cert-manager/cluster-issuers.yaml`

## Full deployment

From the repository root, run:

```bash
./scripts/full-deploy.sh <your-name>
```

For example:

```bash
AWS_REGION=us-east-1 DOMAIN=ironlabs.online ./scripts/full-deploy.sh stef
```

The orchestrator runs five phases in dependency order:

```text
1. infra-up.sh
   Terraform VPC + EKS + node group + add-ons, then configure kubectl
                 |
                 v
2. deploy-all-services.sh
   Namespace + config + storage + Redis + PostgreSQL + worker + frontends
                 |
                 v
3. ingress-up.sh
   ingress-nginx controller + public NLB
                 |
                 v
4. dns-up.sh
   Route 53 Alias records pointing to the NLB
                 |
                 v
5. tls-up.sh
   cert-manager + Let's Encrypt issuers + application Ingress + certificate
```

When the deployment completes, the applications are available at:

```text
https://vote.<your-name>.ironlabs.online
https://result.<your-name>.ironlabs.online
```

Useful verification commands:

```bash
kubectl get nodes -o wide
kubectl get pods,services,ingress,pvc -n voting-app -o wide
kubectl get pods,services -n ingress-nginx -o wide
kubectl get certificate -n voting-app
kubectl describe certificate voting-app-tls -n voting-app
```

## Teardown

To delete the complete environment:

```bash
./scripts/full-destroy.sh <your-name>
```

This removes resources in reverse dependency order: Route 53 records, the application Ingress, ingress-nginx and its NLB, the application namespace and persistent volumes, and finally the EKS/VPC infrastructure.

> **Warning:** teardown deletes the Redis and PostgreSQL EBS volumes because the StorageClass reclaim policy is `Delete`. Back up any data that must be retained.

## CI/CD across the two repositories

Infrastructure creation is intentionally separate from application delivery. The full deployment is run when establishing the environment; subsequent application pushes update only the three custom services.

```text
cvsd-app repository

push to main
     |
     v
GitHub Actions matrix build
     |-- build + push vote image   ----+
     |-- build + push result image ----+--> Docker Hub (:latest)
     `-- build + push worker image ----+
     |
     v
workflow_dispatch API call
     |
     v
cvsd-infra/.github/workflows/deploy-services.yml
     |
     |-- authenticate to AWS
     |-- aws eks update-kubeconfig
     `-- scripts/workflow-deploy-services.sh
             |-- apply vote, result, and worker manifests
             |-- enforce imagePullPolicy: Always
             |-- restart the three Deployments
             `-- wait for successful rollouts
```

The [`cvsd-app`](https://github.com/StefAltavista/cvsd-app) workflow owns the source-code and container-image lifecycle. On a push to `main`, it builds the Vote, Result, and Worker images, pushes their `latest` tags to Docker Hub, and dispatches the infrastructure workflow only after all image builds succeed.

The [`cvsd-infra` deployment workflow](.github/workflows/deploy-services.yml) uses `workflow_dispatch`, so it can be triggered by the application repository or manually in GitHub Actions. It connects to the existing EKS cluster and rolls out only `vote`, `result`, and `worker`. It does not run Terraform or replace Redis, PostgreSQL, ingress, DNS, or TLS.

### GitHub Actions configuration

Configure the following in `cvsd-app`:

| Type | Name | Purpose |
| --- | --- | --- |
| Secret | `DOCKERHUB_USERNAME` | Docker Hub authentication |
| Secret | `DOCKERHUB_TOKEN` | Docker Hub access token |
| Secret | `INFRA_REPO_TOKEN` | Permission to dispatch the `cvsd-infra` workflow |

Configure the following in `cvsd-infra`:

| Type | Name | Purpose |
| --- | --- | --- |
| Secret | `AWS_ACCESS_KEY_ID` | AWS authentication |
| Secret | `AWS_SECRET_ACCESS_KEY` | AWS authentication |
| Variable | `AWS_REGION` | Region containing the EKS cluster |
| Variable | `EKS_CLUSTER_NAME` | Existing cluster name, for example `eks-stef` |

The AWS identity used by GitHub Actions must be authorized to describe the EKS cluster and access its Kubernetes API. The workflow expects the `voting-app` namespace and the backing services to exist already.

## Repository layout

```text
.
|-- .github/workflows/        # Application-only EKS rollout
|-- helm/                     # ingress-nginx values
|-- kubernetes/               # Namespace, workloads, Services, storage, Ingress, TLS
|-- scripts/                  # Full lifecycle and component deployment scripts
|-- terraform/                # VPC, EKS, nodes, IAM, and managed add-ons
`-- terraform-dns/            # Route 53 Alias records
```

## Design notes

- The cluster uses two Availability Zones and two worker nodes for a stronger baseline than a single-node cluster, but the single NAT Gateway and single-replica stateful services remain availability limitations.
- The NLB and ingress-nginx expose only the Vote and Result frontends; Kubernetes Services keep the remaining traffic internal.
- EBS provides durable block storage for Redis and PostgreSQL, but persistence alone is not replication or automatic database failover.
- The CI/CD path uses mutable `latest` tags and forces fresh pulls. Immutable version or digest-based image references would provide stronger traceability and rollback behavior in a production environment.
- Terraform state is local unless a remote backend is configured. For team use, add a protected remote state backend and state locking.
