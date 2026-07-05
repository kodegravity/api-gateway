# ECS Deployment Checklist

Use this checklist to ensure all prerequisites are met and deployment is successful.

---

## ✅ Pre-Deployment Checklist

### Infrastructure Prerequisites

- [ ] **VPC Created**
  - [ ] Public subnets (minimum 2 for ALB)
  - [ ] Private subnets (minimum 2 for ECS tasks)
  - [ ] Internet Gateway attached
  - [ ] NAT Gateway in public subnet
  - [ ] Route tables configured

- [ ] **ECS Cluster Created**
  - [ ] Cluster name: `food-delivery-dev-cluster`
  - [ ] Cluster type: EC2 Linux + Networking (for Fargate)

- [ ] **Application Load Balancer**
  - [ ] ALB created in public subnets
  - [ ] HTTP listener on port 80
  - [ ] Security group allows inbound on port 80
  - [ ] (Optional) HTTPS listener on port 443 with ACM certificate

- [ ] **PostgreSQL RDS**
  - [ ] Database instance created
  - [ ] Endpoint noted
  - [ ] Database name created (e.g., `fooddelivery`)
  - [ ] In private subnet
  - [ ] Security group configured

- [ ] **ECR Repositories**
  - [ ] `api-gateway` repository created
  - [ ] `user-service` repository created
  - [ ] `restaurant-service` repository created
  - [ ] `order-service` repository created

- [ ] **IAM Roles**
  - [ ] `ecsTaskExecutionRole` created with policies:
    - [ ] ECR pull permissions
    - [ ] CloudWatch logs permissions
    - [ ] Secrets Manager read permissions
  - [ ] `ecsTaskRole` created with policies:
    - [ ] SSM permissions (for ECS Exec)

- [ ] **Secrets Manager**
  - [ ] Secret created: `food-delivery/database`
  - [ ] Contains `username` and `password` keys
  - [ ] Secret ARN noted

- [ ] **CloudWatch Log Groups** (optional, Terraform will create)
  - [ ] `/ecs/api-gateway`
  - [ ] `/ecs/user-service`
  - [ ] `/ecs/restaurant-service`
  - [ ] `/ecs/order-service`

---

## 🐳 Docker Images

- [ ] **Build and Push Images**
  - [ ] api-gateway Docker image built
  - [ ] api-gateway image pushed to ECR
  - [ ] user-service Docker image built
  - [ ] user-service image pushed to ECR
  - [ ] restaurant-service Docker image built
  - [ ] restaurant-service image pushed to ECR
  - [ ] order-service Docker image built
  - [ ] order-service image pushed to ECR

**Verify images in ECR:**
```bash
aws ecr list-images --repository-name api-gateway --region ca-central-1
aws ecr list-images --repository-name user-service --region ca-central-1
aws ecr list-images --repository-name restaurant-service --region ca-central-1
aws ecr list-images --repository-name order-service --region ca-central-1
```

---

## 🔧 Terraform Configuration

- [ ] **Copy and Edit terraform.tfvars**
  - [ ] Copied `terraform.tfvars.example` to `terraform.tfvars`
  - [ ] Updated `aws_account_id`
  - [ ] Updated `vpc_id`
  - [ ] Updated `private_subnet_ids`
  - [ ] Updated `public_subnet_ids`
  - [ ] Updated `db_host` (RDS endpoint)
  - [ ] Updated `db_secret_arn`
  - [ ] Updated `alb_arn`
  - [ ] Updated `alb_listener_arn`
  - [ ] Updated `alb_security_group_id`

- [ ] **Verify Terraform Files**
  - [ ] All `.tf` files present in `terraform/ecs-deployment/`
  - [ ] Modules present in `modules/ecs-service/` and `modules/cloudwatch/`

---

## 🚀 Deployment

- [ ] **Initialize Terraform**
  ```bash
  cd terraform/ecs-deployment
  terraform init
  ```

- [ ] **Review Terraform Plan**
  ```bash
  terraform plan
  ```
  - [ ] Review resources to be created (~18 resources)
  - [ ] Verify no unexpected changes

- [ ] **Apply Terraform**
  ```bash
  terraform apply
  ```
  - [ ] Type `yes` when prompted
  - [ ] Wait for completion (~5-10 minutes)

- [ ] **Note Outputs**
  ```bash
  terraform output
  ```
  - [ ] ALB DNS name noted
  - [ ] Service names confirmed

---

## ✅ Post-Deployment Verification

### Check ECS Services

- [ ] **Verify Services are Running**
  ```bash
  aws ecs describe-services \
    --cluster food-delivery-dev-cluster \
    --services api-gateway user-service restaurant-service order-service \
    --region ca-central-1 \
    --query 'services[*].{Name:serviceName,Running:runningCount,Desired:desiredCount}'
  ```
  - [ ] api-gateway: Running 1, Desired 1
  - [ ] user-service: Running 1, Desired 1
  - [ ] restaurant-service: Running 1, Desired 1
  - [ ] order-service: Running 1, Desired 1

### Check Tasks

- [ ] **List Running Tasks**
  ```bash
  aws ecs list-tasks \
    --cluster food-delivery-dev-cluster \
    --service-name api-gateway \
    --region ca-central-1
  ```
  - [ ] At least 1 task ARN returned

- [ ] **Describe Task**
  ```bash
  TASK_ARN=$(aws ecs list-tasks --cluster food-delivery-dev-cluster --service-name api-gateway --region ca-central-1 --query 'taskArns[0]' --output text)
  
  aws ecs describe-tasks \
    --cluster food-delivery-dev-cluster \
    --tasks $TASK_ARN \
    --region ca-central-1
  ```
  - [ ] Last status: RUNNING
  - [ ] Health status: HEALTHY

### Check ALB Target Group

- [ ] **Check Target Health**
  ```bash
  TG_ARN=$(aws elbv2 describe-target-groups --names api-gateway-tg --region ca-central-1 --query 'TargetGroups[0].TargetGroupArn' --output text)
  
  aws elbv2 describe-target-health \
    --target-group-arn $TG_ARN \
    --region ca-central-1
  ```
  - [ ] All targets show state: healthy

### Test Endpoints

- [ ] **Get ALB DNS Name**
  ```bash
  ALB_DNS=$(terraform output -raw alb_dns_name)
  echo $ALB_DNS
  ```

- [ ] **Test Health Endpoint**
  ```bash
  curl http://$ALB_DNS/actuator/health
  ```
  - [ ] Response: `{"status":"UP"}`

- [ ] **Test API Endpoints** (adjust paths based on your API)
  ```bash
  curl http://$ALB_DNS/api/users
  curl http://$ALB_DNS/api/restaurants
  curl http://$ALB_DNS/api/orders
  ```
  - [ ] Responses received (even if empty arrays)

### Check CloudWatch Logs

- [ ] **View api-gateway Logs**
  ```bash
  aws logs tail /ecs/api-gateway --region ca-central-1
  ```
  - [ ] Logs are being generated

- [ ] **View user-service Logs**
  ```bash
  aws logs tail /ecs/user-service --region ca-central-1
  ```
  - [ ] No database connection errors
  - [ ] Application started successfully

- [ ] **Check for Errors**
  ```bash
  aws logs filter-log-events \
    --log-group-name /ecs/api-gateway \
    --filter-pattern "ERROR" \
    --region ca-central-1
  ```
  - [ ] No critical errors

### Verify Service Discovery

- [ ] **List Service Discovery Services**
  ```bash
  NAMESPACE_ID=$(aws servicediscovery list-namespaces --region ca-central-1 --query 'Namespaces[?Name==`local`].Id' --output text)
  
  aws servicediscovery list-services \
    --filters Name=NAMESPACE_ID,Values=$NAMESPACE_ID \
    --region ca-central-1
  ```
  - [ ] user-service registered
  - [ ] restaurant-service registered
  - [ ] order-service registered

---

## 🔒 Security Verification

- [ ] **Verify Backend Services are Private**
  - [ ] Backend services do NOT have public IP addresses
  - [ ] Cannot access backend services directly from internet

- [ ] **Verify Security Groups**
  ```bash
  aws ec2 describe-security-groups \
    --group-names api-gateway-sg backend-services-sg \
    --region ca-central-1
  ```
  - [ ] api-gateway-sg allows inbound from ALB only
  - [ ] backend-services-sg allows inbound from api-gateway-sg only

- [ ] **Verify RDS Security Group**
  - [ ] RDS security group allows inbound from backend-services-sg
  - [ ] (If not, see docs/RDS_SECURITY_GROUP_UPDATE.md)

- [ ] **Verify Secrets Manager Access**
  ```bash
  aws secretsmanager get-secret-value \
    --secret-id food-delivery/database \
    --region ca-central-1
  ```
  - [ ] Secret can be retrieved
  - [ ] Contains username and password

---

## 🎯 Optional Enhancements

- [ ] **Enable HTTPS**
  - [ ] ACM certificate requested and validated
  - [ ] HTTPS listener added to ALB
  - [ ] HTTP to HTTPS redirect configured

- [ ] **Set Up Auto-Scaling**
  - [ ] Target tracking scaling policies configured
  - [ ] Min/Max capacity set

- [ ] **Configure CloudWatch Alarms**
  - [ ] High CPU alarm
  - [ ] High memory alarm
  - [ ] Unhealthy target alarm
  - [ ] SNS topic for notifications

- [ ] **Enable Container Insights**
  ```bash
  aws ecs update-cluster-settings \
    --cluster food-delivery-dev-cluster \
    --settings name=containerInsights,value=enabled \
    --region ca-central-1
  ```

- [ ] **Set Up Monitoring Dashboard**
  - [ ] CloudWatch dashboard created
  - [ ] Key metrics added

---

## 🐛 Troubleshooting

If any check fails, see:
- [ECS Deployment Guide - Troubleshooting](docs/ECS_DEPLOYMENT_GUIDE.md#troubleshooting)
- [Deployment Commands Reference](scripts/deployment-commands.sh)

Common issues:
- **Service not starting**: Check CloudWatch logs
- **Health check failing**: Verify `/actuator/health` endpoint
- **Database errors**: Check RDS security group and Secrets Manager
- **Cannot pull image**: Verify ECR repository and IAM permissions

---

## ✅ Deployment Complete!

Once all checks pass:

1. ✅ All 4 services are running
2. ✅ Health checks are passing
3. ✅ ALB is forwarding traffic
4. ✅ Backend services can connect to database
5. ✅ CloudWatch logs are collecting data
6. ✅ Security groups are properly configured

**Your microservices are now deployed on AWS ECS Fargate!** 🎉

---

## 📝 Next Steps

1. Set up CI/CD pipeline for automated deployments
2. Configure auto-scaling policies
3. Enable CloudWatch alarms
4. Set up production environment
5. Implement blue/green deployments
6. Add distributed tracing (AWS X-Ray)

---

**Checklist Version:** 1.0  
**Last Updated:** July 2026
