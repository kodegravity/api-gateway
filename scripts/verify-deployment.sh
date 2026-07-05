#!/bin/bash

# Food Delivery ECS Deployment Verification Script
# This script verifies that all ECS services are deployed and healthy

set -e

# Configuration
REGION="${AWS_REGION:-ca-central-1}"
CLUSTER_NAME="${ECS_CLUSTER:-food-delivery-dev-cluster}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_service() {
    local service_name=$1
    log_info "Checking service: $service_name"
    
    # Get service details
    service_info=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$service_name" \
        --region "$REGION" \
        --query 'services[0]' 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_error "Failed to describe service $service_name"
        return 1
    fi
    
    # Check if service exists
    status=$(echo "$service_info" | jq -r '.status')
    if [ "$status" != "ACTIVE" ]; then
        log_error "Service $service_name is not ACTIVE (status: $status)"
        return 1
    fi
    
    # Check running count
    desired=$(echo "$service_info" | jq -r '.desiredCount')
    running=$(echo "$service_info" | jq -r '.runningCount')
    
    echo "  - Desired: $desired"
    echo "  - Running: $running"
    
    if [ "$running" -eq "$desired" ]; then
        log_info "Service $service_name is healthy ✓"
        return 0
    else
        log_warn "Service $service_name has $running/$desired tasks running"
        return 1
    fi
}

check_task() {
    local service_name=$1
    log_info "Checking tasks for service: $service_name"
    
    # List tasks
    task_arns=$(aws ecs list-tasks \
        --cluster "$CLUSTER_NAME" \
        --service-name "$service_name" \
        --region "$REGION" \
        --query 'taskArns[]' \
        --output text)
    
    if [ -z "$task_arns" ]; then
        log_warn "No tasks found for $service_name"
        return 1
    fi
    
    # Describe tasks
    for task_arn in $task_arns; do
        task_info=$(aws ecs describe-tasks \
            --cluster "$CLUSTER_NAME" \
            --tasks "$task_arn" \
            --region "$REGION" \
            --query 'tasks[0]')
        
        last_status=$(echo "$task_info" | jq -r '.lastStatus')
        health_status=$(echo "$task_info" | jq -r '.healthStatus')
        
        echo "  - Task: $(basename $task_arn)"
        echo "    Status: $last_status"
        echo "    Health: $health_status"
    done
}

check_target_group() {
    local tg_name=$1
    log_info "Checking target group: $tg_name"
    
    # Get target group ARN
    tg_arn=$(aws elbv2 describe-target-groups \
        --names "$tg_name" \
        --region "$REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ] || [ "$tg_arn" == "None" ]; then
        log_error "Target group $tg_name not found"
        return 1
    fi
    
    # Check target health
    targets=$(aws elbv2 describe-target-health \
        --target-group-arn "$tg_arn" \
        --region "$REGION" \
        --query 'TargetHealthDescriptions[*].{Target:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}')
    
    echo "$targets" | jq -r '.[] | "  - Target: \(.Target) | State: \(.State) | Reason: \(.Reason // "N/A")"'
}

check_cloudwatch_logs() {
    local log_group=$1
    log_info "Checking CloudWatch log group: $log_group"
    
    # Check if log group exists
    aws logs describe-log-groups \
        --log-group-name-prefix "$log_group" \
        --region "$REGION" \
        --query 'logGroups[0].logGroupName' \
        --output text >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_info "Log group $log_group exists ✓"
        
        # Get recent log streams
        streams=$(aws logs describe-log-streams \
            --log-group-name "$log_group" \
            --region "$REGION" \
            --order-by LastEventTime \
            --descending \
            --max-items 3 \
            --query 'logStreams[*].logStreamName' \
            --output text)
        
        if [ -n "$streams" ]; then
            echo "  Recent log streams:"
            echo "$streams" | tr '\t' '\n' | sed 's/^/    - /'
        fi
    else
        log_error "Log group $log_group not found"
        return 1
    fi
}

test_endpoint() {
    local url=$1
    local endpoint=$2
    log_info "Testing endpoint: $url$endpoint"
    
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url$endpoint" || echo "000")
    
    if [ "$response" == "200" ]; then
        log_info "Endpoint is healthy (HTTP $response) ✓"
        return 0
    else
        log_error "Endpoint returned HTTP $response"
        return 1
    fi
}

# Main verification
echo "========================================"
echo "ECS Deployment Verification"
echo "========================================"
echo ""

log_info "Region: $REGION"
log_info "Cluster: $CLUSTER_NAME"
echo ""

# Check ECS Services
echo "----------------------------------------"
echo "1. Checking ECS Services"
echo "----------------------------------------"
services=("api-gateway" "user-service" "restaurant-service" "order-service")
for service in "${services[@]}"; do
    check_service "$service"
    echo ""
done

# Check Tasks
echo "----------------------------------------"
echo "2. Checking ECS Tasks"
echo "----------------------------------------"
for service in "${services[@]}"; do
    check_task "$service"
    echo ""
done

# Check Target Group (API Gateway only)
echo "----------------------------------------"
echo "3. Checking ALB Target Group"
echo "----------------------------------------"
check_target_group "api-gateway-tg"
echo ""

# Check CloudWatch Logs
echo "----------------------------------------"
echo "4. Checking CloudWatch Log Groups"
echo "----------------------------------------"
log_groups=("/ecs/api-gateway" "/ecs/user-service" "/ecs/restaurant-service" "/ecs/order-service")
for log_group in "${log_groups[@]}"; do
    check_cloudwatch_logs "$log_group"
    echo ""
done

# Test Endpoints (if ALB DNS is provided)
if [ -n "$ALB_DNS" ]; then
    echo "----------------------------------------"
    echo "5. Testing Endpoints"
    echo "----------------------------------------"
    test_endpoint "http://$ALB_DNS" "/actuator/health"
    echo ""
fi

echo "========================================"
log_info "Verification complete!"
echo "========================================"
