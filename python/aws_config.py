import os
import subprocess
from typing import Optional, Dict, Tuple


def detect_aws_credentials() -> Tuple[bool, Optional[str]]:
    if os.environ.get("AWS_ACCESS_KEY_ID") and os.environ.get("AWS_SECRET_ACCESS_KEY"):
        return True, "direct_credentials"

    if os.environ.get("AWS_PROFILE"):
        return validate_profile(os.environ["AWS_PROFILE"]), "sso_profile"

    try:
        result = subprocess.run(
            ["aws", "sts", "get-caller-identity"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            return True, "default_profile"
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    return False, None


def validate_profile(profile: str) -> bool:
    try:
        env = os.environ.copy()
        env["AWS_PROFILE"] = profile

        result = subprocess.run(
            ["aws", "sts", "get-caller-identity"],
            capture_output=True,
            text=True,
            timeout=5,
            env=env
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


def refresh_aws_sso(profile: str) -> bool:
    try:
        result = subprocess.run(
            ["aws", "sso", "login", "--profile", profile],
            timeout=60
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


def get_bedrock_config() -> Dict[str, str]:
    config = {}

    region = os.environ.get("AWS_REGION")
    if not region:
        region = "us-east-1"

    config["region"] = region

    model = os.environ.get("ANTHROPIC_MODEL")
    if not model:
        model = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"

    config["model"] = model

    small_model = os.environ.get("ANTHROPIC_SMALL_FAST_MODEL")
    if not small_model:
        small_model = "us.anthropic.claude-3-5-haiku-20241022-v1:0"

    config["small_model"] = small_model

    return config
