# ---------------------------------------
# S3 Gateway Endpoint
# ---------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  # Associate endpoint with private route table
  route_table_ids = [
    aws_route_table.private.id
  ]

  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}

# ---------------------------------------
# DynamoDB Gateway Endpoint
# ---------------------------------------

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"

  # Associate endpoint with private route table
  route_table_ids = [
    aws_route_table.private.id
  ]

  tags = {
    Name = "${var.project_name}-dynamodb-endpoint"
  }
}
