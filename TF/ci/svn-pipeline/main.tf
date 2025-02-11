# ----------------------------------------------------------------------------------------------------
# This module create templates to build projects, which source code lives in SVN
# ----------------------------------------------------------------------------------------------------

provider "aws" {
  region = local.aws_region
}

terraform {
  backend "local" {
    path = "../../tf_state/ci/svn-pipeline/terraform.tfstate"
  }
}

locals {
  /*
    Please add new SVN project repositories here, for example:
      pipelines = {
        app1 = {},
        app2 = {}
      }
  */
  pipelines = {}

  #constants
  branch                      = "trunk"
  aws_region                  = "ca-central-1"
  aws_account_id              = "1234567890" #add your AWS account id here
  codebuild_project_name      = "svn-codebuild-project"
  common_build_resources_path = "svn_pipelines/common_build_resources.zip"

  #read from state of other modules
  vpc_id               = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids           = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  build_bucket         = data.terraform_remote_state.common_resources.outputs.build_bucket_name
  build_bucket_arn     = "arn:aws:s3:::${local.build_bucket}"
  ecr_repository_url   = data.terraform_remote_state.ecr.outputs.repository_url
  artifacts_bucket_arn = "arn:aws:s3:::${data.terraform_remote_state.common_resources.outputs.artifacts_bucket_name}"
}

# ----------------------------------------------------------------------------------------------------
# DATA
# ----------------------------------------------------------------------------------------------------

data "terraform_remote_state" "vpc" {
  backend = "local"

  config = {
    path = "../../tf_state/vpc/terraform.tfstate"
  }
}

data "terraform_remote_state" "common_resources" {
  backend = "local"

  config = {
    path = "../../tf_state/ci/common_resources/terraform.tfstate"
  }
}

data "terraform_remote_state" "ecr" {
  backend = "local"

  config = {
    path = "../../tf_state/ci/ecr/terraform.tfstate"
  }
}

# ----------------------------------------------------------------------------------------------------
# CODEPIPELINE for trunk, pipelines for brunches will be created by SVN hook
# ----------------------------------------------------------------------------------------------------

resource "aws_codepipeline" "pipelines" {
  for_each = local.pipelines

  name     = "svn-${each.key}-${local.branch}"
  role_arn = aws_iam_role.codepipeline.arn

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        S3Bucket             = local.build_bucket
        S3ObjectKey          = local.common_build_resources_path
        PollForSourceChanges = false
      }
    }
  }

  stage {
    name = "Build"

    action {
      name            = "Build"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = local.codebuild_project_name
        EnvironmentVariables = jsonencode([
          {
            name  = "SOURCE_PROJECT"
            value = each.key
            type  = "PLAINTEXT"
          },
          {
            name  = "SOURCE_BRANCH"
            value = local.branch
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  artifact_store {
    type     = "S3"
    location = local.build_bucket
  }
}

# ----------------------------------------------------------------------------------------------------
# CODEBUILD PROJECT
# ----------------------------------------------------------------------------------------------------

resource "aws_codebuild_project" "project" {
  name          = local.codebuild_project_name
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  environment {
    type                        = "LINUX_CONTAINER"
    image                       = "${local.ecr_repository_url}:latest"
    compute_type                = "BUILD_GENERAL1_SMALL"
    privileged_mode             = true
    image_pull_credentials_type = "SERVICE_ROLE"
  }

  vpc_config {
    vpc_id             = local.vpc_id
    subnets            = local.subnet_ids
    security_group_ids = [aws_security_group.codebuild.id]
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE"]
  }
}

resource "aws_s3_bucket_object" "common_build_resources" {
  bucket = local.build_bucket
  key    = local.common_build_resources_path
  source = "common_build_resources.zip"
}

# ----------------------------------------------------------------------------------------------------
# CODEPIPELINE IAM ROLE
# ----------------------------------------------------------------------------------------------------

resource "aws_iam_role" "codepipeline" {
  name               = "svn-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume_policy.json
}

data "aws_iam_policy_document" "codepipeline_assume_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "codepipeline" {
  role       = aws_iam_role.codepipeline.name
  policy_arn = aws_iam_policy.codepipeline.arn
}

resource "aws_iam_policy" "codepipeline" {
  name   = "svn-codepipeline-policy"
  policy = data.aws_iam_policy_document.codepipeline.json
}

data "aws_iam_policy_document" "codepipeline" {

  #for downloading source in codepipeline source stage, and for saving artifacts
  statement {
    sid    = "S3Access"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning"
    ]

    resources = [
      local.build_bucket_arn,
      "${local.build_bucket_arn}/*"
    ]
  }

  #for allowing CodePipeline to start build on CodeBuild
  statement {
    sid    = "CodeBuildAccess"
    effect = "Allow"

    actions = [
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds"
    ]

    resources = [
      "arn:aws:codebuild:${local.aws_region}:${local.aws_account_id}:project/${local.codebuild_project_name}"
    ]
  }
}

# ----------------------------------------------------------------------------------------------------
# CODEBUILD IAM ROLE
# ----------------------------------------------------------------------------------------------------

resource "aws_iam_role" "codebuild" {
  name               = "svn-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_policy.json
}

data "aws_iam_policy_document" "codebuild_assume_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  role       = aws_iam_role.codebuild.name
  policy_arn = aws_iam_policy.codebuild.arn
}

resource "aws_iam_policy" "codebuild" {
  name   = "svn-codebuild-policy"
  policy = data.aws_iam_policy_document.codebuild.json
}

data "aws_iam_policy_document" "codebuild" {

  #for saving logs to CloudWatch when building project
  statement {
    sid    = "CloudWatchAccess"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:aws:logs:${local.aws_region}:${local.aws_account_id}:log-group:/aws/codebuild/${local.codebuild_project_name}",
      "arn:aws:logs:${local.aws_region}:${local.aws_account_id}:log-group:/aws/codebuild/${local.codebuild_project_name}:*"
    ]
  }

  #for setting up networking of EC2 server, on which project builds
  statement {
    sid    = "EC2Access1"
    effect = "Allow"

    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs"
    ]

    resources = ["*"]
  }

  #for setting up networking of EC2 server, on which project builds
  statement {
    sid    = "EC2Access2"
    effect = "Allow"

    actions = [
      "ec2:CreateNetworkInterfacePermission"
    ]

    resources = [
      "arn:aws:ec2:${local.aws_region}:${local.aws_account_id}:network-interface/*"
    ]
  }

  #for getting SVN credentials
  statement {
    sid    = "ParameterStoreAccess"
    effect = "Allow"

    actions = [
      "ssm:GetParameters"
    ]

    resources = [
      "arn:aws:ssm:${local.aws_region}:${local.aws_account_id}:parameter/build/*"
    ]
  }

  #for publishing Docker image to ECR: log into ECR
  statement {
    sid    = "ECRAccess1"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = [
      "*"
    ]
  }

  #for downloading custom build image & publishing Docker image to ECR
  statement {
    sid    = "ECRAccess2"
    effect = "Allow"

    actions = [
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]

    resources = [
      "arn:aws:ecr:${local.aws_region}:${local.aws_account_id}:repository/*"
    ]
  }

  #for uploading to artifactory S3 bucket
  statement {
    sid    = "S3Access1"
    effect = "Allow"

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${local.artifacts_bucket_arn}/*"
    ]
  }

  #for downloading source and uploading artifact
  statement {
    sid    = "S3Access2"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject"
    ]

    resources = [
      "${local.build_bucket_arn}/*"
    ]
  }

  #for publishing test reports
  statement {
    sid    = "ReportsAccess"
    effect = "Allow"

    actions = [
      "codebuild:CreateReportGroup",
      "codebuild:CreateReport",
      "codebuild:UpdateReport",
      "codebuild:BatchPutTestCases"
    ]

    resources = [
      "arn:aws:codebuild:${local.aws_region}:${local.aws_account_id}:report-group/${local.codebuild_project_name}-CiReports"
    ]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Security Group
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "codebuild" {
  name   = "svn-codebuild-sg"
  vpc_id = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# User for SVN to run commands
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_user" "svn_user" {
  name = "svn-pipelines"
  path = "/ci/"
}

resource "aws_iam_access_key" "key" {
  user = aws_iam_user.svn_user.name
}

resource "aws_iam_user_policy" "user_policy" {
  user   = aws_iam_user.svn_user.name
  policy = data.aws_iam_policy_document.user_policy.json
}

data "aws_iam_policy_document" "user_policy" {

  statement {
    effect = "Allow"

    actions = [
      "codepipeline:CreatePipeline",
      "codepipeline:DeletePipeline",
      "codepipeline:StartPipelineExecution"
    ]

    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["codepipeline.amazonaws.com"]
    }
  }
}
