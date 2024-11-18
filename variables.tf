variable "zero_address" {
    type = string
    default = "0.0.0.0/0"
}

variable "immutable_ecr_repositories" {
  description = "Whether ECR repositories should be immutable"
  type        = bool
  default     = false
}

variable "region" {
    default = "ap-southeast-1"
}

variable "access_key" {
  description = "Access key"
}

variable "secret_key" {
  description = "Secret key"
}

variable "subnet_prefix" {
   description = "Cidr block for subnet"
}

variable "ecr_repositories" {
  default = {
    frontend = {
      name = "frontend"
      tags = {
        Name  = "Frontend repository"
        Group = "Practical DevOps assignment"
      }
    },
    backend = {
      name = "backend"
      tags = {
        Name  = "Backend repository"
        Group = "Practical DevOps assignment"
      }
    }
  }
}