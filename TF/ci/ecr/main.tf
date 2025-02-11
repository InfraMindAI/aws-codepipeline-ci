# ----------------------------------------------------------------------------------------------------
# Prerequisites for SVN pipeline module: ECR for build image
# ----------------------------------------------------------------------------------------------------

provider "aws" {
  region = "ca-central-1"
}

terraform {
  backend "local" {
    path = "../../tf_state/ci/ecr/terraform.tfstate"
  }
}

resource "aws_ecr_repository" "ecr" {
  name = "build"
}
