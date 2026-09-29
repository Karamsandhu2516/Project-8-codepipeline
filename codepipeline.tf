# IAM Role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
    }]
  })
}

# Inline Policy for CodePipeline — covers all three stages
resource "aws_iam_role_policy" "codepipeline_connection_policy" {
  name = "codepipeline-connection-policy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Source: use the GitHub CodeStar connection
      {
        Effect = "Allow"
        Action = [
          "codestar-connections:UseConnection",
          "codeconnections:UseConnection"
        ]
        Resource = "arn:aws:codeconnections:us-east-1:387994677123:connection/b319d139-c4aa-46f4-a4d2-b03d1d7dcce7"
      },
      # Source + Build: read/write artifacts in S3
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          aws_s3_bucket.pipeline_bucket.arn,
          "${aws_s3_bucket.pipeline_bucket.arn}/*"
        ]
      },
      # Build stage: start/poll CodeBuild
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codebuild:StopBuild"
        ]
        Resource = "*"
      },
      # Deploy stage: trigger CodeDeploy
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision"
        ]
        Resource = "*"
      },
      # Deploy stage: register new ECS task definitions
      {
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeServices"
        ]
        Resource = "*"
      },
      # Allow CodePipeline to pass IAM roles to CodeBuild / CodeDeploy
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringEqualsIfExists = {
            "iam:PassedToService" = [
              "codebuild.amazonaws.com",
              "codedeploy.amazonaws.com",
              "ecs-tasks.amazonaws.com"
            ]
          }
        }
      }
    ]
  })
}

# S3 Bucket for Pipeline Artifacts
resource "aws_s3_bucket" "pipeline_bucket" {
  bucket = "node-app-pipeline-artifacts-387994677123"
}

# CodePipeline Resource
resource "aws_codepipeline" "app_pipeline" {
  name     = "node-app-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection" # Or GitHub v2
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = "arn:aws:codeconnections:us-east-1:387994677123:connection/b319d139-c4aa-46f4-a4d2-b03d1d7dcce7"
        FullRepositoryId = "karamsandhu2516/Project-8-codepipeline"
        BranchName       = "main"
    
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
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.app_build.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        ApplicationName     = aws_codedeploy_app.app_codedeploy.name
        DeploymentGroupName = aws_codedeploy_deployment_group.codedeploy_group.deployment_group_name
        TaskDefinitionTemplateArtifact = "build_output"
        AppSpecTemplateArtifact        = "build_output"
        Image1ArtifactName             = "build_output"
        Image1ContainerName            = "IMAGE1_NAME"
      }
    }
  }
}