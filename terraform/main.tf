terraform {
  cloud {
    organization = "your-organisation"
    workspaces {
      name = "your-workspace"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.63.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.5.0"
    }
  }

  required_version = "~> 1.9.4"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Name  = local.service_name
      Stage = var.stage_name
    }
  }
}

data "archive_file" "create_dist_pkg" {
  source_dir  = local.package_path
  output_path = local.archive_path
  type        = "zip"
  excludes = [
    "**/__pycache__/*"
  ]
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "your-unique-${local.service_name}-lambda-bucket"
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.lambda_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "versioning-bucket-config" {
  depends_on = [aws_s3_bucket_versioning.versioning]

  bucket = aws_s3_bucket.lambda_bucket.id

  rule {
    status = "Enabled"
    id     = "delete_previous_versions"

    noncurrent_version_expiration {
      noncurrent_days = 5
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "lambda_bucket_ownership_controls" {
  bucket = aws_s3_bucket.lambda_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "lambda_bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.lambda_bucket_ownership_controls]

  bucket = aws_s3_bucket.lambda_bucket.id
  acl    = "private"
}

resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.lambda_bucket.id
  key    = "${local.service_name}.zip"
  source = data.archive_file.create_dist_pkg.output_path
  etag   = filemd5(data.archive_file.create_dist_pkg.output_path)

  depends_on = [
    data.archive_file.create_dist_pkg
  ]
}

resource "aws_sns_topic" "canvas_data_2_sync_results" {
  name = var.sns_topic
}

resource "aws_sns_topic_subscription" "canvas_data_2_sync_results_email" {
  count = length(var.subscription_emails)
  topic_arn = aws_sns_topic.canvas_data_2_sync_results.arn
  protocol  = "email"
  endpoint  = var.subscription_emails[count.index]
}

resource "aws_lambda_function" "function" {
  function_name = local.service_name
  description   = "Python function that synchronize canvas-data-2 to our database."
  role          = aws_iam_role.lambda_exec.arn
  handler       = "main.lambda_handler"

  memory_size   = 2048
  architectures = ["x86_64"]
  s3_bucket     = aws_s3_bucket.lambda_bucket.id
  s3_key        = aws_s3_object.lambda_zip.key

  source_code_hash = data.archive_file.create_dist_pkg.output_base64sha256
  timeout          = 900
  runtime          = var.python_runtime

  depends_on = [aws_s3_object.lambda_zip, aws_sns_topic.canvas_data_2_sync_results]

  environment {
    variables = {
      "DAP_API_URL"           = var.dap_api_url,
      "DAP_CLIENT_ID"         = var.dap_client_id,
      "DAP_CLIENT_SECRET"     = var.dap_client_secret,
      "DAP_CONNECTION_STRING" = var.dap_connection_string,
      "TABLES"                = var.tables,
      "SNS_TOPIC_ARN"         = aws_sns_topic.canvas_data_2_sync_results.arn
    }
  }
}

resource "aws_cloudwatch_log_group" "log_group" {
  name              = "/aws/lambda/${aws_lambda_function.function.function_name}"
  retention_in_days = 30
}

resource "aws_iam_role" "lambda_exec" {
  name        = "${local.service_name}-lambda-role"
  description = "Allow lambda to access AWS services or resources."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_sns_publish_policy" {
  name = "${local.service_name}-sns-publish-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "sns:Publish"
        Effect   = "Allow"
        Resource = "${aws_sns_topic.canvas_data_2_sync_results.arn}"
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "weekdays_sync" {
  name                = "${local.service_name}-weekdays-sync"
  description         = "Trigger every weekdays at 8 AM, 12 PM, and 4 PM Perth time."
  schedule_expression = "cron(0 0,4,8 ? * MON-FRI *)"
}

resource "aws_cloudwatch_event_target" "weekdays_sync" {
  rule = aws_cloudwatch_event_rule.weekdays_sync.name
  arn  = aws_lambda_function.function.arn

  depends_on = [
    aws_lambda_function.function
  ]
}

resource "aws_lambda_permission" "allow_event_rule" {
  statement_id  = "AllowExecutionFromCloudWatchEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekdays_sync.arn
}