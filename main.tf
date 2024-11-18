provider "aws" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key
}

data "aws_availability_zones" "available" {}

locals {
  vpc_id          = aws_vpc.main-vpc.id
  subnet_ids      = [for s in aws_subnet.subnets : s.id]
  security_group_id = aws_security_group.allow_web.id
}

# 1. Create VPC
resource "aws_vpc" "main-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "sd2660-vpc"
  }
}

# 2. Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = local.vpc_id

  tags = {
    Name = "main"
  }
}

# 3. Create Custom Route Table
resource "aws_route_table" "main-route-table" {
  vpc_id = local.vpc_id

  route {
    cidr_block      = var.zero_address
    gateway_id      = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "main"
  }
}

# 4. Create subnets
resource "aws_subnet" "subnets" {
  count = length(var.subnet_prefix)

  vpc_id            = local.vpc_id
  cidr_block        = var.subnet_prefix[count.index].cidr_block
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = var.subnet_prefix[count.index].map_public_ip

  tags = {
    Name = var.subnet_prefix[count.index].name
  }
}

# 5. Associate subnet with Route Table
resource "aws_route_table_association" "associations" {
  count = length(aws_subnet.subnets)

  subnet_id      = aws_subnet.subnets[count.index].id
  route_table_id = aws_route_table.main-route-table.id
}

# 6. Create Security Group to allow port 22, 80, 443, 8080
resource "aws_security_group" "allow_web" {
    name = "allow_web_traffic"
    description = "Allow web inboundd traffic"
    vpc_id = local.vpc_id

    ingress {
        description = "HTTPS from VPC"
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = [var.zero_address]
    }

    ingress {
        description = "HTTP"
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = [var.zero_address]
    }

    ingress {
        description = "HTTP"
        from_port = 8080
        to_port = 8080
        protocol = "tcp"
        cidr_blocks = [var.zero_address]
    }

    ingress {
        description = "SSH"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [var.zero_address]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = [var.zero_address]
    }

    tags = {
      Name = "allow_tls"
    }  
}

# 7. Create a network interface with an IP in the subnet
resource "aws_network_interface" "web-server-nic" {
  subnet_id      = aws_subnet.subnets[0].id
  private_ips    = ["10.0.1.50"]
  security_groups = [local.security_group_id]
}

# 8. Assign an Elastic IP to the network interface
resource "aws_eip" "one" {
  network_interface = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw]
}

# 9. Create Ubuntu server and install/enable Apache2
resource "aws_instance" "web-server" {
  ami                = "ami-03fa85deedfcac80b"
  instance_type      = "t2.small"
  availability_zone  = data.aws_availability_zones.available.names[0]
  key_name           = "main-key"
  depends_on         = [aws_network_interface.web-server-nic, aws_eip.one]

  network_interface {
    network_interface_id = aws_network_interface.web-server-nic.id
    device_index         = 0
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo apt-get update
                sudo apt-get install ca-certificates curl gnupg
                sudo install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                sudo chmod a+r /etc/apt/keyrings/docker.gpg
                echo \
                    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
                    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                sudo apt-get update
                sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
                sudo docker run hello-world
                EOF

  tags = {
    Name = "Ubuntu Web Server"
  }
}

# 10. Create ECR Repositories
locals {
  ecr_repositories = [
    {
      name        = "frontend"
      description = "Frontend repository"
    },
    {
      name        = "backend"
      description = "Backend repository"
    }
  ]
}

resource "aws_ecr_repository" "repo" {
  for_each              = { for r in local.ecr_repositories : r.name => r }
  name                  = each.value.name
  image_tag_mutability  = var.immutable_ecr_repositories ? "IMMUTABLE" : "MUTABLE"
  force_delete          = true
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = each.value.description
    Group       = "Practical DevOps assignment"
  }
}

resource "aws_ecr_lifecycle_policy" "repo_lifecycle" {
  for_each  = aws_ecr_repository.repo
  repository = each.value.name

  policy = <<EOF
            {
              "rules": [
                {
                  "rulePriority": 1,
                  "description": "Expire images older than 14 days",
                  "selection": {
                    "tagStatus": "any",
                    "countType": "sinceImagePushed",
                    "countUnit": "days",
                    "countNumber": 14
                  },
                  "action": {
                    "type": "expire"
                  }
                }
              ]
            }
            EOF
}

resource "aws_ecr_repository_policy" "repo_policy" {
  for_each  = aws_ecr_repository.repo
  repository = each.value.name
  policy     = <<EOF
                {
                  "Version": "2012-10-17",
                  "Statement": [
                    {
                      "Sid": "Set the permission for ECR",
                      "Effect": "Allow",
                      "Principal": "*",
                      "Action": [
                        "ecr:BatchCheckLayerAvailability",
                        "ecr:BatchGetImage",
                        "ecr:CompleteLayerUpload",
                        "ecr:GetDownloadUrlForLayer",
                        "ecr:GetLifecyclePolicy",
                        "ecr:InitiateLayerUpload",
                        "ecr:PutImage",
                        "ecr:UploadLayerPart",
                        "ecr:GetAuthorizationToken"
                      ]
                    }
                  ]
                }
                EOF
}

# 11. Create EKS
locals {
  cluster_name = "sd2660-devops-eks"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = ">= 19.18.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.27"

  vpc_id                         = local.vpc_id
  subnet_ids                     = [local.subnet_ids[1], local.subnet_ids[2]]
  cluster_endpoint_public_access = true

  cluster_addons = {
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
    aws-ebs-csi-driver = {
      addon_version = "v1.27.0-eksbuild.1"
    }
  }

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"
    disk_size  = 20
    volume_type = "gp2"
  }

  eks_managed_node_groups = {
    one = {
      name          = "node-group-1"
      instance_types = ["t2.small"]
      min_size     = 1
      max_size     = 5
      desired_size = 3
      availability_zones = data.aws_availability_zones.available.names
    }
  }
}