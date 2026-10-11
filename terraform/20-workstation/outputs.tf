# terraform/20-workstation/outputs.tf
output "instance_id" {
  value = aws_instance.ws.id
}

output "instance_type" {
  value = aws_instance.ws.instance_type
}

output "availability_zone" {
  value = aws_instance.ws.availability_zone
}
