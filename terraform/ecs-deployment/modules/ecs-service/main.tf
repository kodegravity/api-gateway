resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = var.cluster_id
  task_definition = var.task_definition_arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  enable_execute_command = var.enable_execute_command

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  # Load balancer configuration (only for api-gateway)
  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  # Service discovery configuration (for internal service-to-service communication)
  dynamic "service_registries" {
    for_each = var.enable_service_discovery && var.service_discovery_namespace_id != null ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.this[0].arn
    }
  }

  health_check_grace_period_seconds = var.target_group_arn != null ? var.health_check_grace_period_seconds : null

  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 100
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(
    var.tags,
    {
      Name = var.service_name
    }
  )

  # Ensure task definition changes trigger service updates
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_service_discovery_service.this
  ]
}

# AWS Cloud Map Service Discovery
resource "aws_service_discovery_service" "this" {
  count = var.enable_service_discovery && var.service_discovery_namespace_id != null ? 1 : 0

  name = var.service_name

  dns_config {
    namespace_id = var.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.service_name}-discovery"
    }
  )
}
