variable "availability_zone_names" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1e", "us-east-1d"]
}

variable "zero-address" {
    type = string
    default = "0.0.0.0/0"
}

variable "docker_image_tag" {
    type = string
    description = "This is the tag which will be used for the created image"
    default = "latest"
}

variable "immutable_ecr_repositories" {
    type = bool
    default = true
}

variable "region" {
    default = "us-east-1"
}

variable "subnet_prefix" {
  description = "Cidr block for subnet"
}