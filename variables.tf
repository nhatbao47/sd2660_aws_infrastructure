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

variable "access_key" {
  description = "Access key"
}

variable "secret_key" {
  description = "Secret key"
}

variable "subnet_prefix" {
   description = "Cidr block for subnet"
}