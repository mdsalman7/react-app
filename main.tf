provider "aws" {
  region = "ap-south-1"
}

# Create VPC
resource "aws_vpc" "devops_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "devops-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.devops_vpc.id
  tags = {
    Name = "devops-igw"
  }
}

# Public Subnets
resource "aws_subnet" "public_1a" {
  vpc_id                = aws_vpc.devops_vpc.id
  cidr_block            = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone     = "ap-south-1a"
  tags = {
    Name = "public-1a"
  }
}

resource "aws_subnet" "public_1b" {
  vpc_id                = aws_vpc.devops_vpc.id
  cidr_block            = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone     = "ap-south-1b"
  tags = {
    Name = "public-1b"
  }
}
# Private Subnet
resource "aws_subnet" "private_1a" {
  vpc_id                  = aws_vpc.devops_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = false
  tags = {
    Name = "private-1a"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# Public Subnet for NAT Gateway (already exists)
resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.devops_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-1a"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1a.id
  tags = {
    Name = "devops-nat-gw"
  }
}

# Route Table for Private Subnet
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.devops_vpc.id
  tags = {
    Name = "private-route-table"
  }
}

# Route for Private Subnet Traffic via NAT Gateway
resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

# Associate Route Table with Private Subnet
resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private_route_table.id
}


# Route Table for Public Subnets
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.devops_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

# Public Route Table Associations
resource "aws_route_table_association" "public_rt_1a" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rt_1b" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public_rt.id
}

# Route Table for Private Subnet
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.devops_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "private-rt"
  }
}

# Private Route Table Association
resource "aws_route_table_association" "private_rt_1a" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private_rt.id
}

# Security Groups
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.devops_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}

resource "aws_security_group" "ecs_sg" {
  vpc_id = aws_vpc.devops_vpc.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.9.97/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-sg"
  }
}

resource "aws_security_group" "jump_sg" {
  vpc_id = aws_vpc.devops_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jump-sg"
  }
}

# ALB Target Groups
resource "aws_lb_target_group" "tg_80" {
  name     = "tg-80"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.devops_vpc.id
  health_check {
    path = "/"
  }
  tags = {
    Name = "tg-80"
  }
}

resource "aws_lb_target_group" "tg_3000" {
  name     = "tg-3000"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.devops_vpc.id
  health_check {
    path = "/"
  }
  tags = {
    Name = "tg-3000"
  }
}

# EC2 Instances (Jump Server and ECS)
resource "aws_instance" "jump_server" {
  ami             = "ami-0dee22c13ea7a9a67"
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.public_1a.id
  security_group_ids = [aws_security_group.jump_sg.id] # Change this line
  tags = {
    Name = "jump-server"
  }
}

resource "aws_instance" "ecs_instance" {
  ami             = "ami-0dee22c13ea7a9a67" # Example AMI for ECS
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.private_1a.id
  security_groups = [aws_security_group.ecs_sg.name]
  tags = {
    Name = "ecs-instance"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ecs-cluster"
}

# IAM Roles for ECS Task Execution
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Effect   = "Allow"
      Sid      = ""
    }]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Effect   = "Allow"
      Sid      = ""
    }]
  })
}

# ECS Task Definition
resource "aws_ecs_task_definition" "ecs_task" {
  family                   = "ecs-task-family"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "web-container"
    image     = "salmanp7/react-controller-app:latest"
    portMappings = [
      {
        containerPort = 80
        hostPort      = 80
        protocol      = "tcp"
      },
      {
        containerPort = 3000
        hostPort      = 3000
        protocol      = "tcp"
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/web-app"
        "awslogs-region"        = "ap-south-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# Security Group for ECS
resource "aws_security_group" "ecs_sg" {
  name   = "ecs-sg"
  vpc_id = aws_vpc.devops_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.9.97/32"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
