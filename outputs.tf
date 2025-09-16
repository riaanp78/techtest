output "nginx_public_dns" {
  description = "Public DNS hostname of the nginx server"
  value       = aws_instance.nginx.public_dns
}

output "nginx_public_ip" {
  description = "Public IP of the nginx server"
  value       = aws_instance.nginx.public_ip
}

output "nginx_private_ip" {
  description = "Private IP of the nginx server"
  value       = aws_instance.nginx.private_ip
}

output "nginx_instance_id" {
  description = "Instance ID of the nginx server"
  value       = aws_instance.nginx.id
}

output "postgres_private_ip" {
  description = "Private IP of the postgres server"
  value       = aws_instance.postgres.private_ip
}

output "postgres_instance_id" {
  description = "Instance ID of the postgres server"
  value       = aws_instance.postgres.id
}


# New descriptive outputs
output "app_location" {
  description = "Path on the nginx instance where the Flask app is deployed"
  value       = "/opt/app/dummyapp"
}

output "app_service_name" {
  description = "Systemd service managing the Flask app"
  value       = "flask-app"
}

output "app_url" {
  description = "HTTP URL to access the Flask app via nginx"
  value       = "http://${aws_instance.nginx.public_dns}"
}
