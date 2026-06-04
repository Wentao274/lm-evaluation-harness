#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys
from datetime import datetime


def parse_args():
    parser = argparse.ArgumentParser(description="Run lm_eval test via shell script")
    parser.add_argument("--tester", required=True, help="Tester name")
    parser.add_argument("--build-number", required=True, help="Build number")
    parser.add_argument("--chip", required=True, help="Chip platform name")
    parser.add_argument("--model", required=True, help="Model service name")
    parser.add_argument("--model-path", required=True, help="Local model path")
    parser.add_argument(
        "--base-url", required=True, help="LLM base URL (e.g., http://127.0.0.1:8080)"
    )
    parser.add_argument(
        "--api-key", required=True, help="API key for Bearer authentication"
    )
    parser.add_argument(
        "--tasks",
        default="mmlu_pro",
        help="Tasks to run, comma-separated (default: mmlu_pro)",
    )
    parser.add_argument(
        "--limit", default="", help="Limit number of samples per task (optional)"
    )
    parser.add_argument(
        "--ruler-limit",
        default="32",
        help="Limit number of samples for ruler task (default: 32)",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    model_dir = args.model.split("/")[-1]
    output_dir = os.path.abspath(
        f"./output/{args.tester}/{args.build_number}/{args.chip}/{model_dir}/{timestamp}"
    )
    os.makedirs(output_dir, exist_ok=True)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    shell_script = os.path.join(script_dir, "lm_eval_test.sh")

    if not os.path.exists(shell_script):
        print(f"Error: Shell script not found at {shell_script}")
        sys.exit(1)

    env = os.environ.copy()
    env["LLM_ADDR"] = args.base_url
    env["API_KEY"] = args.api_key
    env["MODEL_NAME"] = args.model
    env["LOCAL_MODEL_PATH"] = args.model_path
    env["OUTPUT_BASE"] = output_dir
    if args.limit:
        env["LIMIT"] = args.limit
    env["RULER_LIMIT"] = args.ruler_limit

    cmd = ["bash", shell_script, args.tasks]

    print(f"Output directory: {output_dir}")
    print(f"Command: {' '.join(cmd)}")
    print("=" * 60)

    result = subprocess.run(cmd, env=env)

    print(f"Test completed. Output directory: {output_dir}")
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
