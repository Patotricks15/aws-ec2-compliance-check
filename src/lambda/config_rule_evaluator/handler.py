"""Custom AWS Config rule: flags EC2 instances missing a required 'CostCenter' tag.

Invoked hourly by AWS Config (ScheduledNotification) against every EC2 instance
in scope. Reports NON_COMPLIANT/COMPLIANT back to Config via put_evaluations.
"""

import datetime
import json

import boto3

REQUIRED_TAG_KEY = "CostCenter"

config_client = boto3.client("config")
ec2_client = boto3.client("ec2")


def _is_compliant(instance):
    tags = {tag["Key"]: tag["Value"] for tag in instance.get("Tags", [])}
    return REQUIRED_TAG_KEY in tags and bool(tags[REQUIRED_TAG_KEY])


def lambda_handler(event, context):
    invoking_event = json.loads(event["invokingEvent"])
    result_token = event["resultToken"]

    evaluations = []
    paginator = ec2_client.get_paginator("describe_instances")
    for page in paginator.paginate():
        for reservation in page["Reservations"]:
            for instance in reservation["Instances"]:
                compliance_type = "COMPLIANT" if _is_compliant(instance) else "NON_COMPLIANT"
                evaluations.append(
                    {
                        "ComplianceResourceType": "AWS::EC2::Instance",
                        "ComplianceResourceId": instance["InstanceId"],
                        "ComplianceType": compliance_type,
                        "Annotation": f"Requires the '{REQUIRED_TAG_KEY}' tag.",
                        "OrderingTimestamp": invoking_event.get(
                            "notificationCreationTime", datetime.datetime.utcnow().isoformat()
                        ),
                    }
                )

    if evaluations:
        config_client.put_evaluations(Evaluations=evaluations, ResultToken=result_token)

    return {"evaluations": len(evaluations)}
