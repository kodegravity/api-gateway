# Service Discovery
output "service_discovery_namespace_id" {
  description = "Service discovery namespace ID"
  value       = aws_service_discovery_private_dns_namespace.main.id
}

output "service_discovery_namespace_name" {
  description = "Service discovery namespace name"
  value       = aws_service_discovery_private_dns_namespace.main.name
}

# Security Groups
output "api_gateway_security_group_id" {
  description = "Security group ID for API Gateway"
  value       = aws_security_group.api_gateway.id
}

output "backend_services_security_group_id" {
  description = "Security group ID for backend services"
  value       = aws_security_group.backend_services.id
}

# ALB Target Group
output "api_gateway_target_group_arn" {
  description = "ARN of API Gateway target group"
  value       = aws_lb_target_group.api_gateway.arn
}

# ECS Services
output "api_gateway_service_name" {
  description = "Name of the API Gateway ECS service"
  value       = module.api_gateway_service.service_name
}

output "user_service_name" {
  description = "Name of the User Service ECS service"
  value       = module.user_service.service_name
}

output "restaurant_service_name" {
  description = "Name of the Restaurant Service ECS service"
  value       = module.restaurant_service.service_name
}

output "order_service_name" {
  description = "Name of the Order Service ECS service"
  value       = module.order_service.service_name
}

# Service Discovery
output "user_service_discovery_name" {
  description = "Service discovery DNS name for user-service"
  value       = module.user_service.service_discovery_name
}

output "restaurant_service_discovery_name" {
  description = "Service discovery DNS name for restaurant-service"
  value       = module.restaurant_service.service_discovery_name
}

output "order_service_discovery_name" {
  description = "Service discovery DNS name for order-service"
  value       = module.order_service.service_discovery_name
}

# CloudWatch Log Groups
output "log_groups" {
  description = "CloudWatch log groups for all services"
  value = {
    api_gateway        = module.api_gateway_logs.log_group_name
    user_service       = module.user_service_logs.log_group_name
    restaurant_service = module.restaurant_service_logs.log_group_name
    order_service      = module.order_service_logs.log_group_name
  }
}
