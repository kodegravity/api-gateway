#!/bin/bash

# Deployment Commands for Food Delivery ECS Services
# This file contains all commands needed to deploy and manage the services

# Set your variables
export AWS_REGION="ca-central-1"
export ECS_CLUSTER="food-delivery-dev-cluster"
export AWS_ACCOUNT_ID="123456789012"  # Replace with your account ID

#######################################
# 1. DEPLOY INFRASTRUCTURE
#######################################

# Navigate to terraform directory
cd terraform/ecs-deployment

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply

# Get outputs
terraform output

#######################################
# 2. CHECK ECS SERVICES
#######################################

# List all services in the cluster
aws ecs list-services \
  --cluster $ECS_CLUSTER \
  --region $AWS_REGION

# Describe all services
aws ecs describe-services \
  --cluster $ECS_CLUSTER \
  --services api-gateway user-service restaurant-service order-service \
  --region $AWS_REGION

# Check specific service
aws ecs describe-services \
  --cluster $ECS_CLUSTER \
  --services api-gateway \
  --region $AWS_REGION \
  --query 'services[0].{Name:serviceName,Status:status,Running:runningCount,Desired:desiredCount}'

#######################################
# 3. CHECK RUNNING TASKS
#######################################

# List tasks for a service
aws ecs list-tasks \
  --cluster $ECS_CLUSTER \
  --service-name api-gateway \
  --region $AWS_REGION

# Describe tasks
TASK_ARN=$(aws ecs list-tasks \
  --cluster $ECS_CLUSTER \
  --service-name api-gateway \
  --region $AWS_REGION \
  --query 'taskArns[0]' \
  --output text)

aws ecs describe-tasks \
  --cluster $ECS_CLUSTER \
  --tasks $TASK_ARN \
  --region $AWS_REGION

#######################################
# 4. VIEW TASK DEFINITION
#######################################

# Describe task definition
aws ecs describe-task-definition \
  --task-definition api-gateway \
  --region $AWS_REGION

# List task definition revisions
aws ecs list-task-definitions \
  --family-prefix api-gateway \
  --region $AWS_REGION

#######################################
# 5. CHECK CLOUDWATCH LOGS
#######################################

# Tail logs for api-gateway
aws logs tail /ecs/api-gateway \
  --follow \
  --region $AWS_REGION

# Tail logs for user-service
aws logs tail /ecs/user-service \
  --follow \
  --region $AWS_REGION

# Get recent logs (last 5 minutes)
aws logs filter-log-events \
  --log-group-name /ecs/api-gateway \
  --start-time $(date -u -d '5 minutes ago' +%s)000 \
  --region $AWS_REGION

# Search for errors
aws logs filter-log-events \
  --log-group-name /ecs/api-gateway \
  --filter-pattern "ERROR" \
  --region $AWS_REGION

#######################################
# 6. CHECK ALB AND TARGET GROUP
#######################################

# Get ALB DNS name
aws elbv2 describe-load-balancers \
  --region $AWS_REGION \
  --query 'LoadBalancers[?contains(LoadBalancerName, `food-delivery`)].DNSName' \
  --output text

# Describe target group
aws elbv2 describe-target-groups \
  --names api-gateway-tg \
  --region $AWS_REGION

# Check target health
TG_ARN=$(aws elbv2 describe-target-groups \
  --names api-gateway-tg \
  --region $AWS_REGION \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region $AWS_REGION

#######################################
# 7. TEST ENDPOINTS
#######################################

# Get ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --region $AWS_REGION \
  --query 'LoadBalancers[?contains(LoadBalancerName, `food-delivery`)].DNSName' \
  --output text)

echo "ALB DNS: $ALB_DNS"

# Test health endpoint
curl http://$ALB_DNS/actuator/health

# Test with detailed output
curl -i http://$ALB_DNS/actuator/health

# Test API endpoints (adjust based on your actual API paths)
curl http://$ALB_DNS/api/users
curl http://$ALB_DNS/api/restaurants
curl http://$ALB_DNS/api/orders

#######################################
# 8. SERVICE DISCOVERY CHECK
#######################################

# List service discovery namespaces
aws servicediscovery list-namespaces \
  --region $AWS_REGION

# List services in namespace
NAMESPACE_ID=$(aws servicediscovery list-namespaces \
  --region $AWS_REGION \
  --query 'Namespaces[?Name==`local`].Id' \
  --output text)

aws servicediscovery list-services \
  --filters Name=NAMESPACE_ID,Values=$NAMESPACE_ID \
  --region $AWS_REGION

#######################################
# 9. UPDATE SERVICE (FORCE NEW DEPLOYMENT)
#######################################

# Force new deployment (e.g., after pushing new Docker image)
aws ecs update-service \
  --cluster $ECS_CLUSTER \
  --service api-gateway \
  --force-new-deployment \
  --region $AWS_REGION

# Update service with new task definition
aws ecs update-service \
  --cluster $ECS_CLUSTER \
  --service api-gateway \
  --task-definition api-gateway:2 \
  --region $AWS_REGION

# Scale service
aws ecs update-service \
  --cluster $ECS_CLUSTER \
  --service api-gateway \
  --desired-count 2 \
  --region $AWS_REGION

#######################################
# 10. ECS EXEC (SSH INTO CONTAINER)
#######################################

# Enable execute command (already enabled in Terraform)
# Get task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster $ECS_CLUSTER \
  --service-name api-gateway \
  --region $AWS_REGION \
  --query 'taskArns[0]' \
  --output text)

# Execute command in container
aws ecs execute-command \
  --cluster $ECS_CLUSTER \
  --task $TASK_ARN \
  --container api-gateway \
  --interactive \
  --command "/bin/sh" \
  --region $AWS_REGION

#######################################
# 11. TROUBLESHOOTING
#######################################

# Check service events (recent deployment issues)
aws ecs describe-services \
  --cluster $ECS_CLUSTER \
  --services api-gateway \
  --region $AWS_REGION \
  --query 'services[0].events[0:10]'

# Check task stopped reason
aws ecs describe-tasks \
  --cluster $ECS_CLUSTER \
  --tasks $TASK_ARN \
  --region $AWS_REGION \
  --query 'tasks[0].{StoppedReason:stoppedReason,StoppedAt:stoppedAt,LastStatus:lastStatus}'

# Get CloudWatch insights query
aws logs start-query \
  --log-group-name /ecs/api-gateway \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20' \
  --region $AWS_REGION

#######################################
# 12. ROLLBACK
#######################################

# List task definition revisions
aws ecs list-task-definitions \
  --family-prefix api-gateway \
  --region $AWS_REGION

# Rollback to previous version
aws ecs update-service \
  --cluster $ECS_CLUSTER \
  --service api-gateway \
  --task-definition api-gateway:1 \
  --region $AWS_REGION

#######################################
# 13. CLEANUP
#######################################

# Delete service (scale to 0 first)
aws ecs update-service \
  --cluster $ECS_CLUSTER \
  --service api-gateway \
  --desired-count 0 \
  --region $AWS_REGION

# Delete service
aws ecs delete-service \
  --cluster $ECS_CLUSTER \
  --service api-gateway \
  --force \
  --region $AWS_REGION

# Destroy Terraform resources
cd terraform/ecs-deployment
terraform destroy
