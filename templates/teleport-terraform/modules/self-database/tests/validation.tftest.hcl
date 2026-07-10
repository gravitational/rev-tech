# Validation tests for modules/self-database
#
# Tests the db_type variable validation block without requiring real credentials.
# Run from the module root: cd modules/self-database && terraform test
#
# Requires Terraform >= 1.7 (mock_provider support).

mock_provider "aws" {}
mock_provider "tls" {}
mock_provider "random" {}
mock_provider "teleport" {}

# Shared variable values for all valid-type runs.
# All required variables must be present for the plan to proceed past validation.
variables {
  env                = "test"
  user               = "test@example.com"
  proxy_address      = "teleport.example.com"
  teleport_version   = "18.0.0"
  teleport_db_ca     = "fake-ca-pem"
  ami_id             = "ami-12345678"
  instance_type      = "t3.small"
  subnet_id          = "subnet-12345678"
  security_group_ids = ["sg-12345678"]
}

run "valid_postgres" {
  variables {
    db_type = "postgres"
  }
  command = plan
}

run "valid_mysql" {
  variables {
    db_type = "mysql"
  }
  command = plan
}

run "valid_mongodb" {
  variables {
    db_type = "mongodb"
  }
  command = plan
}

run "valid_cassandra" {
  variables {
    db_type = "cassandra"
  }
  command = plan
}

run "rejects_invalid_db_type" {
  variables {
    db_type = "oracle"
  }
  command         = plan
  expect_failures = [var.db_type]
}
