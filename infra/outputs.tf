output "store_url" {
  description = "Public storefront URL - this is what you submit."
  value       = "http://${aws_eip.app.public_dns}/"
}

output "public_ip" {
  description = "Elastic IP of the application server."
  value       = aws_eip.app.public_ip
}

output "ssh_command" {
  description = "SSH into the application server."
  value       = "ssh -i ${var.project}-key.pem ubuntu@${aws_eip.app.public_ip}"
}

output "ssh_private_key_file" {
  description = "Private key written next to the Terraform files."
  value       = local_sensitive_file.key.filename
}

output "db_endpoint" {
  description = "RDS endpoint. Different host from the web server, which is the separation requirement."
  value       = aws_db_instance.app.address
}

output "db_instance_class" {
  description = "RDS class actually provisioned (free-tier evidence)."
  value       = aws_db_instance.app.instance_class
}

output "app_instance_type" {
  description = "EC2 type actually provisioned (free-tier evidence)."
  value       = aws_instance.app.instance_type
}

output "admin_credentials" {
  description = "Back-office sign-in details. Append the admin directory from the summary file."
  value = {
    email    = var.admin_email
    password = var.admin_password
    hint     = "Run: ssh -i ${var.project}-key.pem ubuntu@${aws_eip.app.public_ip} 'cat /root/prestashop-summary.txt'"
  }
  sensitive = true
}

output "next_steps" {
  description = "What to do once apply finishes."
  value       = <<-EOT
    1. Wait 5-10 min for cloud-init, then check progress:
         ssh -i ${var.project}-key.pem ubuntu@${aws_eip.app.public_ip} 'sudo tail -f /var/log/prestashop-install.log'
    2. Read the admin URL and credentials:
         ssh -i ${var.project}-key.pem ubuntu@${aws_eip.app.public_ip} 'sudo cat /root/prestashop-summary.txt'
    3. Open the storefront: http://${aws_eip.app.public_dns}/
  EOT
}
