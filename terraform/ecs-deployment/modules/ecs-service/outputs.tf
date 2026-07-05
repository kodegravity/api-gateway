output "service_id" {
  description = "ID of the ECS service"
  value       = aws_ecs_service.this.id
}

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.this.name
}

output "service_discovery_arn" {
  description = "ARN of the service discovery service"
  value       = var.enable_service_discovery && var.service_discovery_namespace_id != null ? aws_service_discovery_service.this[0].arn : null
}

output "service_discovery_name" {
  description = "Name used for service discovery"
  value       = var.enable_service_discovery && var.service_discovery_namespace_id != null ? "${var.service_name}.local" : null
}
