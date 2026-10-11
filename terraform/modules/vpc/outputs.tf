# roboshop-infra/terraform/modules/vpc/outputs.tf
output "vpc_id" { value = aws_vpc.this.id }
output "vpc_cidr" { value = aws_vpc.this.cidr_block }
output "public_subnet_ids" { value = aws_subnet.public[*].id }
output "private_app_subnet_ids" { value = aws_subnet.app[*].id }
output "private_data_subnet_ids" { value = aws_subnet.data[*].id }
output "app_cidrs" { value = local.app_cidrs }
output "data_cidrs" { value = local.data_cidrs }
output "nat_public_ips" { value = aws_eip.nat[*].public_ip }
