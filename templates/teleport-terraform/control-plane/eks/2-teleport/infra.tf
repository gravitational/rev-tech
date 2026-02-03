##################################################################################
# AWS BACKEND INFRASTRUCTURE (DYNAMODB & S3)
##################################################################################

resource "aws_dynamodb_table" "teleport_backend" {
  name         = "${var.proxy_address}-backend"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "HashKey"
  range_key    = "FullPath"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  attribute {
    name = "HashKey"
    type = "S"
  }
  attribute {
    name = "FullPath"
    type = "S"
  }
  server_side_encryption {
    enabled = true
  }
  point_in_time_recovery {
    enabled = true
  }
  tags = {
    Name = "${var.proxy_address}-backend"
  }
}

resource "aws_dynamodb_table" "teleport_events" {
  name         = "${var.proxy_address}-events"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "SessionID"
  range_key    = "EventIndex"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  attribute {
    name = "SessionID"
    type = "S"
  }
  attribute {
    name = "EventIndex"
    type = "N"
  }
  attribute {
    name = "CreatedAtDate"
    type = "S"
  }
  attribute {
    name = "CreatedAt"
    type = "N"
  }
  global_secondary_index {
    name            = "timesearch"
    hash_key        = "CreatedAtDate"
    range_key       = "CreatedAt"
    projection_type = "ALL"
  }
  global_secondary_index {
    name            = "timesearchV2"
    hash_key        = "CreatedAtDate"
    range_key       = "CreatedAt"
    projection_type = "ALL"
  }
  server_side_encryption {
    enabled = true
  }
  point_in_time_recovery {
    enabled = true
  }
  ttl {
    enabled        = true
    attribute_name = "Expires"
  }
  lifecycle {
    ignore_changes = [global_secondary_index]
  }
  tags = {
    Name = "${var.proxy_address}-events"
  }
}

resource "aws_s3_bucket" "session_recordings" {
  bucket        = "${var.proxy_address}-session-recordings-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags = {
    Name = "${var.proxy_address}-session-recordings"
  }
}

resource "aws_s3_bucket_versioning" "session_recordings" {
  bucket = aws_s3_bucket.session_recordings.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "session_recordings" {
  bucket = aws_s3_bucket.session_recordings.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "session_recordings" {
  bucket = aws_s3_bucket.session_recordings.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "session_recordings" {
  bucket = aws_s3_bucket.session_recordings.id
  rule {
    id     = "expire-old-recordings"
    status = "Enabled"
    filter {} # Apply to all objects in the bucket
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    expiration {
      days = 365 # Adjust based on compliance requirements
    }
  }
}
