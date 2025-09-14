terraform {
  required_version = ">= 1.13.0"

  cloud {
    organization = "gossamer-labs"

    workspaces {
      name = "port-guide-create-eks-cluster"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.7.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.1"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.4"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3.2"
    }

    port = {
      source  = "port-labs/port-labs"
      version = "2.0.0"
    }
  }
}
