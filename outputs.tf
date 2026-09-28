output "config_rule_name" {
  description = "Name of the custom AWS Config rule evaluating EC2 instance compliance."
  value       = aws_config_config_rule.ec2_compliance.name
}

output "event_rule_name" {
  description = "Name of the EventBridge rule reacting to NON_COMPLIANT evaluations."
  value       = aws_cloudwatch_event_rule.noncompliant_ec2.name
}

output "ssm_automation_document_name" {
  description = "Name of the SSM Automation document that remediates and notifies."
  value       = aws_ssm_document.remediate_noncompliant_instance.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic the compliance team is subscribed to."
  value       = aws_sns_topic.compliance_notifications.arn
}

output "config_bucket_name" {
  description = "S3 bucket receiving AWS Config configuration snapshots."
  value       = aws_s3_bucket.config_bucket.bucket
}

output "lambda_function_name" {
  description = "Name of the Lambda function backing the custom Config rule."
  value       = aws_lambda_function.config_rule_evaluator.function_name
}
