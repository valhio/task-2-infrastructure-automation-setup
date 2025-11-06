output "load_balancer_dns" {
  value = aws_lb.app_lb.dns_name
  description = "Public URL of your Load Balancer"
}

output "database_endpoint" {
  value = aws_db_instance.demo_db.address
}

output "database_username" {
  value = aws_db_instance.demo_db.username
}
