provider "aws" {
    region = "us-east-1"
    access_key = ""
    secret_key = ""
}

# 1. Create vpc
resource "aws_vpc" "main-vpc" {
    cidr_block = "10.0.0.0/16"

    tags = {
      Name = "main-vpc"
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

# 4. Create a Subnet
resource "aws_subnet" "subnet-1" {
    vpc_id = aws_vpc.main-vpc.id
    cidr_block = var.subnet_prefix[0].cidr_block
    availability_zone = var.availability_zone_names[0]

    tags = {
        Name = var.subnet_prefix[0].name
    }
}

resource "aws_subnet" "subnet-2" {
    vpc_id = aws_vpc.main-vpc.id
    cidr_block = var.subnet_prefix[1].cidr_block
    availability_zone = var.availability_zone_names[1]

    tags = {
        Name = var.subnet_prefix[1].name
    }
}


# 5. Associate subnet with Route Table
resource "aws_route_table_association" "subnrt" {
    subnet_id = aws_subnet.subnet-1.id
    route_table_id = aws_route_table.main-route-table.id
}

# 6. Create Security Group to allow port 22, 80, 443
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
    ami = "ami-053b0d53c279acc90"
    instance_type = "t2.micro"
    availability_zone = var.availability_zone_names[1]
    key_name = "main-key"
    depends_on = [ aws_eip.one, aws_network_interface.web-server-nic ]

    network_interface {
        network_interface_id = aws_network_interface.web-server-nic.id
        device_index = 0
    }

    user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c 'echo your very first web server > /var/www/html/index.html'
                EOF
    
    tags = {
      Name = "Ubuntu"
    }
}

# 10. Create ECR
resource "aws_ecr_repository" "devops_repo" {
    name = "practical-devops-repo"
    image_tag_mutability = var.immutable_ecr_repositories ? "IMMUTABLE" : "MUTABLE"
    force_delete = true
    image_scanning_configuration {
        scan_on_push = true
    }

    tags = {
        Name  = "Practical DevOps Repository"
        Group = "Assigment"
    }
}

resource "aws_ecr_lifecycle_policy" "devops_lifecycle_policy" {
  repository = aws_ecr_repository.devops_repo.name

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

resource "aws_ecr_repository_policy" "devops-repo-policy" {
  repository = aws_ecr_repository.devops_repo.name
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

resource "null_resource" "update_docker_fund" {
  provisioner "local-exec" {
    working_dir = "nginx"
    command     = "chmod +x update-ecr.sh && sh -x update-ecr.sh"
  }

  depends_on = [aws_ecr_repository.devops_repo, aws_ecr_lifecycle_policy.devops_lifecycle_policy, aws_ecr_repository_policy.devops-repo-policy]
}


# 11. Create EKS