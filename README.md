# Demo Web Application with Load Balancer EC2 and RDS using Terraform on AWS

This repository contains Terraform code to provision a simple **web application stack** on AWS using Infrastructure-as-Code (IaC). The stack includes:

- **2 EC2 web servers** running PHP and Apache  
- **A MySQL RDS database**  
- **An Application Load Balancer (ALB)** to distribute traffic  
- **Security groups and networking** (VPC, subnets, Internet Gateway)

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
6. [Security Notes](#security-notes)
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

## Security Notes

- Web servers only accept **HTTP from the ALB** and **SSH from your IP**.  
- RDS is **not publicly accessible**, only web servers can access it.  
- Credentials (`admin/admin123`) are hardcoded for demo purposes; in production, they should be securely managed.
- Use security groups to restrict access to only trusted IPs and ports.
