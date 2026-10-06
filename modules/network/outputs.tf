output "vpc_id" {
  description = "ID de la VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs de las subnets públicas, una por AZ"
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas, una por AZ"
  value       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}
