subnet_prefix = [
    {
        cidr_block = "10.0.1.0/24",
        name = "Subnet-1",
        map_public_ip = false
    },
    {
        cidr_block = "10.0.2.0/24",
        name = "Subnet-2",
        map_public_ip = true
    },
    {
        cidr_block = "10.0.3.0/24",
        name = "Subnet-3",
        map_public_ip = true
    }
]

immutable_ecr_repositories = true
access_key = ""
secret_key = ""