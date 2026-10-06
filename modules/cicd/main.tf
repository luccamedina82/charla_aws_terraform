data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  build_project_name = "${var.name_prefix}-build"
  pipeline_name      = "${var.name_prefix}-pipeline"
}

# --- Artifacts bucket ------------------------------------------------------

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.name_prefix}-cicd-artifacts-${data.aws_caller_identity.current.account_id}"

  # A propósito: la Fase 9 hace destroy + apply desde cero. Sin esto, un
  # bucket con artifacts adentro bloquea el destroy.
  force_destroy = true

  tags = {
    Name = "${var.name_prefix}-cicd-artifacts"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- CodeStar Connection ----------------------------------------------------
# Nace en PENDING. Autorizarla a mano en la consola es la segunda excepción
# al "sin consola" (estado-actual.md §14) — no es automatizable, el handshake
# OAuth con GitHub lo tiene que confirmar una persona.

resource "aws_codestarconnections_connection" "github" {
  name          = "${var.name_prefix}-github"
  provider_type = "GitHub"

  tags = {
    Name = "${var.name_prefix}-github-connection"
  }
}

# --- CodeBuild ---------------------------------------------------------------

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${var.name_prefix}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json

  tags = {
    Name = "${var.name_prefix}-codebuild-role"
  }
}

data "aws_iam_policy_document" "codebuild_permissions" {
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    # El log group que crea CodeBuild es /aws/codebuild/<proyecto>, con el
    # prefijo /aws. Sin el, el rol no puede crear su propio log stream y el
    # build muere en la fase QUEUED con un CLIENT_ERROR que no menciona los
    # logs como causa raiz.
    resources = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${local.build_project_name}*"]
  }

  statement {
    sid    = "Artifacts"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_role_policy" "codebuild_permissions" {
  name   = "${var.name_prefix}-codebuild-permissions"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild_permissions.json
}

resource "aws_codebuild_project" "this" {
  name         = local.build_project_name
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/standard:7.0"
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = true # necesario: el buildspec corre "docker build"

    environment_variable {
      name  = "REPOSITORY_URI"
      value = var.ecr_repository_url
    }

    environment_variable {
      name  = "CONTAINER_NAME"
      value = var.container_name
    }
  }

  source {
    type = "CODEPIPELINE"
  }

  tags = {
    Name = local.build_project_name
  }
}

# --- CodePipeline --------------------------------------------------------

data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "${var.name_prefix}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json

  tags = {
    Name = "${var.name_prefix}-codepipeline-role"
  }
}

data "aws_iam_policy_document" "codepipeline_permissions" {
  statement {
    sid    = "Artifacts"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:GetBucketVersioning",
    ]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    sid       = "UseConnection"
    effect    = "Allow"
    actions   = ["codestar-connections:UseConnection"]
    resources = [aws_codestarconnections_connection.github.arn]
  }

  statement {
    sid    = "TriggerBuild"
    effect = "Allow"
    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
    ]
    resources = [aws_codebuild_project.this.arn]
  }

  # El deploy provider "ECS" registra una revisión nueva de la task
  # definition con la imagen actualizada y actualiza el servicio. Registrar
  # una task definition exige poder pasar los roles que esa task usa.
  statement {
    sid    = "EcsDeploy"
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",

      # Estas tres no son opcionales aunque no se usen "a simple vista": el
      # deploy provider de ECS lista y describe las tasks para esperar a que
      # el despliegue estabilice, y TagResource lo necesita RegisterTaskDefinition
      # porque la definicion lleva tags. Sin ellas el stage falla con
      # "The provided role does not have sufficient permissions to access ECS",
      # que no dice cual falta.
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:TagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassEcsRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [var.frontend_execution_role_arn, var.frontend_task_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "codepipeline_permissions" {
  name   = "${var.name_prefix}-codepipeline-permissions"
  role   = aws_iam_role.codepipeline.id
  policy = data.aws_iam_policy_document.codepipeline_permissions.json
}

resource "aws_codepipeline" "this" {
  name     = local.pipeline_name
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "${var.github_owner}/${var.github_repo}"
        BranchName       = var.branch
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.this.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ClusterName = var.cluster_name
        ServiceName = var.frontend_service_name
        FileName    = "imagedefinitions.json"
      }
    }
  }

  tags = {
    Name = local.pipeline_name
  }
}

# --- Notificaciones --------------------------------------------------------

resource "aws_codestarnotifications_notification_rule" "pipeline" {
  name        = "${var.name_prefix}-pipeline-notifications"
  resource    = aws_codepipeline.this.arn
  detail_type = "BASIC"

  event_type_ids = [
    "codepipeline-pipeline-pipeline-execution-succeeded",
    "codepipeline-pipeline-pipeline-execution-failed",
  ]

  target {
    address = var.notifications_topic_arn
    type    = "SNS"
  }

  tags = {
    Name = "${var.name_prefix}-pipeline-notifications"
  }
}
