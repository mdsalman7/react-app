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

# Public Subnet 1
resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.devops_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-1a"
  }
}

# Public Subnet 2
resource "aws_subnet" "public_1b" {
  vpc_id                  = aws_vpc.devops_vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-south-1b"
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

# NAT Gateway
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1a.id
  tags = {
    Name = "devops-nat-gw"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.devops_vpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate Route Table with Public Subnet 1a
resource "aws_route_table_association" "public_1a_association" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public_route_table.id
}

# Associate Route Table with Public Subnet 1b
resource "aws_route_table_association" "public_1b_association" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public_route_table.id
}

# Update existing NAT Gateway route for Private Subnet
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.devops_vpc.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "private-route-table"
  }
}

# Ensure Private Subnet is associated with the updated route table
resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private_route_table.id
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

# Security Group for ECS
resource "aws_security_group" "ecs_sg" {
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
    Name = "ecs-sg"
  }
}

# Load Balancer
resource "aws_lb" "my_alb" {
  name                        = "my-alb"
  internal                    = false
  load_balancer_type          = "application"
  security_groups             = [aws_security_group.alb_sg.id]
  subnets                     = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
  enable_deletion_protection  = false
  enable_cross_zone_load_balancing = true
  enable_http2                = true
}

# Target Groups
resource "aws_lb_target_group" "tg_80" {
  name        = "tg-80"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.devops_vpc.id
  target_type = "instance"

  health_check {
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name = "tg-80"
  }
}

resource "aws_lb_target_group" "tg_3000" {
  name        = "tg-3000"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.devops_vpc.id
  target_type = "instance"

  health_check {
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name = "tg-3000"
  }
}

# Load Balancer Listener
resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      status_code   = 200
      content_type = "text/plain"
      message_body = "OK"
    }
  }
}

# Listener Rules
resource "aws_lb_listener_rule" "rule_tg_80" {
  listener_arn = aws_lb_listener.my_listener.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_80.arn
  }

  condition {
    path_pattern {
      values = ["/app1/*"]
    }
  }
}

resource "aws_lb_listener_rule" "rule_tg_3000" {
  listener_arn = aws_lb_listener.my_listener.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/app2/*"]
    }
  }
}

# EC2 Instance (Jump Server)
resource "aws_instance" "jump_server" {
  ami                    = "ami-0dee22c13ea7a9a67"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_1a.id
  vpc_security_group_ids = [aws_security_group.alb_sg.id]
  key_name               = "jump-server"
  tags = {
    Name = "jump-server"
  }
}

# ECS Optimized Amazon Linux 2 AMI (EC2)
resource "aws_instance" "ecs_instance" {
  ami                    = "ami-0dee22c13ea7a9a67"  
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_1a.id
  vpc_security_group_ids = [aws_security_group.ecs_sg.id]
  key_name               = "jump-server"
  iam_instance_profile   = aws_iam_instance_profile.ecs_instance_profile.name
  user_data              = <<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${aws_ecs_cluster.ecs_cluster.name} >> /etc/ecs/ecs.config
              EOF

  tags = {
    Name = "ecs-instance"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ecs-cluster"
}

# IAM Role for ECS EC2 Instance
resource "aws_iam_role" "ecs_instance_role" {
  name = "ecs-instance-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for ECS EC2 Instance
resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# IAM Instance Profile for ECS EC2 Instance
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
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
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Task Role
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

# CloudWatch Log Group for ECS Container Logs
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/web-container"
  retention_in_days = 30

  tags = {
    Name        = "ecs-web-container-logs"
    Environment = "production"
  }
}

# Update IAM Role to allow CloudWatch Logs creation
resource "aws_iam_role_policy" "ecs_cloudwatch_logs_policy" {
  name = "ecs-cloudwatch-logs-policy"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.ecs_log_group.arn}:*"
      }
    ]
  })
}

# ECS Task Definition for EC2
resource "aws_ecs_task_definition" "ecs_task" {
  family                   = "ecs-task-family"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "web-container"
    image     = "salmanp7/react-controller-app:latest"
    essential = true
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
        "awslogs-group"         = "/ecs/web-container"
        "awslogs-region"        = "ap-south-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# Continue from the previous configuration...

# ECS Capacity Provider
resource "aws_ecs_capacity_provider" "ecs_capacity_provider" {
  name = "ecs-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn
    managed_scaling {
      maximum_scaling_step_size = 1000
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }
}

# Attach Capacity Provider to ECS Cluster
resource "aws_ecs_cluster_capacity_providers" "example" {
  cluster_name = aws_ecs_cluster.ecs_cluster.name

  capacity_providers = [aws_ecs_capacity_provider.ecs_capacity_provider.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
  }
}

# Launch Template for ECS Instances
resource "aws_launch_template" "ecs_launch_template" {
  name_prefix   = "ecs-launch-template"
  image_id      = "ami-0c29476f4e61c9cdb"  # ECS-Optimized Amazon Linux 2 AMI for ap-south-1
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ecs_sg.id]
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${aws_ecs_cluster.ecs_cluster.name} >> /etc/ecs/ecs.config
              EOF
  )

  key_name = "jump-server"
}

# Auto Scaling Group for ECS Instances
resource "aws_autoscaling_group" "ecs_asg" {
  desired_capacity    = 1
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = [aws_subnet.private_1a.id]

  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

# Updated ECS Service Configuration
resource "aws_ecs_service" "ecs_service" {
  name            = "ecs-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_task.arn
  desired_count   = 1
  launch_type     = "EC2"

  load_balancer {
    target_group_arn = aws_lb_target_group.tg_80.arn
    container_name   = "web-container"
    container_port   = 80
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg_3000.arn
    container_name   = "web-container"
    container_port   = 3000
  }

  # Ensure the service waits for the capacity provider to be ready
  depends_on = [aws_ecs_cluster_capacity_providers.example]
}
