import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
sd = boto3.client("servicediscovery")
autoscaling = boto3.client("autoscaling")

TRANSITION_LAUNCHING = "autoscaling:EC2_INSTANCE_LAUNCHING"
TRANSITION_TERMINATING = "autoscaling:EC2_INSTANCE_TERMINATING"


def handler(event, context):
    logger.info("Event: %s", json.dumps(event))

    detail = event["detail"]
    transition = detail["LifecycleTransition"]
    instance_id = detail["EC2InstanceId"]
    hook_name = detail["LifecycleHookName"]
    asg_name = detail["AutoScalingGroupName"]
    token = detail["LifecycleActionToken"]

    service_id = os.environ["CLOUD_MAP_SERVICE_ID"]
    app_port = os.environ["APP_PORT"]

    try:
        if transition == TRANSITION_LAUNCHING:
            _register(instance_id, service_id, app_port)
            _complete(hook_name, asg_name, token, "CONTINUE")

        elif transition == TRANSITION_TERMINATING:
            _deregister(instance_id, service_id)
            _complete(hook_name, asg_name, token, "CONTINUE")

        else:
            logger.warning("Unknown transition: %s", transition)
            _complete(hook_name, asg_name, token, "CONTINUE")

    except Exception as exc:
        logger.error("Error during %s for %s: %s", transition, instance_id, exc)
        # 시작 실패 시 ABANDON → 인스턴스 폐기 (안전)
        # 종료 실패 시 CONTINUE → 그냥 종료 (좀비 레코드 가능하나 허용)
        result = "ABANDON" if transition == TRANSITION_LAUNCHING else "CONTINUE"
        _complete(hook_name, asg_name, token, result)
        raise


def _register(instance_id: str, service_id: str, app_port: str) -> None:
    resp = ec2.describe_instances(InstanceIds=[instance_id])
    private_ip = resp["Reservations"][0]["Instances"][0]["PrivateIpAddress"]

    sd.register_instance(
        ServiceId=service_id,
        InstanceId=instance_id,
        Attributes={
            "AWS_INSTANCE_IPV4": private_ip,
            "AWS_INSTANCE_PORT": app_port,
            "HEALTH_STATUS": "UNHEALTHY",  # 앱 기동 완료 후 CodeDeploy 훅에서 HEALTHY로 변경
        },
    )
    logger.info("Registered %s (%s:%s) → UNHEALTHY", instance_id, private_ip, app_port)


def _deregister(instance_id: str, service_id: str) -> None:
    sd.deregister_instance(ServiceId=service_id, InstanceId=instance_id)
    logger.info("Deregistered %s from Cloud Map", instance_id)


def _complete(hook_name: str, asg_name: str, token: str, result: str) -> None:
    autoscaling.complete_lifecycle_action(
        LifecycleHookName=hook_name,
        AutoScalingGroupName=asg_name,
        LifecycleActionToken=token,
        LifecycleActionResult=result,
    )
    logger.info("CompleteLifecycleAction: %s → %s", hook_name, result)
