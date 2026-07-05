# Data Sources
data "aws_ecs_cluster" "main" {
  cluster_name = var.ecs_cluster_name
}

data "aws_caller_identity" "current" {}

# Service Discovery Namespace
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "local"
  description = "Private DNS namespace for service discovery"
  vpc         = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "food-delivery-service-discovery"
    }
  )
}

# CloudWatch Log Groups
module "api_gateway_logs" {
  source = "./modules/cloudwatch"

  log_group_name    = "/ecs/api-gateway"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

module "user_service_logs" {
  source = "./modules/cloudwatch"

  log_group_name    = "/ecs/user-service"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

module "restaurant_service_logs" {
  source = "./modules/cloudwatch"

  log_group_name    = "/ecs/restaurant-service"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

module "order_service_logs" {
  source = "./modules/cloudwatch"

  log_group_name    = "/ecs/order-service"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# Security Groups
resource "aws_security_group" "api_gateway" {
  name        = "api-gateway-sg"
  description = "Security group for API Gateway service"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow traffic from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "api-gateway-sg"
    }
  )
}

resource "aws_security_group" "backend_services" {
  name        = "backend-services-sg"
  description = "Security group for backend microservices"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow traffic from API Gateway"
    from_port       = 8081
    to_port         = 8083
    protocol        = "tcp"
    security_groups = [aws_security_group.api_gateway.id]
  }

  # Allow inter-service communication
  ingress {
    description = "Allow inter-service communication"
    from_port   = 8081
    to_port     = 8083
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "backend-services-sg"
    }
  )
}

# Note: Ensure your RDS security group allows traffic from backend_services security group
# This should be done in your infrastructure Terraform code

# ALB Target Group for API Gateway
resource "aws_lb_target_group" "api_gateway" {
  name        = "api-gateway-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/actuator/health"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = merge(
    var.tags,
    {
      Name = "api-gateway-tg"
    }
  )
}

# ALB Listener Rule
resource "aws_lb_listener_rule" "api_gateway" {
  listener_arn = var.alb_listener_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_gateway.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  tags = var.tags
}

# ECS Task Definitions
resource "aws_ecs_task_definition" "api_gateway" {
  family                   = "api-gateway"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "arn:aws:iam::${var.aws_account_id}:role/ecsTaskExecutionRole"
  task_role_arn            = "arn:aws:iam::${var.aws_account_id}:role/ecsTaskRole"

  container_definitions = jsonencode([
    {
      name      = "api-gateway"
      image     = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/api-gateway:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "SPRING_PROFILES_ACTIVE"
          value = "prod"
        },
        {
          name  = "SERVER_PORT"
          value = "8080"
        },
        {
          name  = "USER_SERVICE_URL"
          value = "http://user-service.local:8081"
        },
        {
          name  = "RESTAURANT_SERVICE_URL"
          value = "http://restaurant-service.local:8082"
        },
        {
          name  = "ORDER_SERVICE_URL"
          value = "http://order-service.local:8083"
        },
        {
          name  = "MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE"
          value = "health,info,metrics"
        },
        {
          name  = "MANAGEMENT_ENDPOINT_HEALTH_SHOW_DETAILS"
          value = "always"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = module.api_gateway_logs.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = merge(
    var.tags,
    {
      Name = "api-gateway-task"
    }
  )
}

resource "aws_ecs_task_definition" "user_service" {
  family                   = "user-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "arn:aws:iam::${var.aws_account_id}:role/ecsTaskExecutionRole"
  task_role_arn            = "arn:aws:iam::${var.aws_account_id}:role/ecsTaskRole"

  container_definitions = jsonencode([
    {
      name      = "user-service"
      image     = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/user-service:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8081
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "SPRING_PROFILES_ACTIVE"
          value = "prod"
        },
        {
          name  = "SERVER_PORT"
          value = "8081"
        },
        {
          name  = "SPRING_DATASOURCE_URL"
          value = "jdbc:postgresql://${var.db_host}:5432/${var.db_name}"
        },
        {
          name  = "SPRING_DATASOURCE_DRIVER_CLASS_NAME"
          value = "org.postgresql.Driver"
        },
        {
          name  = "SPRING_JPA_HIBERNATE_DDL_AUTO"
          value = "update"
        },
        {
          name  = "SPRING_JPA_PROPERTIES_HIBERNATE_DIALECT"
          value = "org.hibernate.dialect.PostgreSQLDialect"
        },
        {
          name  = "MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE"
          value = "health,info,metrics"
        },
        {
          name  = "MANAGEMENT_ENDPOINT_HEALTH_SHOW_DETAILS"
          value = "always"
        }
      ]

      secrets = [
        {
          name      = "SPRING_DATASOURCE_USERNAME"
          valueFrom = "${var.db_secret_arn}:username::"
        },
        {
          name      = "SPRING_DATASOURCE_PASSWORD"
          valueFrom = "${var.db_secret_arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = module.user_service_logs.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8081/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 90
      }
    }
  ])

  tags = merge(
    var.tags,
    {
      Name = "user-service-task"
    }
  )
}

resource "aws_ecs_task_definition" "restaurant_service" {
  family                   = "restaurant-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "arn:aws:iam::${var.aws_account_id}:role/ecsTaskExecutionRole"
  task_role_arn            = "arn:aws:iam::${var.aws_account_id}:role/ecsTaskRole"

  container_definitions = jsonencode([
    {
      name      = "restaurant-service"
      image     = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/restaurant-service:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8082
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "SPRING_PROFILES_ACTIVE"
          value = "prod"
        },
        {
          name  = "SERVER_PORT"
          value = "8082"
        },
        {
          name  = "SPRING_DATASOURCE_URL"
          value = "jdbc:postgresql://${var.db_host}:5432/${var.db_name}"
        },
        {
          name  = "SPRING_DATASOURCE_DRIVER_CLASS_NAME"
          value = "org.postgresql.Driver"
        },
        {
          name  = "SPRING_JPA_HIBERNATE_DDL_AUTO"
          value = "update"
        },
        {
          name  = "SPRING_JPA_PROPERTIES_HIBERNATE_DIALECT"
          value = "org.hibernate.dialect.PostgreSQLDialect"
        },
        {
          name  = "MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE"
          value = "health,info,metrics"
        },
        {
          name  = "MANAGEMENT_ENDPOINT_HEALTH_SHOW_DETAILS"
          value = "always"
        }
      ]

      secrets = [
        {
          name      = "SPRING_DATASOURCE_USERNAME"
          valueFrom = "${var.db_secret_arn}:username::"
        },
        {
          name      = "SPRING_DATASOURCE_PASSWORD"
          valueFrom = "${var.db_secret_arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = module.restaurant_service_logs.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8082/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 90
      }
    }
  ])

  tags = merge(
    var.tags,
    {
      Name = "restaurant-service-task"
    }
  )
}

resource "aws_ecs_task_definition" "order_service" {
  family                   = "order-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "arn:aws:iam::${var.aws_account_id}:role/ecsTaskExecutionRole"
  task_role_arn            = "arn:aws:iam::${var.aws_account_id}:role/ecsTaskRole"

  container_definitions = jsonencode([
    {
      name      = "order-service"
      image     = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/order-service:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8083
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "SPRING_PROFILES_ACTIVE"
          value = "prod"
        },
        {
          name  = "SERVER_PORT"
          value = "8083"
        },
        {
          name  = "SPRING_DATASOURCE_URL"
          value = "jdbc:postgresql://${var.db_host}:5432/${var.db_name}"
        },
        {
          name  = "SPRING_DATASOURCE_DRIVER_CLASS_NAME"
          value = "org.postgresql.Driver"
        },
        {
          name  = "SPRING_JPA_HIBERNATE_DDL_AUTO"
          value = "update"
        },
        {
          name  = "SPRING_JPA_PROPERTIES_HIBERNATE_DIALECT"
          value = "org.hibernate.dialect.PostgreSQLDialect"
        },
        {
          name  = "MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE"
          value = "health,info,metrics"
        },
        {
          name  = "MANAGEMENT_ENDPOINT_HEALTH_SHOW_DETAILS"
          value = "always"
        }
      ]

      secrets = [
        {
          name      = "SPRING_DATASOURCE_USERNAME"
          valueFrom = "${var.db_secret_arn}:username::"
        },
        {
          name      = "SPRING_DATASOURCE_PASSWORD"
          valueFrom = "${var.db_secret_arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = module.order_service_logs.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8083/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 90
      }
    }
  ])

  tags = merge(
    var.tags,
    {
      Name = "order-service-task"
    }
  )
}

# ECS Services
module "api_gateway_service" {
  source = "./modules/ecs-service"

  service_name    = "api-gateway"
  cluster_id      = data.aws_ecs_cluster.main.id
  task_definition_arn = aws_ecs_task_definition.api_gateway.arn
  desired_count   = var.desired_count

  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.api_gateway.id]

  target_group_arn = aws_lb_target_group.api_gateway.arn
  container_name   = "api-gateway"
  container_port   = 8080

  enable_execute_command = var.enable_execute_command

  enable_service_discovery       = false  # API Gateway doesn't need service discovery
  service_discovery_namespace_id = null

  health_check_grace_period_seconds = 60

  tags = var.tags
}

module "user_service" {
  source = "./modules/ecs-service"

  service_name        = "user-service"
  cluster_id          = data.aws_ecs_cluster.main.id
  task_definition_arn = aws_ecs_task_definition.user_service.arn
  desired_count       = var.desired_count

  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.backend_services.id]

  target_group_arn = null  # Backend service - no ALB
  container_name   = "user-service"
  container_port   = 8081

  enable_execute_command = var.enable_execute_command

  enable_service_discovery       = true
  service_discovery_namespace_id = aws_service_discovery_private_dns_namespace.main.id

  tags = var.tags
}

module "restaurant_service" {
  source = "./modules/ecs-service"

  service_name        = "restaurant-service"
  cluster_id          = data.aws_ecs_cluster.main.id
  task_definition_arn = aws_ecs_task_definition.restaurant_service.arn
  desired_count       = var.desired_count

  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.backend_services.id]

  target_group_arn = null  # Backend service - no ALB
  container_name   = "restaurant-service"
  container_port   = 8082

  enable_execute_command = var.enable_execute_command

  enable_service_discovery       = true
  service_discovery_namespace_id = aws_service_discovery_private_dns_namespace.main.id

  tags = var.tags
}

module "order_service" {
  source = "./modules/ecs-service"

  service_name        = "order-service"
  cluster_id          = data.aws_ecs_cluster.main.id
  task_definition_arn = aws_ecs_task_definition.order_service.arn
  desired_count       = var.desired_count

  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.backend_services.id]

  target_group_arn = null  # Backend service - no ALB
  container_name   = "order-service"
  container_port   = 8083

  enable_execute_command = var.enable_execute_command

  enable_service_discovery       = true
  service_discovery_namespace_id = aws_service_discovery_private_dns_namespace.main.id

  tags = var.tags
}
