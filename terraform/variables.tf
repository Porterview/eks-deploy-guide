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

# NOTE: ideally default this to null and define elsewhere
variable "platform_engineers_role_arn" {
  description = "IAM role ARN in 496973234569 assumed by Identity Center group 'platform-engineers'"
  type        = string
  default     = "arn:aws:iam::496973234569:role/aws-reserved/sso.amazonaws.com/us-east-2/AWSReservedSSO_platform-operations_cebcc15b810c4dd2"
}
