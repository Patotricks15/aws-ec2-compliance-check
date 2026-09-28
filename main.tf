# ─── S3 bucket: AWS Config delivery channel destination ──────────────────────

resource "aws_s3_bucket" "config_bucket" {
  bucket        = "${local.name_prefix}-config-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = local.common_tags
}

data "aws_caller_identity" "current" {}

# ─── AWS Config: recorder + delivery channel scoped to EC2 instances ─────────

resource "aws_iam_role" "config_recorder" {
  name = "${local.name_prefix}-config-recorder"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "config.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "config_recorder_managed" {
  role       = aws_iam_role.config_recorder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_recorder_s3_delivery" {
  name = "${local.name_prefix}-config-s3-delivery"
  role = aws_iam_role.config_recorder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_bucket.arn
      },
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_config_configuration_recorder" "main" {
  name     = "${local.name_prefix}-recorder"
  role_arn = aws_iam_role.config_recorder.arn

  recording_group {
    all_supported                = false
    include_global_resource_types = false
    resource_types                = ["AWS::EC2::Instance"]
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "${local.name_prefix}-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config_bucket.bucket

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# ─── Lambda: custom Config rule that evaluates EC2 instance compliance ───────

resource "aws_iam_role" "lambda_exec" {
  name = "${local.name_prefix}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_config_evaluate" {
  name = "${local.name_prefix}-lambda-config-evaluate"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "config:PutEvaluations"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "ec2:DescribeInstances"
        Resource = "*"
      }
    ]
  })
}

resource "null_resource" "lambda_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/config_rule_evaluator/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} config_rule_evaluator"
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/config_rule_evaluator/handler.py"
  output_path = "${path.module}/.build/config_rule_evaluator.zip"

  depends_on = [null_resource.lambda_package]
}

resource "aws_lambda_function" "config_rule_evaluator" {
  function_name = "${local.name_prefix}-config-rule-evaluator"
  description   = "Custom AWS Config rule: flags EC2 instances missing the required CostCenter tag"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-config-rule-evaluator" })

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

resource "aws_lambda_permission" "config_invoke" {
  statement_id  = "AllowConfigInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.config_rule_evaluator.function_name
  principal     = "config.amazonaws.com"
}

# ─── AWS Config rule: hourly evaluation of EC2 instances via the Lambda ──────

resource "aws_config_config_rule" "ec2_compliance" {
  name = "${local.name_prefix}-ec2-required-tags"

  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = aws_lambda_function.config_rule_evaluator.arn

    source_detail {
      message_type                = "ScheduledNotification"
      maximum_execution_frequency = var.config_max_execution_frequency
    }
  }

  scope {
    compliance_resource_types = ["AWS::EC2::Instance"]
  }

  depends_on = [
    aws_config_configuration_recorder_status.main,
    aws_lambda_permission.config_invoke,
  ]

  tags = local.common_tags
}

# ─── SNS topic: emails the compliance team when an instance goes NON_COMPLIANT

resource "aws_sns_topic" "compliance_notifications" {
  name = "${local.name_prefix}-notifications"

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "compliance_email" {
  topic_arn = aws_sns_topic.compliance_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ─── Systems Manager Automation: tags the noncompliant instance and notifies ─

resource "aws_iam_role" "ssm_automation" {
  name = "${local.name_prefix}-ssm-automation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ssm.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "ssm_automation_remediate" {
  name = "${local.name_prefix}-ssm-automation-remediate"
  role = aws_iam_role.ssm_automation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags", "ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.compliance_notifications.arn
      }
    ]
  })
}

resource "aws_ssm_document" "remediate_noncompliant_instance" {
  name          = "${local.name_prefix}-remediate-instance"
  document_type = "Automation"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Tags a noncompliant EC2 instance for review and notifies the compliance team via SNS."
    assumeRole    = "{{ AutomationAssumeRole }}"
    parameters = {
      InstanceId = {
        type        = "String"
        description = "EC2 instance flagged as NON_COMPLIANT by AWS Config."
      }
      AutomationAssumeRole = {
        type        = "String"
        description = "IAM role assumed to run this automation."
      }
      SnsTopicArn = {
        type        = "String"
        description = "SNS topic to notify."
        default     = aws_sns_topic.compliance_notifications.arn
      }
    }
    mainSteps = [
      {
        name   = "TagInstanceForReview"
        action = "aws:executeAwsApi"
        inputs = {
          Service = "ec2"
          Api     = "CreateTags"
          Resources = ["{{ InstanceId }}"]
          Tags = [
            { Key = "ComplianceStatus", Value = "NON_COMPLIANT" }
          ]
        }
      },
      {
        name   = "NotifyComplianceTeam"
        action = "aws:executeAwsApi"
        inputs = {
          Service  = "sns"
          Api      = "Publish"
          TopicArn = "{{ SnsTopicArn }}"
          Subject  = "AWS Config: EC2 instance flagged NON_COMPLIANT"
          Message  = "Instance {{ InstanceId }} is missing the required CostCenter tag and was flagged for review."
        }
      }
    ]
  })

  tags = local.common_tags
}

# ─── EventBridge: reacts to Config compliance-change events, runs Automation

resource "aws_iam_role" "eventbridge_ssm" {
  name = "${local.name_prefix}-eventbridge-ssm"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "events.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "eventbridge_start_automation" {
  name = "${local.name_prefix}-eventbridge-start-automation"
  role = aws_iam_role.eventbridge_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:StartAutomationExecution"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.ssm_automation.arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "noncompliant_ec2" {
  name        = "${local.name_prefix}-noncompliant-ec2"
  description = "Fires when AWS Config marks an EC2 instance NON_COMPLIANT."

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      configRuleName          = [aws_config_config_rule.ec2_compliance.name]
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "ssm_remediation" {
  rule     = aws_cloudwatch_event_rule.noncompliant_ec2.name
  arn      = "arn:aws:ssm:${var.aws_region}::automation-definition/${aws_ssm_document.remediate_noncompliant_instance.name}:$DEFAULT"
  role_arn = aws_iam_role.eventbridge_ssm.arn

  input_transformer {
    input_paths = {
      instance_id = "$.detail.resourceId"
    }
    input_template = jsonencode({
      InstanceId           = "<instance_id>"
      AutomationAssumeRole = aws_iam_role.ssm_automation.arn
      SnsTopicArn          = aws_sns_topic.compliance_notifications.arn
    })
  }
}
