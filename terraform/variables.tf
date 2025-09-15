variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Version of the EKS cluster"
  type        = string
  default     = "1.33"
}

variable "port_run_id" {
  type        = string
  description = "The runID of the action run that created the entity"
  default     = ""
}

# ideally default this to null and define elsewhere
variable "platform_engineers_role_arn" {
  description = "IAM role ARN in 327207168534 assumed by Identity Center group 'platform-engineers'"
  type        = string
  default     = "arn:aws:iam::327207168534:role/aws-reserved/sso.amazonaws.com/us-east-2/AWSReservedSSO_platform-operations_2677084c3e95224d"
}
