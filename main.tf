/**
 * Creates a lambda function with associated role and policies, which
 * will log to Cloudwatch Logs.
 *
 * Creates the following resources:
 *
 * * Lambda function
 * * IAM role with policy to allow logging to Cloudwatch Logs
 * * Cloudwatch Logs group
 *
 * ## Usage
 *
 * ```hcl
 * module "my_lambda_function" {
 *   source                = "trussworks/lambda/aws"
 *   name                  = "my_app"
 *   job_identifier        = "instance_alpha"
 *   runtime               = "go1.x"
 *   role_policy_arns      = ["${aws_iam_policy.my_app_lambda_policy.arn}"]
 *   s3_bucket             = "my_s3_bucket"
 *   s3_key                = "my_app/1.0/my_app.zip"
 *
 *   subnet_ids            = ["subnet-0123456789abcdef0"]
 *   security_group_ids    = ["sg-0123456789abcdef0"]
 *
 *   source_types          = ["events"]
 *   source_arns           = ["${aws_cloudwatch_event_rule.trigger.arn}"]
 *
 *   env_vars {
 *     VARNAME = "value"
 *   }
 *
 *   tags {
 *     "Service" = "big_app"
 *   }
 *
 * }
 * ```
 */

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals = {
  full_name = "${var.name}-${var.job_identifier}"
}

# This is the IAM policy for letting lambda assume roles.
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Define default policy document for writing to Cloudwatch Logs.
data "aws_iam_policy_document" "logs_policy_doc" {
  statement {
    sid    = "WriteCloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.full_name}:*"]
  }
}

# Create the IAM role for the Lambda instance.
resource "aws_iam_role" "main" {
  name               = "lambda-${local.full_name}"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role.json}"
}

# Attach the logging policy to the above IAM role.
resource "aws_iam_role_policy" "main" {
  name = "lambda-${local.full_name}"
  role = "${aws_iam_role.main.id}"

  policy = "${data.aws_iam_policy_document.logs_policy_doc.json}"
}

# Attach user-provided policies to role defined above.
resource "aws_iam_role_policy_attachment" "user_policy_attach" {
  count      = "${length(var.role_policy_arns)}"
  role       = "${aws_iam_role.main.name}"
  policy_arn = "${var.role_policy_arns[count.index]}"
}

# Cloudwatch Logs
resource "aws_cloudwatch_log_group" "main" {
  name              = "/aws/lambda/${local.full_name}"
  retention_in_days = "${var.cloudwatch_logs_retention_days}"

  tags {
    Name = "${local.full_name}"
  }
}

# Lambda function
resource "aws_lambda_function" "main" {
  depends_on = ["aws_cloudwatch_log_group.main"]

  s3_bucket = "${var.s3_bucket}"
  s3_key    = "${var.s3_key}"

  function_name = "${local.full_name}"
  role          = "${aws_iam_role.main.arn}"
  handler       = "${var.name}"
  runtime       = "${var.runtime}"
  memory_size   = "${var.memory_size}"
  timeout       = "${var.timeout}"

  environment {
    variables = "${var.env_vars}"
  }

  tags = "${var.tags}"

  vpc_config {
    subnet_ids         = "${var.subnet_ids}"
    security_group_ids = "${var.security_group_ids}"
  }
}

# Add lambda permissions for acting on various triggers.
resource "aws_lambda_permission" "allow_source" {
  count = "${length(var.source_types)}"

  statement_id = "AllowExecutionForLambda-${var.source_types[count.index]}"

  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.main.function_name}"

  principal  = "${var.source_types[count.index]}.amazonaws.com"
  source_arn = "${var.source_arns[count.index]}"
}