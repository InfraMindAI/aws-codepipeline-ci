output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "private_subnet_ids" {
  value = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
}
