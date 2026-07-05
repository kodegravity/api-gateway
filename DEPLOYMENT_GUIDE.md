# Order Service CI/CD Deployment Guide

## Overview
This guide covers the complete setup and usage of the GitHub Actions CI/CD pipeline for the order-service Spring Boot application.

---

## Required GitHub Secrets and Variables

### Secrets (Settings → Secrets and variables → Actions → Secrets)

1. **AWS_ROLE_TO_ASSUME** (Required)
   ```
   Example: arn:aws:iam::123456789012:role/GitHubActionsDeploymentRole
   ```
   - IAM role ARN that GitHub Actions will assume using OIDC
   - Must have trust relationship with GitHub OIDC provider

### Variables (Settings → Secrets and variables → Actions → Variables)

While the pipeline uses hardcoded values for clarity, you can optionally configure:

2. **AWS_ACCOUNT_ID** (Optional - for reference)
   ```
   Example: 123456789012
   ```

3. **AWS_REGION** (Optional - currently hardcoded to ca-central-1)
   ```
   Example: ca-central-1
   ```

---

## Required AWS IAM Role Setup

### Step 1: Create OIDC Identity Provider (One-time setup)

```bash
# Run this once per AWS account
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### Step 2: Create IAM Role with Trust Policy

Create a role named `GitHubActionsDeploymentRole` with this trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_ORG/YOUR_REPO_NAME:*"
        }
      }
    }
  ]
}
```

**Replace:**
- `YOUR_ACCOUNT_ID` with your AWS account ID
- `YOUR_GITHUB_ORG/YOUR_REPO_NAME` with your repository (e.g., `Surinder07/private`)

### Step 3: Attach Required Permissions Policy

Create and attach this inline policy to the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRPermissions",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECSPermissions",
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition",
        "ecs:DescribeTasks",
        "ecs:ListTasks",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::YOUR_ACCOUNT_ID:role/ecsTaskExecutionRole",
        "arn:aws:iam::YOUR_ACCOUNT_ID:role/ecsTaskRole"
      ]
    }
  ]
}
```

**Note:** You can scope down the `Resource: "*"` to specific ARNs for better security.

---

## Required ECS Task Definition File

Create this file at: `order-service/ecs-task-definition.json`

```json
{
  "family": "order-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::YOUR_ACCOUNT_ID:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::YOUR_ACCOUNT_ID:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "order-service",
      "image": "YOUR_ACCOUNT_ID.dkr.ecr.ca-central-1.amazonaws.com/order-service:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "SPRING_PROFILES_ACTIVE",
          "value": "prod"
        },
        {
          "name": "SERVER_PORT",
          "value": "8080"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/order-service",
          "awslogs-region": "ca-central-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "curl -f http://localhost:8080/actuator/health || exit 1"
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

**Important:**
- Replace `YOUR_ACCOUNT_ID` with your AWS account ID
- The `image` value will be replaced by the pipeline during deployment
- Ensure CloudWatch log group `/ecs/order-service` exists
- Add Spring Boot Actuator dependency for health checks

---

## Expected Project Structure

```
api-gateaway/
├── .github/
│   └── workflows/
│       └── order-service-deploy.yml
└── order-service/
    ├── src/
    │   └── main/
    │       └── java/
    ├── Dockerfile
    ├── pom.xml
    └── ecs-task-definition.json
```

### Sample Dockerfile

Create at: `order-service/Dockerfile`

```dockerfile
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# Copy the JAR file
COPY target/*.jar app.jar

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
```

---

## How to Test the Pipeline

### 1. Pre-deployment Verification

```bash
# Verify AWS infrastructure exists
aws ecs describe-clusters --clusters food-delivery-dev-cluster --region ca-central-1
aws ecs describe-services --cluster food-delivery-dev-cluster --services order-service --region ca-central-1
aws ecr describe-repositories --repository-names order-service --region ca-central-1
```

### 2. Test Local Build

```bash
# Test Maven build locally
cd order-service
mvn clean test
mvn clean package

# Test Docker build locally
docker build -t order-service:test .
docker run -p 8080:8080 order-service:test
```

### 3. Trigger Pipeline

**Automatic Trigger:**
```bash
# Make a change to order-service
cd order-service
echo "# Update" >> README.md
git add .
git commit -m "feat: trigger deployment"
git push origin main
```

**Manual Trigger:**
1. Go to GitHub → Actions tab
2. Select "Order Service CI/CD Pipeline"
3. Click "Run workflow"
4. Select branch: main
5. Click "Run workflow"

### 4. Monitor Deployment

```bash
# Watch GitHub Actions
# Go to: https://github.com/YOUR_ORG/YOUR_REPO/actions

# Monitor ECS service from CLI
watch -n 5 'aws ecs describe-services \
  --cluster food-delivery-dev-cluster \
  --services order-service \
  --region ca-central-1 \
  --query "services[0].events[0:5]"'

# Check running tasks
aws ecs list-tasks \
  --cluster food-delivery-dev-cluster \
  --service-name order-service \
  --region ca-central-1
```

---

## Common Deployment Issues and Debugging

### Issue 1: "AccessDenied" when pushing to ECR

**Symptoms:**
```
Error: denied: User is not authorized to perform: ecr:PutImage
```

**Solutions:**
1. Verify IAM role has ECR permissions
2. Check ECR repository exists:
   ```bash
   aws ecr describe-repositories --repository-names order-service --region ca-central-1
   ```
3. Create repository if missing:
   ```bash
   aws ecr create-repository --repository-name order-service --region ca-central-1
   ```

### Issue 2: "OIDC token verification failed"

**Symptoms:**
```
Error: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

**Solutions:**
1. Verify OIDC provider exists:
   ```bash
   aws iam list-open-id-connect-providers
   ```
2. Check IAM role trust policy includes correct GitHub repository
3. Verify `id-token: write` permission in workflow

### Issue 3: ECS Service fails to stabilize

**Symptoms:**
```
Error: Service failed to reach stable state within 10 minutes
```

**Solutions:**
1. Check ECS service events:
   ```bash
   aws ecs describe-services \
     --cluster food-delivery-dev-cluster \
     --services order-service \
     --region ca-central-1 \
     --query 'services[0].events[0:10]'
   ```

2. Check CloudWatch logs:
   ```bash
   aws logs tail /ecs/order-service --follow --region ca-central-1
   ```

3. Common causes:
   - Health check failing (check `/actuator/health` endpoint)
   - Port mismatch (container vs. target group)
   - Insufficient CPU/memory
   - Environment variable issues
   - Security group blocking traffic

### Issue 4: Maven build fails

**Symptoms:**
```
Error: Tests failed
```

**Solutions:**
1. Check test logs in GitHub Actions output
2. Run tests locally:
   ```bash
   cd order-service
   mvn clean test -X  # debug mode
   ```
3. Skip tests temporarily (not recommended):
   ```yaml
   run: mvn clean package -DskipTests
   ```

### Issue 5: Docker build fails

**Symptoms:**
```
Error: failed to solve: process "/bin/sh -c" did not complete successfully
```

**Solutions:**
1. Verify JAR file exists in target/ directory
2. Check Dockerfile COPY paths
3. Test build locally:
   ```bash
   cd order-service
   mvn clean package
   docker build -t test .
   ```

### Issue 6: Task definition not found

**Symptoms:**
```
Error: Unable to describe task definition
```

**Solutions:**
1. Verify file exists: `order-service/ecs-task-definition.json`
2. Check file path in workflow matches actual location
3. Ensure file is committed to repository
4. Validate JSON syntax:
   ```bash
   cat order-service/ecs-task-definition.json | jq .
   ```

---

## Debugging Commands

### Check GitHub Actions Logs
```bash
# Using GitHub CLI
gh run list --workflow=order-service-deploy.yml
gh run view <run-id> --log
```

### Check ECS Task Status
```bash
# Get task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster food-delivery-dev-cluster \
  --service-name order-service \
  --region ca-central-1 \
  --query 'taskArns[0]' --output text)

# Describe task
aws ecs describe-tasks \
  --cluster food-delivery-dev-cluster \
  --tasks $TASK_ARN \
  --region ca-central-1
```

### Check CloudWatch Logs
```bash
# Tail logs
aws logs tail /ecs/order-service --follow --region ca-central-1

# Filter errors
aws logs filter-log-events \
  --log-group-name /ecs/order-service \
  --filter-pattern "ERROR" \
  --region ca-central-1
```

### Check ECR Images
```bash
# List images in ECR
aws ecr list-images \
  --repository-name order-service \
  --region ca-central-1

# Describe specific image
aws ecr describe-images \
  --repository-name order-service \
  --image-ids imageTag=latest \
  --region ca-central-1
```

---

## Pipeline Optimization Tips

1. **Speed up Maven builds:**
   - The pipeline already uses `cache: 'maven'` in setup-java
   - Dependencies are cached between runs

2. **Parallel testing:**
   ```yaml
   run: mvn test -T 1C  # Use 1 thread per CPU core
   ```

3. **Build matrix for multiple environments:**
   ```yaml
   strategy:
     matrix:
       environment: [dev, staging, prod]
   ```

4. **Add deployment gates:**
   ```yaml
   - name: Manual approval
     uses: trstringer/manual-approval@v1
     with:
       approvers: your-github-username
   ```

---

## Security Best Practices

1. **Use OIDC instead of long-lived credentials** ✅ (Already implemented)
2. **Scope IAM permissions** - Use least privilege
3. **Enable ECR image scanning:**
   ```bash
   aws ecr put-image-scanning-configuration \
     --repository-name order-service \
     --image-scanning-configuration scanOnPush=true \
     --region ca-central-1
   ```
4. **Use secrets for sensitive data** - Never hardcode credentials
5. **Enable VPC Flow Logs** - Monitor network traffic
6. **Use AWS Secrets Manager** - For database credentials

---

## Next Steps

1. ✅ Create GitHub secrets (AWS_ROLE_TO_ASSUME)
2. ✅ Set up AWS IAM role with OIDC trust
3. ✅ Create ECS task definition file
4. ✅ Ensure ECR repository exists
5. ✅ Add Spring Boot Actuator for health checks
6. ✅ Create CloudWatch log group
7. ✅ Test the pipeline with a small change
8. 📊 Set up monitoring and alerts

---

## Support Resources

- **GitHub Actions Docs:** https://docs.github.com/en/actions
- **AWS ECS Docs:** https://docs.aws.amazon.com/ecs/
- **AWS ECR Docs:** https://docs.aws.amazon.com/ecr/
- **Spring Boot Actuator:** https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html

---

## Rollback Strategy

If deployment fails or issues occur:

```bash
# Get previous task definition
aws ecs describe-services \
  --cluster food-delivery-dev-cluster \
  --services order-service \
  --region ca-central-1 \
  --query 'services[0].deployments'

# Rollback to previous revision
aws ecs update-service \
  --cluster food-delivery-dev-cluster \
  --service order-service \
  --task-definition order-service:PREVIOUS_REVISION \
  --region ca-central-1
```

Or use the AWS Console:
1. Go to ECS → Clusters → food-delivery-dev-cluster
2. Click on order-service
3. Click "Update service"
4. Select previous task definition revision
5. Click "Update"
