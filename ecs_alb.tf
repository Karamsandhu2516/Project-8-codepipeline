
# 1. Application Load Balancer
resource "aws_lb" "app_alb" {
  name               = "ecs-alb-bluegreen"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
}

# 2. Blue Target Group
resource "aws_lb_target_group" "tg_blue" {
  name        = "tg-blue"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id = aws_vpc.main.id

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# 3. Green Target Group
resource "aws_lb_target_group" "tg_green" {
  name        = "tg-green"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id = aws_vpc.main.id

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# 4. ALB HTTP Listener (port 80 → blue target group by default)
resource "aws_lb_listener" "listener_http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_blue.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}


# 5. ECS Cluster
resource "aws_ecs_cluster" "app_cluster" {
  name = "node-app-cluster"
}

# 6. ECS Task Definition (Fargate)[cite: 1, 2]
resource "aws_ecs_task_definition" "app_task" {
  family                   = "node-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "node-app"
      image     = "${aws_ecr_repository.app_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
        }
      ]
    }
  ])
}