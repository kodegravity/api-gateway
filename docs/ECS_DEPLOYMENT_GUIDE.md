# Food Delivery Microservices - AWS ECS Fargate Deployment

Complete deployment guide for deploying Spring Boot microservices to AWS ECS Fargate with Application Load Balancer, RDS PostgreSQL, and AWS Secrets Manager.

---

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Deployment Flow](#deployment-flow)
- [Directory Structure](#directory-structure)
- [Configuration](#configuration)
- [Deployment Steps](#deployment-steps)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Security Best Practices](#security-best-practices)
- [Monitoring](#monitoring)
- [Rollback Strategy](#rollback-strategy)

---

## 🏗️ Architecture Overview

```
                                  Internet
                                     │
                                     ▼
                            ┌────────────────┐
                            │  Application   │
                            │  Load Balancer │
                            │   (Port 80)    │
                            └────────┬───────┘
                                     │
                                     ▼
                            ┌────────────────┐
                            │  API Gateway   │
                            │  (Port 8080)   │
                            │  ECS Fargate   │
                            └────────┬───────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
                    ▼                ▼                ▼
            ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
            │User Service  │ │Restaurant Svc│ │Order Service │
            │ (Port 8081)  │ │ (Port 8082)  │ │ (Port 8083)  │
            │ ECS Fargate  │ │ ECS Fargate  │ │ ECS Fargate  │
            └──────┬───────┘ └──────┬───────┘ └──────┬───────┘
                   │                │                │
                   └────────────────┼────────────────┘
                                    │
                                    ▼
                            ┌────────────────┐
                            │   PostgreSQL   │
                            │      RDS       │
                            └────────────────┘
                                    │
                                    ▼
                            ┌────────────────┐
                            │Secrets Manager │
                            │ (DB Credentials)│
                            └────────────────┘
```

### Components

#### **Frontend Layer**
- **Application Load Balancer**: Routes HTTP traffic to API Gateway
- **Security**: Only ALB is publicly accessible

#### **API Layer**
- **api-gateway**: Entry point for all client requests (Port 8080)
- Registered with ALB target group
- Routes requests to backend services via Service Discovery

#### **Backend Services (Private)**
- **user-service**: Manages user accounts and authentication (Port 8081)
- **restaurant-service**: Handles restaurant data (Port 8082)
- **order-service**: Processes orders (Port 8083)
- All connect to shared PostgreSQL RDS
- Use AWS Cloud Map for service discovery

#### **Data Layer**
- **PostgreSQL RDS**: Shared database in private subnet
- **Secrets Manager**: Stores database credentials securely

#### **Observability**
- **CloudWatch Logs**: Centralized logging for all services
- **CloudWatch Metrics**: Service and task metrics
- **ECS Service Discovery**: Internal DNS resolution

---

## ✅ Prerequisites

### 1. Infrastructure Requirements

You must have already provisioned via Terraform:

- ✅ VPC with public and private subnets
- ✅ Internet Gateway and NAT Gateway
- ✅ ECS Cluster (`food-delivery-dev-cluster`)
- ✅ Application Load Balancer
- ✅ PostgreSQL RDS instance
- ✅ ECR repositories for each service
- ✅ Security groups (base configuration)
- ✅ CloudWatch log groups
- ✅ IAM roles (`ecsTaskExecutionRole`, `ecsTaskRole`)
- ✅ Secrets Manager secret for database credentials

### 2. Required IAM Roles

**ecsTaskExecutionRole** (allows ECS to pull images and secrets):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "*"
    }
  ]
}
```

**ecsTaskRole** (allows containers to call AWS services):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ],
      "Resource": "*"
    }
  ]
}
```

### 3. Secrets Manager Configuration

Create a secret with database credentials:

```bash
aws secretsmanager create-secret \
  --name food-delivery/database \
  --description "Database credentials for food delivery app" \
  --secret-string '{
    "username": "fooddelivery_admin",
    "password": "YourSecurePassword123!"
  }' \
  --region ca-central-1
```

### 4. Docker Images

Ensure all Docker images are pushed to ECR:

```bash
# Example for api-gateway
aws ecr get-login-password --region ca-central-1 | \
  docker login --username AWS --password-stdin 123456789012.dkr.ecr.ca-central-1.amazonaws.com

docker tag api-gateway:latest 123456789012.dkr.ecr.ca-central-1.amazonaws.com/api-gateway:latest
docker push 123456789012.dkr.ecr.ca-central-1.amazonaws.com/api-gateway:latest
```

---

## 📂 Directory Structure

```
.
├── ecs-task-definitions/              # ECS Task Definition JSON files
│   ├── api-gateway-task-definition.json
│   ├── user-service-task-definition.json
│   ├── restaurant-service-task-definition.json
│   └── order-service-task-definition.json
│
├── terraform/ecs-deployment/           # Terraform infrastructure code
│   ├── main.tf                        # Main configuration
│   ├── variables.tf                   # Input variables
│   ├── outputs.tf                     # Output values
│   ├── provider.tf                    # Provider configuration
│   ├── terraform.tfvars.example       # Example variables file
│   │
│   └── modules/                       # Reusable Terraform modules
│       ├── ecs-service/               # ECS service module
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       │
│       └── cloudwatch/                # CloudWatch log groups module
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
│
├── scripts/                           # Deployment and verification scripts
│   ├── verify-deployment.sh          # Automated deployment verification
│   └── deployment-commands.sh        # All AWS CLI commands reference
│
└── docs/
    └── ECS_DEPLOYMENT_GUIDE.md       # This file
```

---

## ⚙️ Configuration

### Step 1: Configure Terraform Variables

Copy the example file and update with your values:

```bash
cd terraform/ecs-deployment
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region     = "ca-central-1"
environment    = "dev"
aws_account_id = "123456789012"  # YOUR AWS ACCOUNT ID

# From your infrastructure Terraform outputs
vpc_id             = "vpc-xxxxxxxxxxxxxxxxx"
private_subnet_ids = ["subnet-xxxxxxxxxxxxxxxxx", "subnet-yyyyyyyyyyyyyyyyy"]
public_subnet_ids  = ["subnet-zzzzzzzzzzzzzzzzz", "subnet-aaaaaaaaaaaaaaaaa"]

ecs_cluster_name = "food-delivery-dev-cluster"

db_host       = "fooddelivery-db.xxxxxxxxxxxx.ca-central-1.rds.amazonaws.com"
db_name       = "fooddelivery"
db_secret_arn = "arn:aws:secretsmanager:ca-central-1:123456789012:secret:food-delivery/database-xxxxxx"

alb_arn               = "arn:aws:elasticloadbalancing:ca-central-1:123456789012:loadbalancer/app/food-delivery-alb/xxxxxx"
alb_listener_arn      = "arn:aws:elasticloadbalancing:ca-central-1:123456789012:listener/app/food-delivery-alb/xxxxxx/yyyyyy"
alb_security_group_id = "sg-xxxxxxxxxxxxxxxxx"

desired_count          = 1
enable_execute_command = true
log_retention_days     = 7
```

### Step 2: Get Infrastructure Outputs

If you used Terraform for infrastructure, get the required values:

```bash
# Navigate to your infrastructure Terraform directory
cd /path/to/infrastructure-terraform

# Get all outputs
terraform output

# Get specific outputs
terraform output -raw vpc_id
terraform output -json private_subnet_ids
terraform output -raw alb_arn
terraform output -raw alb_listener_arn
terraform output -raw rds_endpoint
```

---

## 🚀 Deployment Steps

### Step 1: Initialize Terraform

```bash
cd terraform/ecs-deployment
terraform init
```

### Step 2: Review Deployment Plan

```bash
terraform plan
```

Review the plan to ensure:
- 4 ECS task definitions will be created
- 4 ECS services will be created
- Security groups are correctly configured
- Service discovery namespace is created
- CloudWatch log groups are created
- ALB target group is created and attached

### Step 3: Apply Terraform Configuration

```bash
terraform apply
```

Type `yes` when prompted.

**Expected resources created:**
- 1 Service Discovery namespace (`local`)
- 4 CloudWatch log groups
- 2 Security groups (api-gateway-sg, backend-services-sg)
- 1 ALB target group (api-gateway-tg)
- 1 ALB listener rule
- 4 ECS task definitions
- 4 ECS services
- 3 Service Discovery services (backend services only)

### Step 4: Monitor Deployment

```bash
# Watch service status
watch -n 5 'aws ecs describe-services \
  --cluster food-delivery-dev-cluster \
  --services api-gateway user-service restaurant-service order-service \
  --region ca-central-1 \
  --query "services[*].{Name:serviceName,Running:runningCount,Desired:desiredCount,Status:status}"'
```

Wait until all services show `Running: 1, Desired: 1`.

### Step 5: Get ALB DNS Name

```bash
terraform output -raw alb_dns_name

# Or using AWS CLI
aws elbv2 describe-load-balancers \
  --region ca-central-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `food-delivery`)].DNSName' \
  --output text
```

---

## ✅ Verification

### Automated Verification

Run the verification script:

```bash
chmod +x scripts/verify-deployment.sh
export AWS_REGION=ca-central-1
export ECS_CLUSTER=food-delivery-dev-cluster
export ALB_DNS=<your-alb-dns-name>

./scripts/verify-deployment.sh
```

The script checks:
1. ✅ ECS service status
2. ✅ Task health status
3. ✅ ALB target group health
4. ✅ CloudWatch log groups
5. ✅ Health endpoints

### Manual Verification

#### 1. Check ECS Services

```bash
aws ecs describe-services \
  --cluster food-delivery-dev-cluster \
  --services api-gateway user-service restaurant-service order-service \
  --region ca-central-1 \
  --query 'services[*].{Name:serviceName,Running:runningCount,Desired:desiredCount}'
```

Expected output:
```json
[
  {"Name": "api-gateway", "Running": 1, "Desired": 1},
  {"Name": "user-service", "Running": 1, "Desired": 1},
  {"Name": "restaurant-service", "Running": 1, "Desired": 1},
  {"Name": "order-service", "Running": 1, "Desired": 1}
]
```

#### 2. Check Running Tasks

```bash
# List tasks for api-gateway
aws ecs list-tasks \
  --cluster food-delivery-dev-cluster \
  --service-name api-gateway \
  --region ca-central-1
```

#### 3. Check Target Group Health

```bash
TG_ARN=$(aws elbv2 describe-target-groups \
  --names api-gateway-tg \
  --region ca-central-1 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region ca-central-1
```

Expected: All targets should be `healthy`.

#### 4. Test Health Endpoints

```bash
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --region ca-central-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `food-delivery`)].DNSName' \
  --output text)

# Test API Gateway health
curl http://$ALB_DNS/actuator/health
```

Expected response:
```json
{
  "status": "UP"
}
```

#### 5. View CloudWatch Logs

```bash
# Tail api-gateway logs
aws logs tail /ecs/api-gateway --follow --region ca-central-1

# View user-service logs
aws logs tail /ecs/user-service --follow --region ca-central-1

# Search for errors
aws logs filter-log-events \
  --log-group-name /ecs/api-gateway \
  --filter-pattern "ERROR" \
  --region ca-central-1
```

#### 6. Test API Endpoints

```bash
# Health check
curl http://$ALB_DNS/actuator/health

# Test user service (via API Gateway)
curl http://$ALB_DNS/api/users

# Test restaurant service
curl http://$ALB_DNS/api/restaurants

# Test order service
curl http://$ALB_DNS/api/orders
```

---

## 🔍 Troubleshooting

### Issue 1: Service Not Starting

**Symptoms:**
- Running count stays at 0
- Tasks keep stopping

**Solution:**

1. Check service events:
```bash
aws ecs describe-services \
  --cluster food-delivery-dev-cluster \
  --services api-gateway \
  --region ca-central-1 \
  --query 'services[0].events[0:10]'
```

2. Check task stopped reason:
```bash
TASK_ARN=$(aws ecs list-tasks \
  --cluster food-delivery-dev-cluster \
  --service-name api-gateway \
  --region ca-central-1 \
  --desired-status STOPPED \
  --query 'taskArns[0]' \
  --output text)

aws ecs describe-tasks \
  --cluster food-delivery-dev-cluster \
  --tasks $TASK_ARN \
  --region ca-central-1 \
  --query 'tasks[0].{StoppedReason:stoppedReason,Containers:containers[*].{Name:name,Reason:reason}}'
```

Common causes:
- Container health check failing
- Application crash on startup
- Cannot pull Docker image from ECR
- Database connection failure
- Missing environment variables

### Issue 2: Health Check Failing

**Symptoms:**
- ALB target group shows unhealthy
- Tasks running but not receiving traffic

**Solution:**

1. Check target health:
```bash
TG_ARN=$(aws elbv2 describe-target-groups \
  --names api-gateway-tg \
  --region ca-central-1 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region ca-central-1
```

2. Test health endpoint directly from container:
```bash
# Get task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster food-delivery-dev-cluster \
  --service-name api-gateway \
  --region ca-central-1 \
  --query 'taskArns[0]' \
  --output text)

# Execute command in container
aws ecs execute-command \
  --cluster food-delivery-dev-cluster \
  --task $TASK_ARN \
  --container api-gateway \
  --interactive \
  --command "curl http://localhost:8080/actuator/health" \
  --region ca-central-1
```

3. Check Spring Boot Actuator configuration:
- Ensure `/actuator/health` endpoint is enabled
- Check `application.properties`:
  ```properties
  management.endpoints.web.exposure.include=health,info,metrics
  management.endpoint.health.show-details=always
  ```

### Issue 3: Database Connection Failure

**Symptoms:**
- Backend services crash
- Logs show `Connection refused` or timeout errors

**Solution:**

1. Verify database endpoint:
```bash
aws rds describe-db-instances \
  --region ca-central-1 \
  --query 'DBInstances[*].{DBInstanceIdentifier:DBInstanceIdentifier,Endpoint:Endpoint.Address,Port:Endpoint.Port}'
```

2. Check security group rules:
```bash
# Ensure RDS security group allows traffic from backend-services-sg
aws ec2 describe-security-groups \
  --group-ids <rds-security-group-id> \
  --region ca-central-1 \
  --query 'SecurityGroups[0].IpPermissions'
```

3. Verify Secrets Manager:
```bash
aws secretsmanager get-secret-value \
  --secret-id food-delivery/database \
  --region ca-central-1 \
  --query 'SecretString' \
  --output text
```

4. Test database connection from ECS task:
```bash
aws ecs execute-command \
  --cluster food-delivery-dev-cluster \
  --task $TASK_ARN \
  --container user-service \
  --interactive \
  --command "/bin/sh" \
  --region ca-central-1

# Inside container:
nc -zv <db-endpoint> 5432
```

### Issue 4: Service Discovery Not Working

**Symptoms:**
- API Gateway cannot reach backend services
- DNS resolution fails

**Solution:**

1. Check service discovery namespace:
```bash
aws servicediscovery list-namespaces \
  --region ca-central-1
```

2. List registered services:
```bash
NAMESPACE_ID=$(aws servicediscovery list-namespaces \
  --region ca-central-1 \
  --query 'Namespaces[?Name==`local`].Id' \
  --output text)

aws servicediscovery list-services \
  --filters Name=NAMESPACE_ID,Values=$NAMESPACE_ID \
  --region ca-central-1
```

3. Test DNS resolution from api-gateway:
```bash
aws ecs execute-command \
  --cluster food-delivery-dev-cluster \
  --task $TASK_ARN \
  --container api-gateway \
  --interactive \
  --command "nslookup user-service.local" \
  --region ca-central-1
```

### Issue 5: Cannot Pull Docker Image

**Symptoms:**
- Error: `CannotPullContainerError`

**Solution:**

1. Verify ECR repository exists:
```bash
aws ecr describe-repositories \
  --repository-names api-gateway \
  --region ca-central-1
```

2. Check image exists:
```bash
aws ecr list-images \
  --repository-name api-gateway \
  --region ca-central-1
```

3. Verify IAM role permissions:
```bash
aws iam get-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-name ECRAccess
```

Ensure the role has `ecr:GetAuthorizationToken` and `ecr:BatchGetImage` permissions.

### Issue 6: Out of Memory

**Symptoms:**
- Tasks keep restarting
- Logs show `java.lang.OutOfMemoryError`

**Solution:**

1. Increase memory in task definition:
```hcl
# In main.tf
cpu    = "512"
memory = "1024"  # Increase from 512 to 1024
```

2. Optimize JVM settings in Dockerfile:
```dockerfile
ENTRYPOINT ["java", "-Xmx384m", "-Xms384m", "-jar", "app.jar"]
```

3. Monitor memory usage:
```bash
# CloudWatch Container Insights
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ServiceName,Value=api-gateway Name=ClusterName,Value=food-delivery-dev-cluster \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region ca-central-1
```

---

## 🔒 Security Best Practices

### 1. Network Security

✅ **Implemented:**
- Backend services in private subnets (no public IP)
- Only API Gateway accessible via ALB
- Security groups follow least privilege principle
- Service-to-service communication via private DNS

### 2. Secrets Management

✅ **Implemented:**
- Database credentials in AWS Secrets Manager
- No hardcoded passwords in code or task definitions
- IAM role-based access to secrets

### 3. IAM Roles

✅ **Implemented:**
- Separate execution role and task role
- Minimal permissions for each role
- No long-term credentials

### 4. Additional Recommendations

🔐 **Enable ECR Image Scanning:**
```bash
aws ecr put-image-scanning-configuration \
  --repository-name api-gateway \
  --image-scanning-configuration scanOnPush=true \
  --region ca-central-1
```

🔐 **Enable VPC Flow Logs:**
```bash
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids <vpc-id> \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/food-delivery \
  --region ca-central-1
```

🔐 **Enable ALB Access Logs:**
```hcl
# In ALB Terraform configuration
access_logs {
  bucket  = aws_s3_bucket.alb_logs.id
  enabled = true
}
```

🔐 **Use HTTPS:**
- Add ACM certificate to ALB
- Create HTTPS listener (port 443)
- Redirect HTTP to HTTPS

---

## 📊 Monitoring

### CloudWatch Dashboards

Create a custom dashboard:

```bash
aws cloudwatch put-dashboard \
  --dashboard-name food-delivery-services \
  --dashboard-body file://cloudwatch-dashboard.json \
  --region ca-central-1
```

### Key Metrics to Monitor

1. **ECS Service Metrics:**
   - CPU Utilization
   - Memory Utilization
   - Running task count
   - Pending task count

2. **ALB Metrics:**
   - Request count
   - Target response time
   - HTTP 4xx/5xx errors
   - Healthy host count

3. **RDS Metrics:**
   - Database connections
   - CPU utilization
   - Free storage space
   - Read/Write IOPS

### CloudWatch Alarms

Create alarms for critical metrics:

```bash
# High CPU utilization
aws cloudwatch put-metric-alarm \
  --alarm-name api-gateway-high-cpu \
  --alarm-description "Alert when CPU exceeds 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=ServiceName,Value=api-gateway Name=ClusterName,Value=food-delivery-dev-cluster \
  --region ca-central-1

# Unhealthy target
aws cloudwatch put-metric-alarm \
  --alarm-name api-gateway-unhealthy-target \
  --metric-name UnHealthyHostCount \
  --namespace AWS/ApplicationELB \
  --statistic Average \
  --period 60 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 2 \
  --dimensions Name=TargetGroup,Value=<target-group-arn-suffix> \
  --region ca-central-1
```

### Log Insights Queries

Useful CloudWatch Insights queries:

**Find errors in last hour:**
```sql
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50
```

**API response times:**
```sql
fields @timestamp, @message
| filter @message like /Request processing time/
| parse @message /time=(?<duration>\d+)ms/
| stats avg(duration), max(duration), min(duration) by bin(5m)
```

**Failed database connections:**
```sql
fields @timestamp, @message
| filter @message like /Connection refused/ or @message like /timeout/
| count() by bin(5m)
```

---

## 🔄 Rollback Strategy

### Option 1: Rollback via Terraform

```bash
# Revert to previous commit
git checkout <previous-commit>

# Apply previous configuration
terraform apply
```

### Option 2: Rollback to Previous Task Definition

```bash
# List task definition revisions
aws ecs list-task-definitions \
  --family-prefix api-gateway \
  --region ca-central-1

# Update service to use previous revision
aws ecs update-service \
  --cluster food-delivery-dev-cluster \
  --service api-gateway \
  --task-definition api-gateway:1 \
  --region ca-central-1
```

### Option 3: Rollback via AWS Console

1. Go to ECS → Clusters → food-delivery-dev-cluster
2. Click on the service
3. Click "Update service"
4. Select previous task definition revision
5. Click "Update"

### Emergency Rollback (Scale to Zero)

```bash
# Stop all tasks by scaling to 0
aws ecs update-service \
  --cluster food-delivery-dev-cluster \
  --service api-gateway \
  --desired-count 0 \
  --region ca-central-1

# Fix the issue, then scale back up
aws ecs update-service \
  --cluster food-delivery-dev-cluster \
  --service api-gateway \
  --desired-count 1 \
  --region ca-central-1
```

---

## 🎯 Deployment Flow Summary

```
1. GitHub Actions Pipeline
   ├── Build Spring Boot JAR
   ├── Run Tests
   ├── Build Docker Image
   ├── Push to ECR
   └── Trigger ECS Update

2. ECS Service Update
   ├── Pull new image from ECR
   ├── Start new task with new image
   ├── Wait for health checks to pass
   ├── Register new task with ALB
   └── Stop old task

3. Service Discovery
   ├── Backend services register with Cloud Map
   ├── API Gateway resolves via DNS
   └── Internal communication established

4. Verification
   ├── Check ECS service status
   ├── Verify target group health
   ├── Test health endpoints
   └── Monitor CloudWatch logs
```

---

## 📝 Next Steps

### Production Readiness Checklist

- [ ] Enable HTTPS on ALB with ACM certificate
- [ ] Configure auto-scaling for ECS services
- [ ] Set up CloudWatch alarms and SNS notifications
- [ ] Enable Container Insights
- [ ] Implement distributed tracing (X-Ray)
- [ ] Set up automated backups for RDS
- [ ] Configure Multi-AZ deployment for RDS
- [ ] Implement circuit breakers in API Gateway
- [ ] Add rate limiting
- [ ] Set up CI/CD pipeline with staging environment
- [ ] Document API endpoints (OpenAPI/Swagger)
- [ ] Implement centralized configuration (AWS AppConfig)

### Scaling Considerations

**Horizontal Scaling:**
```bash
# Update desired count
aws ecs update-service \
  --cluster food-delivery-dev-cluster \
  --service api-gateway \
  --desired-count 3 \
  --region ca-central-1
```

**Auto-scaling Policy:**
```hcl
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/${var.ecs_cluster_name}/api-gateway"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_policy" {
  name               = "cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}
```

---

## 🆘 Support and Resources

- **AWS ECS Documentation**: https://docs.aws.amazon.com/ecs/
- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- **Spring Boot on AWS**: https://aws.amazon.com/blogs/opensource/tag/spring-boot/
- **AWS Well-Architected Framework**: https://aws.amazon.com/architecture/well-architected/

---

## 📄 License

This deployment guide is part of the Food Delivery microservices project.

---

**Last Updated:** 2026-07-04
**Version:** 1.0.0
**Author:** DevOps Team
