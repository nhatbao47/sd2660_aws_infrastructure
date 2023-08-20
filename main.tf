provider "aws" {
    region = var.region
    access_key = var.access_key
    secret_key = var.secret_key
}

data "aws_availability_zones" "available" {}

# 1. Create vpc
resource "aws_vpc" "main-vpc" {
    cidr_block = "10.0.0.0/16"

    tags = {
      Name = "sd2660-vpc"
    }
}

# 2. Create Internet Gateway
resource "aws_internet_gateway" "gw" {
    vpc_id = aws_vpc.main-vpc.id

    tags = {
      Name = "main"
    }
}

# 3. Create Custom Route Table
resource "aws_route_table" "main-route-table" {
    vpc_id = aws_vpc.main-vpc.id

    route {
        cidr_block = var.zero-address
        gateway_id = aws_internet_gateway.gw.id
    }

    route {
        ipv6_cidr_block = "::/0"
        gateway_id = aws_internet_gateway.gw.id
    }

    tags = {
        Name = "main" 
    }
}

# 4. Create subnets
resource "aws_subnet" "subnet-1" {
    vpc_id = aws_vpc.main-vpc.id
    cidr_block = var.subnet_prefix[0].cidr_block
    availability_zone = data.aws_availability_zones.available.names[0]

    tags = {
        Name = var.subnet_prefix[0].name
    }
}

resource "aws_subnet" "subnet-2" {
    vpc_id = aws_vpc.main-vpc.id
    cidr_block = var.subnet_prefix[1].cidr_block
    availability_zone = data.aws_availability_zones.available.names[1]

    tags = {
        Name = var.subnet_prefix[1].name
    }
}

resource "aws_subnet" "subnet-3" {
    vpc_id = aws_vpc.main-vpc.id
    cidr_block = var.subnet_prefix[2].cidr_block
    availability_zone = data.aws_availability_zones.available.names[2]

    tags = {
        Name = var.subnet_prefix[2].name
    }
}


# 5. Associate subnet with Route Table
resource "aws_route_table_association" "subnrt" {
    subnet_id = aws_subnet.subnet-1.id
    route_table_id = aws_route_table.main-route-table.id
}

# 6. Create Security Group to allow port 22, 80, 443, 8080
resource "aws_security_group" "allow_web" {
    name = "allow_web_traffic"
    description = "Allow web inboundd traffic"
    vpc_id = aws_vpc.main-vpc.id

    ingress {
        description = "HTTPS from VPC"
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = [var.zero-address]
    }

    ingress {
        description = "HTTP"
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = [var.zero-address]
    }

    ingress {
        description = "HTTP"
        from_port = 8080
        to_port = 8080
        protocol = "tcp"
        cidr_blocks = [var.zero-address]
    }

    ingress {
        description = "SSH"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [var.zero-address]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = [var.zero-address]
    }

    tags = {
      Name = "allow_tls"
    }  
}

# 7. Create a network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "web-server-nic" {
    subnet_id = aws_subnet.subnet-1.id
    private_ips = ["10.0.1.50"]
    security_groups = [aws_security_group.allow_web.id]
}

# 8. Assign an elastic IP to the network interface created in step 7
resource "aws_eip" "one" {
    network_interface = aws_network_interface.web-server-nic.id
    associate_with_private_ip = "10.0.1.50"
    depends_on = [ aws_internet_gateway.gw ]
}

# 9. Create Ubuntu server and install/enable apache2
resource "aws_instance" "web-server" {
    ami = "ami-0261755bbcb8c4a84"
    instance_type = "t2.small"
    availability_zone = data.aws_availability_zones.available.names[0]
    key_name = "main-key"
    depends_on = [ aws_eip.one, aws_network_interface.web-server-nic ]

    network_interface {
        network_interface_id = aws_network_interface.web-server-nic.id
        device_index = 0
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
      Name = "Ubuntu"
    }
}

# 10. Create ECR
resource "aws_ecr_repository" "frontend_repo" {
    name = "frontend"
    image_tag_mutability = var.immutable_ecr_repositories ? "IMMUTABLE" : "MUTABLE"
    force_delete = true
    image_scanning_configuration {
        scan_on_push = true
    }

    tags = {
        Name  = "Frontend repository"
        Group = "Practical DevOps assigment"
    }
}

resource "aws_ecr_lifecycle_policy" "frontend_lifecycle_policy" {
  repository = aws_ecr_repository.frontend_repo.name

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

resource "aws_ecr_repository_policy" "frontend_repo_policy" {
  repository = aws_ecr_repository.frontend_repo.name
  policy     = <<EOF
  {
    "Version": "2008-10-17",
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
          "ecr:UploadLayerPart"
        ]
      }
    ]
  }
  EOF
}

resource "aws_ecr_repository" "backend_repo" {
    name = "backend"
    image_tag_mutability = var.immutable_ecr_repositories ? "IMMUTABLE" : "MUTABLE"
    force_delete = true
    image_scanning_configuration {
        scan_on_push = true
    }

    tags = {
        Name  = "Backend repository"
        Group = "Practical DevOps assigment"
    }
}

resource "aws_ecr_lifecycle_policy" "backend_lifecycle_policy" {
  repository = aws_ecr_repository.backend_repo.name

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

resource "aws_ecr_repository_policy" "backend_repo_policy" {
  repository = aws_ecr_repository.backend_repo.name
  policy     = <<EOF
  {
    "Version": "2008-10-17",
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
          "ecr:UploadLayerPart"
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
  version = "19.15.3"

  cluster_name    = local.cluster_name
  cluster_version = "1.27"

  vpc_id                         = aws_vpc.main-vpc.id
  subnet_ids                     = [aws_subnet.subnet-2.id, aws_subnet.subnet-3.id]
  cluster_endpoint_public_access = true

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"
  }

  eks_managed_node_groups = {
    one = {
      name = "node-group-1"

      instance_types = ["t2.nano"]

      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
  }
}

data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "4.7.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

resource "aws_eks_addon" "ebs-csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.20.0-eksbuild.1"
  service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
  tags = {
    "eks_addon" = "ebs-csi"
    "terraform" = "true"
  }
}