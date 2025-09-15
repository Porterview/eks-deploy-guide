provider "aws" {
  region = var.region
}
provider "port" {}
provider "random" {}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# Resolve compatible addon versions for the pinned cluster version
data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

data "aws_eks_addon_version" "eks_pod_identity" {
  addon_name         = "eks-pod-identity-agent"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

# ------------------------
# Random suffix for cluster
# ------------------------
resource "random_string" "suffix" {
  length  = 8
  special = false
}

locals {
  cluster_name = var.cluster_name != "" ? var.cluster_name : "education-eks-${random_string.suffix.result}"
}

# ------------------------
# VPC
# ------------------------
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "education-vpc"
  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }
}

# ------------------------
# GitHub Actions OIDC Provider
# ------------------------
resource "aws_iam_openid_connect_provider" "github" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  url             = "https://token.actions.githubusercontent.com"
}

# ------------------------
# IAM Role for GitHub Actions
# ------------------------
data "aws_iam_policy_document" "k8s_deployers_assume_role" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:Porterview/eks-deploy-guide:*",
        "repo:Porterview/port-integration-k8s:*"
      ]
    }
  }
}

resource "aws_iam_role" "k8s_deployers_gha" {
  name               = "k8s-deployers-gha"
  assume_role_policy = data.aws_iam_policy_document.k8s_deployers_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eks_describe" {
  role       = aws_iam_role.k8s_deployers_gha.name
  policy_arn = "arn:aws:iam::327207168534:policy/eks-describe"
}

# ------------------------
# EKS Cluster
# ------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.2.0"

  name               = local.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  #control_plane_subnet_ids = ["subnet-xyzde987", "subnet-slkjf456", "subnet-qeiru789"]
  
  endpoint_public_access = true

  # Adds the current caller identity as an administrator via cluster access entry
  enable_cluster_creator_admin_permissions = true

  # Addon versions resolved below via data sources
  # will want to pin these
  addons = {
    eks-pod-identity-agent = {
      before_compute  = true
      addon_version   = data.aws_eks_addon_version.eks_pod_identity.version
      most_recent     = false
    }
    kube-proxy = {
      before_compute  = true
      addon_version   = data.aws_eks_addon_version.kube_proxy.version
      most_recent     = false
    }
    vpc-cni = {
      before_compute  = true
      addon_version   = data.aws_eks_addon_version.vpc_cni.version
      most_recent     = false
    }
  }

  enable_irsa = true

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }

  depends_on = [
    aws_iam_role.k8s_deployers_gha,
    aws_iam_openid_connect_provider.github
  ]
}

# ------------------------
# EKS Access Entry for GitHub Actions
# ------------------------
resource "aws_eks_access_entry" "github_actions" {
  cluster_name    = module.eks.cluster_name
  principal_arn   = aws_iam_role.k8s_deployers_gha.arn
}

resource "aws_eks_access_policy_association" "github_actions_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.k8s_deployers_gha.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

# ------------------------
# EKS Access Entry for Platform Engineers (SSO)
# ------------------------
resource "aws_eks_access_entry" "platform_engineers" {
  count         = var.platform_engineers_role_arn != null ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = var.platform_engineers_role_arn
}

resource "aws_eks_access_policy_association" "platform_engineers_admin" {
  count        = var.platform_engineers_role_arn != null ? 1 : 0
  cluster_name = module.eks.cluster_name
  principal_arn = var.platform_engineers_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

# ------------------------
# EKS Managed Node Group
# ------------------------
module "managed_node_group_default" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "21.2.0"

  create = true

  region     = var.region
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id

  cluster_name       = module.eks.cluster_name
  kubernetes_version = var.cluster_version

  name            = "node-group-default"
  use_name_prefix = false

  subnet_ids = module.vpc.private_subnets

  # User data inputs required by submodule
  cluster_endpoint      = module.eks.cluster_endpoint
  cluster_auth_base64   = module.eks.cluster_certificate_authority_data
  cluster_ip_family     = module.eks.cluster_ip_family
  cluster_service_cidr  = module.eks.cluster_service_cidr

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.small"]
  min_size       = 1
  max_size       = 3
  desired_size   = 2

  # Ensure control-plane <-> data-plane comms via cluster primary SG
  cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }

  depends_on = [
    module.eks
  ]
}

# ------------------------
# Post-compute Add-ons
# ------------------------
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "4.7.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

resource "aws_eks_addon" "ebs-csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = data.aws_eks_addon_version.ebs_csi.version
  service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
  tags = {
    "eks_addon" = "ebs-csi"
    "terraform" = "true"
  }
  depends_on = [
    module.managed_node_group_default
  ]
}

# ------------------------
# Port entity
# ------------------------
resource "port_entity" "eks_cluster" {
  identifier = module.eks.cluster_arn
  title      = module.eks.cluster_name
  blueprint  = "eks"
  properties = {
    string_props = {
      "version"  = module.eks.cluster_version
      "name"     = module.eks.cluster_name
      "endpoint" = module.eks.cluster_endpoint
      "roleArn"  = module.eks.cluster_iam_role_arn
    }
  }
  relations = {
    single_relations = {
      "region" = var.region
    }
  }

  depends_on = [module.eks.cluster_name]
}
