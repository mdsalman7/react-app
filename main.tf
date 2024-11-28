provider "aws" {
  region = "ap-south-1"
}

resource "aws_vpc" "devops_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "devops-vpc"
  }
}

resource "aws_subnet" "subnet_ap_south_1a" {
  vpc_id                  = aws_vpc.devops_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "subnet-ap-south-1a"
  }
}

resource "aws_subnet" "subnet_ap_south_1b" {
  vpc_id                  = aws_vpc.devops_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "subnet-ap-south-1b"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.devops_vpc.id
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.subnet_ap_south_1a.id
}

resource "aws_eip" "nat_eip" {
  vpc = true
  domain = "vpc" # Warning corrected: use domain instead of vpc
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

# Launch EC2 Instances for Jump Server and ECS Instance
resource "aws_instance" "jump_server" {
  ami             = "ami-0dee22c13ea7a9a67"  # Ubuntu AMI
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.subnet_ap_south_1a.id
  security_groups = [aws_security_group.ecs_sg.name]
  
  tags = {
    Name = "Jump Server"
  }
}

resource "aws_instance" "ecs_instance" {
  ami             = "ami-0dee22c13ea7a9a67"  # Ubuntu AMI
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.subnet_ap_south_1a.id
  security_groups = [aws_security_group.ecs_sg.name]

  tags = {
    Name = "ECS Instance"
  }
}

# Load Balancer Setup
resource "aws_lb" "ecs_lb" {
  name               = "ecs-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups   = [aws_security_group.ecs_sg.id]
  subnets            = [aws_subnet.subnet_ap_south_1a.id, aws_subnet.subnet_ap_south_1b.id]
  enable_deletion_protection = false
}

# Target Group for Port 80
resource "aws_lb_target_group" "tg_80" {
  name     = "target-group-80"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.devops_vpc.id
}

# Target Group for Port 3000
resource "aws_lb_target_group" "tg_3000" {
  name     = "target-group-3000"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.devops_vpc.id
}

# ALB Listener for Port 80
resource "aws_lb_listener" "listener_80" {
  load_balancer_arn = aws_lb.ecs_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response {
      status_code = 200
      content_type = "text/plain"
      message_body = "Hello from ALB"
    }
  }
}

# ALB Listener for Port 3000
resource "aws_lb_listener" "listener_3000" {
  load_balancer_arn = aws_lb.ecs_lb.arn
  port              = "3000"
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response {
      status_code = 200
      content_type = "text/plain"
      message_body = "Hello from ALB on Port 3000"
    }
  }
}

output "alb_dns_name" {
  value = aws_lb.ecs_lb.dns_name
}
