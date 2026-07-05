# Quick Start Guide - ECS Deployment

This is a condensed version of the deployment guide. For complete details, see [ECS_DEPLOYMENT_GUIDE.md](ECS_DEPLOYMENT_GUIDE.md).

## Prerequisites

1. ✅ Infrastructure provisioned via Terraform (VPC, ECS cluster, RDS, ALB)
2. ✅ Docker images pushed to ECR
3. ✅ Database credentials stored in Secrets Manager
4. ✅ IAM roles created (ecsTaskExecutionRole, ecsTaskRole)

## Quick Deploy (5 Steps)

### 1. Configure Variables

```bash
cd terraform/ecs-deployment
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Deploy

```bash
terraform plan
terraform apply
```

### 4. Get ALB DNS

```bash
terraform output
```

### 5. Verify

```bash
# Get ALB DNS name
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || \
  aws elbv2 describe-load-balancers \
    --region ca-central-1 \
    --query 'LoadBalancers[?contains(LoadBalancerName, `food-delivery`)].DNSName' \
    --output text)

# Test health endpoint
curl http://$ALB_DNS/actuator/health
```

## Verify Deployment

```bash
cd ../..
chmod +x scripts/verify-deployment.sh
export AWS_REGION=ca-central-1
export ECS_CLUSTER=food-delivery-dev-cluster
export ALB_DNS=<your-alb-dns-name>
./scripts/verify-deployment.sh
```

## Common Issues

| Issue | Quick Fix |
|-------|-----------|
| Service not starting | Check logs: `aws logs tail /ecs/api-gateway --follow --region ca-central-1` |
| Health check failing | Verify `/actuator/health` is enabled in Spring Boot |
| Database connection error | Check RDS security group allows traffic from backend-services-sg |
| Cannot pull image | Verify ECR image exists and IAM role has ECR permissions |

## Useful Commands

```bash
# Check service status
aws ecs describe-services \
  --cluster food-delivery-dev-cluster \
  --services api-gateway \
  --region ca-central-1 \
  --query 'services[0].{Running:runningCount,Desired:desiredCount}'

# View logs
aws logs tail /ecs/api-gateway --follow --region ca-central-1

# Force new deployment
aws ecs update-service \
  --cluster food-delivery-dev-cluster \
  --service api-gateway \
  --force-new-deployment \
  --region ca-central-1

# Rollback to previous version
aws ecs update-service \
  --cluster food-delivery-dev-cluster \
  --service api-gateway \
  --task-definition api-gateway:1 \
  --region ca-central-1
```

## Architecture

```
Internet → ALB → API Gateway → [User Service, Restaurant Service, Order Service] → RDS
```

- Only ALB is public
- Backend services are private
- Service discovery via AWS Cloud Map
- Database credentials from Secrets Manager

## Next Steps

- [ ] Enable HTTPS on ALB
- [ ] Set up auto-scaling
- [ ] Configure CloudWatch alarms
- [ ] Enable Container Insights

For detailed documentation, see:
- [Complete Deployment Guide](ECS_DEPLOYMENT_GUIDE.md)
- [Deployment Commands Reference](../scripts/deployment-commands.sh)
