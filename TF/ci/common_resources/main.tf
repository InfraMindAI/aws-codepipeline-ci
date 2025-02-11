# ----------------------------------------------------------------------------------------------------
# Prerequisites for SVN pipeline module: buckets
# ----------------------------------------------------------------------------------------------------

provider "aws" {
  region = "ca-central-1"
}

terraform {
  backend "local" {
    path = "../../tf_state/ci/common_resources/terraform.tfstate"
  }
}

locals {
  //constants
  build_bucket_name     = #type your build bucket name here, for example: "build-bucket-f9j10-d1d2"
  artifacts_bucket_name = #type your artifacts bucket name here, for example: "artifacts-bucket-f9j10-d1d2"
}

resource "aws_s3_bucket" "build_bucket" {
  bucket = local.build_bucket_name

  versioning {
    enabled = true
  }

  tags = {
    Name = "build_bucket"
  }
}

resource "aws_s3_bucket" "artifacts_bucket" {
  bucket = local.artifacts_bucket_name

  versioning {
    enabled = true
  }

  tags = {
    Name = "artifacts_bucket"
  }
}
