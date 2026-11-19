# ---------------------------------------
# S3 Artifact Storage
# ---------------------------------------
# Generate a unique suffix for the bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project_name}-artifacts-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "${var.project_name}-artifacts"
  }
}

# Enable bucket versioning
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable S3-managed encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Prevent public access
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------
# DynamoDB Job Tracking
# ---------------------------------------

resource "aws_dynamodb_table" "jobs" {
  name         = "${var.project_name}-jobs"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "job_id"

  attribute {
    name = "job_id"
    type = "S"
  }

  attribute {
    name = "owner_id"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  # Query jobs by owner, newest first
  global_secondary_index {
    name            = "owner-created-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "owner_id"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "created_at"
      key_type       = "RANGE"
    }
  }

  # Query jobs by status
  global_secondary_index {
    name            = "status-created-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "status"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "created_at"
      key_type       = "RANGE"
    }
  }

  # Record item changes for downstream consumers
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = {
    Name = "${var.project_name}-jobs"
  }
}
