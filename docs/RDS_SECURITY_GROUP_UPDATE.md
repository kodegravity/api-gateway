# RDS Security Group Update

You need to update your RDS security group to allow traffic from the backend services security group.

## Option 1: Using AWS CLI

```bash
# Get the RDS security group ID
RDS_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*rds*" \
  --region ca-central-1 \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

# Get the backend services security group ID (created by this Terraform)
BACKEND_SG_ID=$(terraform output -raw backend_services_security_group_id)

# Add ingress rule to RDS security group
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 5432 \
  --source-group $BACKEND_SG_ID \
  --region ca-central-1
```

## Option 2: Update Infrastructure Terraform

Add this to your infrastructure Terraform (where you created RDS):

```hcl
# In your infrastructure Terraform code where RDS is defined

# Import the backend services security group
data "terraform_remote_state" "ecs_deployment" {
  backend = "s3"  # or "local"
  
  config = {
    bucket = "your-terraform-state-bucket"
    key    = "ecs-deployment/terraform.tfstate"
    region = "ca-central-1"
  }
}

# Add ingress rule to RDS security group
resource "aws_security_group_rule" "rds_from_backend_services" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = data.terraform_remote_state.ecs_deployment.outputs.backend_services_security_group_id
  security_group_id        = aws_security_group.rds.id
  description              = "Allow PostgreSQL access from backend services"
}
```

## Option 3: Manual via AWS Console

1. Go to **EC2 Console → Security Groups**
2. Find your RDS security group
3. Click **Inbound rules → Edit inbound rules**
4. Click **Add rule**
5. Configure:
   - Type: PostgreSQL
   - Protocol: TCP
   - Port: 5432
   - Source: Custom → Select `backend-services-sg`
   - Description: "Backend services database access"
6. Click **Save rules**

## Verification

Test database connectivity from a backend service:

```bash
# Get a running task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster food-delivery-dev-cluster \
  --service-name user-service \
  --region ca-central-1 \
  --query 'taskArns[0]' \
  --output text)

# Connect to the container
aws ecs execute-command \
  --cluster food-delivery-dev-cluster \
  --task $TASK_ARN \
  --container user-service \
  --interactive \
  --command "/bin/sh" \
  --region ca-central-1

# Inside the container, test connection
nc -zv <your-rds-endpoint> 5432
# Should output: Connection to <endpoint> 5432 port [tcp/postgresql] succeeded!
```

## Required Rule Summary

| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| PostgreSQL | TCP | 5432 | backend-services-sg | Backend services database access |
