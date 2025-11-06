[![Terraform CI/CD](https://github.com/valhio/task-2-infrastructure-automation-setup/actions/workflows/terraform.yaml/badge.svg)](https://github.com/valhio/task-2-infrastructure-automation-setup/actions/workflows/terraform.yaml)

# Demo Web Application with Load Balancer EC2 and RDS using Terraform on AWS

This repository contains Terraform code to provision a simple **web application stack** on AWS using Infrastructure-as-Code (IaC). The stack includes:

- **2 EC2 web servers** running PHP and Apache  
- **A MySQL RDS database**  
- **An Application Load Balancer (ALB)** to distribute traffic  
- **Security groups and networking** (VPC, subnets, Internet Gateway)
- **S3 + DynamoDB backend** for Terraform remote state & locking
- **GitHub Actions CI/CD pipeline** automating deployment on code changes

The web application allows you to **view users** stored in the database and **add users via a URL parameter**.
<br>
To test the setup, you can go to http://demo-alb-1961873780.us-east-1.elb.amazonaws.com (latest deployment).

---

## Table of Contents

1. [Architecture](#architecture)  
2. [Requirements](#requirements)
3. [Terraform Setup](#terraform-setup)
4. [Application Usage](#application-usage)
5. [Outputs](#outputs)
6. [Continuous Integration / Continuous Deployment (CI/CD)](#continuous-integration--continuous-deployment-cicd)
7. [Security Notes](#security-notes)
---

## Architecture

- **VPC**: A custom Virtual Private Cloud
- **Public subnets**: Used to host the EC2 instances and ALB
- **EC2 Instances**: Two t2.micro instances running Ubuntu 22.04 with Apache and PHP web server
- **ALB**: distributes HTTP traffic across both EC2 instances  
- **RDS**: MySQL 8.0, only accessible from the web servers  
```
          Internet
              |
              |
       ----------------
       |  ALB (HTTP)  |
       ----------------
         /          \
        /            \
---------------  ---------------
 | EC2 Web 1 |    | EC2 Web 2 |
---------------  ---------------
        \            /
         \          /
       ----------------
       |   RDS MySQL  |
       ----------------
```
---

## Requirements

- [Terraform](https://www.terraform.io/downloads.html)  
- AWS account with sufficient permissions to create:  
  - EC2 instances  
  - RDS instances  
  - Security groups, VPCs, subnets, load balancers  

---

## Terraform Setup

1. **Clone the repository**:

```bash
1. git clone https://github.com/valhio/task-2-infrastructure-automation-setup.git
2. cd <repo-directory>
3. terraform apply
Note: user_data in EC2 installs Apache + PHP and creates index.php and add-user.php automatically.
After apply completes, note the ALB DNS name from the outputs.
Also, you may have to wait a few minutes for the EC2 instances to be fully initialized and connected to RDS.
```

## Application Usage
1. **Access the web application**:  
   Open a web browser and navigate to the ALB DNS name (from Terraform outputs). You should see a list of users (could initially be empty).
2. **Add a user**:
    Fill in the "New User Name" field and click "Add User". This will add a new user to the database.

Note: The "Served by" line indicates which web server (1 or 2) served the request. 
Refresh the page multiple times to see requests being served by both web servers.

---

## Outputs

Terraform automatically outputs:

| Name                  | Description                               |
|-----------------------|-------------------------------------------|
| `load_balancer_dns`    | Public URL of your ALB                    |
| `database_endpoint`    | RDS database endpoint                     |
| `database_username`    | RDS database username                     |

---

## Continuous Integration / Continuous Deployment (CI/CD)

This project uses **GitHub Actions** to automatically deploy and manage the entire infrastructure defined in `main.tf` using **Terraform**.
<br>
Whenever a new commit is pushed to the `main` branch, the CI/CD pipeline runs and automatically applies the latest Terraform configuration to AWS.

### What the Pipeline Does

1. **Checks out the repository**
   - Pulls the latest Terraform configuration from the repo.

2. **Sets up Terraform**
   - Uses the official HashiCorp Terraform setup action.

3. **Initializes the backend**
   - Connects to a S3 bucket (for remote Terraform state storage).
   and DynamoDB table (for state locking).

4. **Validates and plans changes**
   - Runs `terraform init`, and `terraform plan` to preview updates.

5. **Applies changes automatically**
   - Executes:
     ```bash
     terraform taint aws_instance.web[0]
     terraform taint aws_instance.web[1]
     terraform apply -auto-approve
     ```
   - This ensures that the web servers always rebuild and deploy the latest PHP updates.

6. **Stores Terraform state remotely**
   - State files are stored in the S3 bucket:
     ```
     my-terraform-state-sap-demo
     ```
     and locked with the DynamoDB table:
     ```
     terraform-locks
     ```

### Environment Configuration

Before using the pipeline, the following **GitHub Secrets** need to be configured in your repository:

| Secret Name | Description |
|--------------|-------------|
| `AWS_ACCESS_KEY_ID` | Access key for the IAM user with Terraform permissions |
| `AWS_SECRET_ACCESS_KEY` | Secret key for the same IAM user |
| `AWS_REGION` | AWS region where infrastructure will be deployed (e.g., `us-east-1`) |

### Terraform State Management

To ensure consistent and reliable infrastructure deployment in both **local** and **CI/CD** environments, this project uses **remote state management** with **Amazon S3** and **DynamoDB**.

### S3 Bucket — Remote State Storage

Terraform stores its state file (`terraform.tfstate`) in an **S3 bucket**.  
This allows all developers and the GitHub Actions pipeline to share a single source of truth for the current infrastructure state.

### DynamoDB Table — State Locking

A DynamoDB table (e.g. terraform-locks) is used to lock the state during terraform apply or terraform plan.
This prevents multiple operations from modifying the infrastructure simultaneously, which could lead to state corruption. The pipeline needs it in order to pass successfully.

---

## Security Notes

- Web servers only accept **HTTP from the ALB** and **SSH from your IP**.  
- RDS is **not publicly accessible**, only web servers can access it.  
- Credentials (`admin/admin123`) are hardcoded for demo purposes; in production, they should be securely managed.
- Use security groups to restrict access to only trusted IPs and ports.
