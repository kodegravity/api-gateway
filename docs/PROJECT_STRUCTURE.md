# ECS Deployment - Complete Project Structure

```
.
├── ecs-task-definitions/                        # ECS Task Definition JSON files
│   ├── api-gateway-task-definition.json         # API Gateway task config (port 8080)
│   ├── user-service-task-definition.json        # User service task config (port 8081)
│   ├── restaurant-service-task-definition.json  # Restaurant service task config (port 8082)
│   └── order-service-task-definition.json       # Order service task config (port 8083)
│
├── terraform/
│   └── ecs-deployment/                          # Terraform for ECS deployment
│       ├── provider.tf                          # AWS provider configuration
│       ├── variables.tf                         # Input variable definitions
│       ├── main.tf                              # Main infrastructure code
│       ├── outputs.tf                           # Output values
│       ├── terraform.tfvars.example             # Example variable values
│       │
│       └── modules/                             # Reusable Terraform modules
│           ├── ecs-service/                     # ECS service module
│           │   ├── main.tf                      # Service and service discovery
│           │   ├── variables.tf                 # Module inputs
│           │   └── outputs.tf                   # Module outputs
│           │
│           └── cloudwatch/                      # CloudWatch logs module
│               ├── main.tf                      # Log group creation
│               ├── variables.tf                 # Module inputs
│               └── outputs.tf                   # Module outputs
│
├── scripts/                                     # Deployment and verification scripts
│   ├── verify-deployment.sh                    # Automated deployment verification
│   └── deployment-commands.sh                  # AWS CLI commands reference
│
├── docs/                                        # Documentation
│   ├── ECS_DEPLOYMENT_GUIDE.md                 # Complete deployment guide
│   ├── QUICK_START.md                          # Quick start guide
│   └── RDS_SECURITY_GROUP_UPDATE.md            # RDS security group setup
│
└── .github/
    └── workflows/
        └── order-service-deploy.yml            # GitHub Actions CI/CD pipeline

Total: 21 files
```

## File Descriptions

### ECS Task Definitions (`ecs-task-definitions/`)

| File | Purpose | Key Configuration |
|------|---------|-------------------|
| `api-gateway-task-definition.json` | API Gateway container config | Port 8080, service URLs, no DB secrets |
| `user-service-task-definition.json` | User service container config | Port 8081, DB connection, Secrets Manager |
| `restaurant-service-task-definition.json` | Restaurant service container config | Port 8082, DB connection, Secrets Manager |
| `order-service-task-definition.json` | Order service container config | Port 8083, DB connection, Secrets Manager |

**Common Features:**
- Fargate launch type
- CPU: 256, Memory: 512
- Health checks via `/actuator/health`
- CloudWatch logging
- IAM roles for execution and task

### Terraform Files (`terraform/ecs-deployment/`)

| File | Purpose | What It Creates |
|------|---------|-----------------|
| `provider.tf` | AWS provider setup | Provider configuration, S3 backend (optional) |
| `variables.tf` | Input variables | All configurable parameters |
| `main.tf` | Main infrastructure | Services, security groups, ALB config, service discovery |
| `outputs.tf` | Output values | Service names, security group IDs, DNS names |
| `terraform.tfvars.example` | Example values | Template for actual tfvars file |

### Terraform Modules

**`modules/ecs-service/`** - Reusable ECS service module
- Creates ECS service with Fargate
- Configures service discovery (Cloud Map)
- Attaches to load balancer (optional)
- Enables ECS Exec for debugging

**`modules/cloudwatch/`** - CloudWatch log group module
- Creates log groups
- Configures retention period
- Applies consistent tagging

### Scripts (`scripts/`)

| Script | Purpose | Usage |
|--------|---------|-------|
| `verify-deployment.sh` | Automated verification | `./verify-deployment.sh` |
| `deployment-commands.sh` | AWS CLI reference | Reference only (not executable) |

### Documentation (`docs/`)

| Document | Purpose | Audience |
|----------|---------|----------|
| `ECS_DEPLOYMENT_GUIDE.md` | Complete deployment guide | All users |
| `QUICK_START.md` | Quick reference | Experienced users |
| `RDS_SECURITY_GROUP_UPDATE.md` | RDS security configuration | DevOps/SRE |

## Resources Created by Terraform

When you run `terraform apply`, these resources are created:

### Networking
- ✅ 1 Service Discovery Namespace (Cloud Map) - `local`
- ✅ 2 Security Groups
  - `api-gateway-sg` - Allows traffic from ALB
  - `backend-services-sg` - Allows traffic from API Gateway

### ECS Resources
- ✅ 4 Task Definitions (api-gateway, user-service, restaurant-service, order-service)
- ✅ 4 ECS Services (all in private subnets)
- ✅ 3 Service Discovery Services (for backend services)

### Load Balancer
- ✅ 1 Target Group - `api-gateway-tg`
- ✅ 1 Listener Rule (forwards all traffic to API Gateway)

### CloudWatch
- ✅ 4 Log Groups
  - `/ecs/api-gateway`
  - `/ecs/user-service`
  - `/ecs/restaurant-service`
  - `/ecs/order-service`

**Total Resources:** ~18 AWS resources

## Traffic Flow

```
User Request
    ↓
Internet Gateway
    ↓
Application Load Balancer (Public Subnet)
    ↓
api-gateway-tg (Target Group)
    ↓
api-gateway ECS Service (Private Subnet, Port 8080)
    ↓
Service Discovery DNS (user-service.local:8081)
    ↓
user-service ECS Service (Private Subnet, Port 8081)
    ↓
PostgreSQL RDS (Private Subnet, Port 5432)
```

## Environment Variables Flow

### API Gateway
```
Environment Variables (Hardcoded):
- USER_SERVICE_URL=http://user-service.local:8081
- RESTAURANT_SERVICE_URL=http://restaurant-service.local:8082
- ORDER_SERVICE_URL=http://order-service.local:8083
```

### Backend Services (user, restaurant, order)
```
Environment Variables (Hardcoded):
- SPRING_DATASOURCE_URL=jdbc:postgresql://<DB_HOST>:5432/<DB_NAME>

Secrets from AWS Secrets Manager:
- SPRING_DATASOURCE_USERNAME (from food-delivery/database:username)
- SPRING_DATASOURCE_PASSWORD (from food-delivery/database:password)
```

## Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Public Subnet                                                │
│  ┌──────────────┐                                           │
│  │     ALB      │ (Internet-facing)                         │
│  │  Port 80     │                                           │
│  └──────┬───────┘                                           │
└─────────┼───────────────────────────────────────────────────┘
          │
┌─────────┼───────────────────────────────────────────────────┐
│ Private │Subnet                                             │
│  ┌──────▼───────┐                                           │
│  │ API Gateway  │ (api-gateway-sg)                          │
│  │  Port 8080   │                                           │
│  └──────┬───────┘                                           │
│         │                                                    │
│  ┌──────▼──────────────────────────────┐                    │
│  │ Backend Services (backend-services-sg)│                  │
│  │  - user-service (8081)               │                  │
│  │  - restaurant-service (8082)         │                  │
│  │  - order-service (8083)              │                  │
│  └──────┬───────────────────────────────┘                   │
│         │                                                    │
│  ┌──────▼───────┐                                           │
│  │  PostgreSQL  │ (rds-sg)                                  │
│  │  Port 5432   │                                           │
│  └──────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
```

## Deployment Workflow

1. **Developer pushes code** → GitHub
2. **GitHub Actions triggered** → Builds JAR, Docker image
3. **Image pushed to ECR** → `<account>.dkr.ecr.ca-central-1.amazonaws.com/<service>:latest`
4. **Terraform deployment** → Creates/updates ECS services
5. **ECS pulls new image** → From ECR
6. **New task starts** → In private subnet
7. **Health checks pass** → Container ready
8. **ALB registers target** → (API Gateway only)
9. **Old task drains** → Stops after new task is healthy
10. **Deployment complete** → New version serving traffic

## Monitoring Stack

```
Application Logs → CloudWatch Logs → CloudWatch Insights
       ↓
ECS Metrics → CloudWatch Metrics → CloudWatch Alarms → SNS → Email/Slack
       ↓
ALB Metrics → CloudWatch Metrics → Dashboards
       ↓
RDS Metrics → CloudWatch Metrics → Performance Insights
```

## Cost Estimation (ca-central-1)

| Resource | Quantity | Monthly Cost (Estimate) |
|----------|----------|-------------------------|
| ECS Fargate Tasks (0.25 vCPU, 0.5 GB) | 4 tasks | ~$12/month |
| Application Load Balancer | 1 | ~$22/month |
| CloudWatch Logs (1 GB) | 4 services | ~$1/month |
| RDS db.t3.micro (shared) | 1 | ~$15/month |
| NAT Gateway | 1 | ~$45/month |
| **Total** | | **~$95/month** |

*Note: Actual costs depend on usage, data transfer, and existing infrastructure.*

## Getting Started

1. **Review Prerequisites** - Ensure infrastructure is provisioned
2. **Configure Variables** - Copy and edit `terraform.tfvars`
3. **Deploy** - Run `terraform apply`
4. **Verify** - Run verification script
5. **Monitor** - Check CloudWatch logs and metrics

For detailed instructions, see [ECS_DEPLOYMENT_GUIDE.md](ECS_DEPLOYMENT_GUIDE.md).
