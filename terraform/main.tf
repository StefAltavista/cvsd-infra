locals {
  cluster_name = "eks-${var.student_name}"

  common_tags = {
    Project   = "voting-app"
    Student   = var.student_name
    ManagedBy = "Terraform"
  }
}

# -------------------------------------------------------------------
# EBS CSI Pod Identity
# -------------------------------------------------------------------

# EKS Pod Identity assumes this IAM role on behalf of the
# ebs-csi-controller-sa Kubernetes service account.
data "aws_iam_policy_document" "ebs_csi_pod_identity" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_pod_identity.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role = aws_iam_role.ebs_csi.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}

# -------------------------------------------------------------------
# Network
# -------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "vpc-${var.student_name}"
  cidr = "10.0.0.0/16"

  azs             = ["${var.region}a", "${var.region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Public subnets are used by public load balancers,
  # including the ingress-nginx LoadBalancer service.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  # Private subnets are available for internal load balancers.
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.common_tags
}

# -------------------------------------------------------------------
# EKS cluster and worker nodes
# -------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.31.6"

  cluster_name    = local.cluster_name
  cluster_version = var.k8s_version

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  # We use EKS Pod Identity instead of IRSA for the EBS CSI driver.
  enable_irsa = false

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    # Required for normal Pod networking.
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }

    kube-proxy = {
      most_recent = true
    }

    coredns = {
      most_recent = true
    }

    # Runs the Pod Identity agent on each worker node.
    eks-pod-identity-agent = {
      most_recent    = true
      before_compute = true
    }

    # Dynamically provisions EBS volumes for Kubernetes PVCs.
    aws-ebs-csi-driver = {
      most_recent = true

      pod_identity_association = [
        {
          role_arn        = aws_iam_role.ebs_csi.arn
          service_account = "ebs-csi-controller-sa"
        }
      ]
    }
  }
  # Allow Pods and system components on different worker nodes
  # to communicate on all ports and protocols.
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports and protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }
  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      ami_type       = "AL2023_x86_64_STANDARD"

      min_size     = var.min_nodes
      max_size     = var.max_nodes
      desired_size = var.desired_nodes
    }
  }

  tags = merge(
    local.common_tags,
    {
      GuardDutyManaged = "false"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi
  ]
}