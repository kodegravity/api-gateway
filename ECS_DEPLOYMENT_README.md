# Food Delivery Microservices - AWS ECS Deployment

Complete production-ready deployment solution for Spring Boot microservices on AWS ECS Fargate with Application Load Balancer, PostgreSQL RDS, and AWS Secrets Manager.

[![AWS](https://img.shields.io/badge/AWS-ECS%20Fargate-orange)](https://aws.amazon.com/ecs/)
[![Terraform](https://img.shields.io/badge/Infrastructure-Terraform-purple)](https://www.terraform.io/)
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-3.x-green)](https://spring.io/projects/spring-boot)

---

## 🏗️ Architecture

```
Internet → ALB → API Gateway → [Backend Services] → RDS PostgreSQL
                                      ↓
                            AWS Secrets Manager
```

### Services

| Service | Port | Public | Database | Description |
|---------|------|--------|----------|-------------|
| **api-gateway** | 8080 | ✅ (via ALB) | ❌ | API Gateway, routes to backend services |
| **user-service** | 8081 | ❌ | ✅ | User management and authentication |
| **restaurant-service** | 8082 | ❌ | ✅ | Restaurant catalog and menu management |
| **order-service** | 8083 | ❌ | ✅ | Order processing and management |

**Security:**
- Only API Gateway is accessible via ALB
- Backend services are in private subnets
- Service-to-service communication via AWS Cloud Map
- Database credentials stored in AWS Secrets Manager

---

## 📦 What's Included

This repository contains everything needed to deploy a complete microservices architecture:

### ✅ ECS Task Definitions
- Production-ready JSON files for all 4 services
- Fargate launch type with optimal CPU/Memory
- Health checks via Spring Boot Actuator
- AWS Secrets Manager integration
- CloudWatch logging configuration

### ✅ Terraform Infrastructure
- Modular, reusable Terraform code
- ECS services with Fargate
- Application Load Balancer configuration
- Security groups (least privilege)
- AWS Cloud Map service discovery
- CloudWatch log groups with retention

### ✅ GitHub Actions CI/CD
- Automated Docker builds
- ECR image push
- ECS service updates
- OIDC authentication (no long-lived credentials)

### ✅ Deployment Scripts
- Automated verification script
- AWS CLI commands reference
- Health check testing

### ✅ Comprehensive Documentation
- Complete deployment guide
- Quick start guide
- Troubleshooting guide
- Architecture diagrams
- Security best practices

---

## 🚀 Quick Start

### Prerequisites

1. ✅ AWS infrastructure provisioned (VPC, ECS cluster, RDS, ALB, ECR)
2. ✅ Docker images built and pushed to ECR
3. ✅ Database credentials in AWS Secrets Manager
4. ✅ IAM roles created (ecsTaskExecutionRole, ecsTaskRole)

### Deploy in 5 Minutes

```bash
# 1. Configure Terraform
cd terraform/ecs-deployment
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 2. Initialize and deploy
terraform init
terraform apply

# 3. Get ALB DNS name
terraform output

# 4. Test deployment
ALB_DNS=$(terraform output -raw alb_dns_name)
curl http://$ALB_DNS/actuator/health
```

**Expected response:**
```json
{"status":"UP"}
```

---

## 📁 Project Structure

```
.
├── ecs-task-definitions/           # ECS task definitions (JSON)
├── terraform/ecs-deployment/       # Terraform infrastructure
│   ├── modules/                    # Reusable modules
│   ├── main.tf                     # Main configuration
│   └── variables.tf                # Variables
├── scripts/                        # Deployment scripts
├── docs/                           # Documentation
└── .github/workflows/              # CI/CD pipelines
```

See [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md) for detailed structure.

---

## 📖 Documentation

| Document | Description |
|----------|-------------|
| [ECS Deployment Guide](docs/ECS_DEPLOYMENT_GUIDE.md) | Complete step-by-step deployment guide |
| [Quick Start](docs/QUICK_START.md) | Fast deployment for experienced users |
| [Project Structure](docs/PROJECT_STRUCTURE.md) | Detailed file and resource overview |
| [RDS Security Setup](docs/RDS_SECURITY_GROUP_UPDATE.md) | Configure RDS security group |
| [Deployment Commands](scripts/deployment-commands.sh) | AWS CLI reference |

---

## 🔧 Configuration

### Required Terraform Variables

Create `terraform/ecs-deployment/terraform.tfvars`:

```hcl
aws_region     = "ca-central-1"
aws_account_id = "123456789012"

# From infrastructure Terraform outputs
vpc_id             = "vpc-xxxxx"
private_subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]
public_subnet_ids  = ["subnet-zzzzz", "subnet-aaaaa"]

# ECS
ecs_cluster_name = "food-delivery-dev-cluster"

# Database
db_host       = "fooddelivery-db.xxxxx.ca-central-1.rds.amazonaws.com"
db_name       = "fooddelivery"
db_secret_arn = "arn:aws:secretsmanager:ca-central-1:123456789012:secret:food-delivery/database-xxxxx"

# ALB
alb_arn                = "arn:aws:elasticloadbalancing:ca-central-1:..."
alb_listener_arn       = "arn:aws:elasticloadbalancing:ca-central-1:..."
alb_security_group_id  = "sg-xxxxx"
```

See [terraform.tfvars.example](terraform/ecs-deployment/terraform.tfvars.example) for all options.

---

## ✅ Verification

### Automated Verification

```bash
./scripts/verify-deployment.sh
```

This checks:
- ✅ ECS service status
- ✅ Running task count
- ✅ Task health status
- ✅ ALB target group health
- ✅ CloudWatch log groups
- ✅ Health endpoints

### Manual Verification

```bash
# Check services
aws ecs describe-services \
  --cluster food-delivery-dev-cluster \
  --services api-gateway user-service restaurant-service order-service \
  --region ca-central-1

# Test endpoints
curl http://$ALB_DNS/actuator/health
curl http://$ALB_DNS/api/users
curl http://$ALB_DNS/api/restaurants
curl http://$ALB_DNS/api/orders

# View logs
aws logs tail /ecs/api-gateway --follow --region ca-central-1
```

---

## 🔍 Monitoring

### CloudWatch Logs

```bash
# Tail logs
aws logs tail /ecs/api-gateway --follow --region ca-central-1

# Search for errors
aws logs filter-log-events \
  --log-group-name /ecs/user-service \
  --filter-pattern "ERROR" \
  --region ca-central-1
```

### Key Metrics

- ECS Service: CPU/Memory utilization, task count
- ALB: Request count, response time, error rates
- RDS: Database connections, CPU, storage

---

## 🔒 Security

### Network Security
- ✅ Backend services in private subnets (no public IP)
- ✅ Only API Gateway accessible via ALB
- ✅ Security groups follow least privilege
- ✅ Service-to-service via private DNS

### Secrets Management
- ✅ Database credentials in AWS Secrets Manager
- ✅ No hardcoded passwords
- ✅ IAM role-based access

### IAM
- ✅ Separate execution and task roles
- ✅ Minimal required permissions
- ✅ No long-term credentials

See [Security Best Practices](docs/ECS_DEPLOYMENT_GUIDE.md#security-best-practices) for more.

---

## 🔄 CI/CD Pipeline

GitHub Actions workflow for continuous deployment:

```yaml
# .github/workflows/order-service-deploy.yml
on:
  push:
    branches: [main]
    paths: ['order-service/**']

jobs:
  deploy:
    - Build JAR
    - Run tests
    - Build Docker image
    - Push to ECR
    - Deploy to ECS
```

See [order-service-deploy.yml](.github/workflows/order-service-deploy.yml) for complete pipeline.

---

## 🐛 Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Service not starting | Check logs: `aws logs tail /ecs/api-gateway --follow` |
| Health check failing | Verify `/actuator/health` is enabled |
| Database connection error | Check RDS security group and Secrets Manager |
| Cannot pull Docker image | Verify ECR repository and IAM permissions |

See [Troubleshooting Guide](docs/ECS_DEPLOYMENT_GUIDE.md#troubleshooting) for detailed solutions.

---

## 🔄 Rollback

### Quick Rollback

```bash
# Rollback to previous task definition
aws ecs update-service \
  --cluster food-delivery-dev-cluster \
  --service api-gateway \
  --task-definition api-gateway:1 \
  --region ca-central-1

# Or via Terraform
git checkout <previous-commit>
terraform apply
```

---

## 📊 Cost Estimation

| Resource | Quantity | Monthly Cost |
|----------|----------|--------------|
| ECS Fargate Tasks | 4 | ~$12 |
| Application Load Balancer | 1 | ~$22 |
| CloudWatch Logs | 4 services | ~$1 |
| **Total** (excluding RDS, NAT) | | **~$35** |

*Costs are estimates for ca-central-1 region*

---

## 🎯 Production Checklist

- [ ] Enable HTTPS on ALB with ACM certificate
- [ ] Configure auto-scaling policies
- [ ] Set up CloudWatch alarms
- [ ] Enable Container Insights
- [ ] Implement distributed tracing (X-Ray)
- [ ] Set up automated RDS backups
- [ ] Configure Multi-AZ for RDS
- [ ] Implement rate limiting
- [ ] Add API documentation (Swagger/OpenAPI)
- [ ] Set up staging environment

---

## 📝 Resources Created

This deployment creates the following AWS resources:

- **ECS:** 4 task definitions, 4 services
- **Security Groups:** 2 (api-gateway, backend-services)
- **Service Discovery:** 1 namespace, 3 services
- **CloudWatch:** 4 log groups
- **Load Balancer:** 1 target group, 1 listener rule

**Total:** ~18 AWS resources

---

## 🆘 Support

### Documentation
- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Spring Boot on AWS](https://aws.amazon.com/blogs/opensource/tag/spring-boot/)

### Useful Commands

```bash
# Service status
aws ecs describe-services --cluster food-delivery-dev-cluster --services api-gateway --region ca-central-1

# Force new deployment
aws ecs update-service --cluster food-delivery-dev-cluster --service api-gateway --force-new-deployment --region ca-central-1

# Scale service
aws ecs update-service --cluster food-delivery-dev-cluster --service api-gateway --desired-count 3 --region ca-central-1

# View logs
aws logs tail /ecs/api-gateway --follow --region ca-central-1

# ECS Exec (SSH into container)
aws ecs execute-command --cluster food-delivery-dev-cluster --task <task-arn> --container api-gateway --interactive --command "/bin/sh" --region ca-central-1
```

---

## 📄 License

This project is part of the Food Delivery microservices application.

---

## 🎉 Contributors

- DevOps Team
- Backend Engineering Team

---

**Last Updated:** July 2026  
**Version:** 1.0.0

---

## Next Steps

1. **Review** [ECS Deployment Guide](docs/ECS_DEPLOYMENT_GUIDE.md)
2. **Configure** `terraform.tfvars`
3. **Deploy** with `terraform apply`
4. **Verify** with automated script
5. **Monitor** CloudWatch metrics and logs

Happy Deploying! 🚀
