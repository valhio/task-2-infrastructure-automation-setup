terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# -----------------------
# 1. Networking
# -----------------------

# Create a VPC (private network in AWS)
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "demo-vpc" }
}

# Internet Gateway (gives Internet access)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "demo-igw" }
}

# Subnet (public subnet where web servers live)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = { Name = "demo-public-subnet" }
}

# Second public subnet (in a different Availability Zone)
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
  tags = { Name = "demo-public-subnet-2" }
}

# Route table so instances can access the Internet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# -----------------------
# 2. Security Groups
# -----------------------

# Allow HTTP from the world (for the Load Balancer)
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Allow HTTP traffic from the ALB to the web servers
resource "aws_security_group" "web_sg" {
  name   = "web-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # BLOCK FOR SSH ACCESS
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["95.87.200.6/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# This means:
# The load balancer can receive HTTP requests from anyone.
# Web servers only accept traffic from the load balancer (for safety).

# Database security group
resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  description = "Allow MySQL access from web servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id] # Allow only from web servers
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "demo-db-sg"
  }
}

# -----------------------
# 3. Database (RDS)
# -----------------------

# RDS Subnet Group - use the same public subnets as EC2
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "demo-db-subnet-group"
  subnet_ids = [aws_subnet.public.id, aws_subnet.public_2.id]

  tags = {
    Name = "demo-db-subnet-group"
  }
}

# MySQL RDS instance - now in the SAME VPC as EC2
resource "aws_db_instance" "demo_db" {
  identifier              = "demo-db"
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  username                = "admin" # Normally you'd store this securely
  password                = "admin123"
  db_name                 = "demo"
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  skip_final_snapshot     = true
  publicly_accessible     = false
  multi_az                = false

  tags = {
    Name = "demo-db"
  }
}

# -----------------------
# 4. Web Servers
# -----------------------

resource "aws_instance" "web" {
  count         = 2                            # Create 2 identical servers
  ami           = var.ami_id                   # Ubuntu image
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name = "terraform-key" 

  # Install a simple web page when it boots up
  user_data = <<-EOF
  #!/bin/bash
  # Update OS and install PHP 8.2 with MySQL driver
  yum update -y
  amazon-linux-extras enable php8.2
  yum clean metadata
  yum install -y httpd php php-mysqli php-mysqlnd
  systemctl enable httpd
  systemctl start httpd

  # -----------------------
  # index.php: lists users, add users, delete users (POST-Redirect-GET)
  # -----------------------
  cat << 'EOPHP' > /var/www/html/index.php
  <?php
  $server_number = "${count.index + 1}";
  $servername = "${aws_db_instance.demo_db.address}";
  $username   = "admin";
  $password   = "admin123";
  $dbname     = "demo";

  $conn = new mysqli($servername, $username, $password, $dbname);
  if ($conn->connect_error) { die("Connection failed: " . $conn->connect_error); }
  if (!$conn->set_charset("utf8mb4")) { die("Error loading charset: " . $conn->error); }

  $message = '';

  // Handle Add User
  if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'add' && !empty($_POST['name'])) {
      $name = $_POST['name'];
      $stmt = $conn->prepare("INSERT INTO users (name) VALUES (?)");
      $stmt->bind_param("s", $name);
      if ($stmt->execute()) {
          header("Location: " . $_SERVER['PHP_SELF'] . "?added=" . urlencode($name));
          exit();
      } else {
          $message = "Error adding user.";
      }
      $stmt->close();
  }

  // Handle Delete User
  if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'delete' && !empty($_POST['id'])) {
      $id = intval($_POST['id']);
      $stmt = $conn->prepare("DELETE FROM users WHERE id = ?");
      $stmt->bind_param("i", $id);
      if ($stmt->execute()) {
          header("Location: " . $_SERVER['PHP_SELF'] . "?deleted=" . $id);
          exit();
      } else {
          $message = "Error deleting user.";
      }
      $stmt->close();
  }

  // Check messages
  if (!empty($_GET['added'])) { $message = "User added: " . htmlspecialchars($_GET['added']); }
  if (!empty($_GET['deleted'])) { $message = "User deleted: ID " . intval($_GET['deleted']); }

  // Fetch all users
  $sql = "SELECT * FROM users";
  $result = $conn->query($sql);
  ?>
  <!DOCTYPE html>
  <html lang="en">
  <head>
      <meta charset="UTF-8">
      <title>Demo Users</title>
      <style>
          body { 
              font-family: Arial, sans-serif; 
              background-color: #f0f2f5; 
              color: #333; 
              margin: 0; 
              padding: 40px 20px; 
              display: flex; 
              justify-content: center; 
          }
          .container { 
              text-align: center; 
              max-width: 700px; 
              width: 100%; 
              background-color: #fff; 
              padding: 20px 30px; 
              box-shadow: 0 4px 10px rgba(0,0,0,0.1); 
              border-radius: 8px;
          }
          h1 { color: #2c3e50; }
          table { border-collapse: collapse; width: 100%; margin: 20px 0; }
          th, td { border: 1px solid #ccc; padding: 8px; text-align: left; }
          th { background-color: #3498db; color: white; }
          tr:nth-child(even) { background-color: #ecf0f1; }
          form { margin-top: 20px; }
          input[type=text] { padding: 6px; width: 60%; max-width: 300px; }
          input[type=submit] { padding: 6px 12px; background-color: #3498db; color: white; border: none; cursor: pointer; }
          input[type=submit]:hover { background-color: #2980b9; }
          .message { margin-top: 10px; font-weight: bold; color: green; }
          .server { margin-bottom: 20px; font-weight: bold; }
          .delete-button { background-color: #e74c3c; }
          .delete-button:hover { background-color: #c0392b; }
      </style>
  </head>
  <body>
      <div class="container">
          <div class="server">Served by: Web Server <?= $server_number ?></div>
          <h1>Users from the Database</h1>

          <?php if ($result && $result->num_rows > 0): ?>
              <table>
                  <tr>
                      <th>ID</th>
                      <th>Name</th>
                      <th>Actions</th>
                  </tr>
                  <?php while($row = $result->fetch_assoc()): ?>
                  <tr>
                      <td><?= $row["id"] ?></td>
                      <td><?= htmlspecialchars($row["name"]) ?></td>
                      <td>
                          <form method="post" style="display:inline;">
                              <input type="hidden" name="id" value="<?= $row['id'] ?>">
                              <input type="hidden" name="action" value="delete">
                              <input type="submit" value="Delete" class="delete-button">
                          </form>
                      </td>
                  </tr>
                  <?php endwhile; ?>
              </table>
          <?php else: ?>
              <p>No users found in the database.</p>
          <?php endif; ?>

          <!-- Add user form -->
          <form method="post" action="">
              <input type="hidden" name="action" value="add">
              <input type="text" name="name" placeholder="Enter new user name" required>
              <input type="submit" value="Create User">
          </form>

          <?php if (!empty($message)): ?>
              <div class="message"><?= $message ?></div>
          <?php endif; ?>
      </div>
  </body>
  </html>
  <?php $conn->close(); ?>
  EOPHP
EOF


tags = {
  Name = "web-server-${count.index + 1}"
}

}
# Explanation:
# count = 2 creates two identical EC2 instances.
# user_data runs a script that installs Apache and serves a tiny HTML page.
# Each server shows a different message (Server 1 or Server 2).

# -----------------------
# 5. Load Balancer
# -----------------------

resource "aws_lb" "app_lb" {
  name               = "demo-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public_2.id]
}

# Target group for web servers
resource "aws_lb_target_group" "web_tg" {
  name     = "demo-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check {
    path = "/"
  }
}

# Register both EC2 instances in the target group
resource "aws_lb_target_group_attachment" "web_attach" {
  count            = 2
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# HTTP listener (connects ALB → target group)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}
# Explanation:
# The ALB listens for HTTP requests on port 80.
# It forwards incoming requests to the target group, which contains the two web servers.
