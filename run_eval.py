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
        "--api-key", default="", help="API key for Bearer authentication (optional)"
    )
    parser.add_argument(
        "--chat-api",
        default="OpenAI ChatCompletions",
        choices=["OpenAI ChatCompletions", "OpenAI Completions"],
        help="API endpoint type (default: OpenAI ChatCompletions)",
    )
    parser.add_argument(
        "--tasks",
        default="mmlu_pro",
        help="Tasks to run, comma-separated (default: mmlu_pro). "
        "Supported: mmlu_pro, gsm_plus, humaneval, ruler",
    )
    parser.add_argument(
        "--task-max-length-json",
        default='{"mmlu_pro":32768,"gsm_plus":32768,"humaneval":16384,"ruler":137216}',
        help="JSON dict of per-task max_length (model_args)",
    )
    parser.add_argument(
        "--task-max-tokens-json",
        default='{"mmlu_pro":2048,"gsm_plus":2048,"humaneval":4096,"ruler":4096}',
        help="JSON dict of per-task max_gen_toks (gen_kwargs)",
    )
    parser.add_argument(
        "--task-temperature-json",
        default='{"mmlu_pro":1.0,"gsm_plus":1.0,"humaneval":1.0,"ruler":1.0}',
        help="JSON dict of per-task temperature (gen_kwargs, default: all 1.0)",
    )
    parser.add_argument(
        "--task-examples-json",
        default='{"ruler":32}',
        help="JSON dict of per-task sample limit (empty value or missing key = full set; default: ruler=32)",
    )
    parser.add_argument(
        "--num-concurrent",
        default="1",
        help="Concurrent requests in model_args (default: 1)",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        help="Logging level for lm-evaluation-harness (default: INFO)",
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
    if args.api_key:
        env["API_KEY"] = args.api_key
    env["MODEL_NAME"] = args.model
    env["LOCAL_MODEL_PATH"] = args.model_path
    env["OUTPUT_BASE"] = output_dir
    env["CHAT_API"] = args.chat_api
    env["TASK_MAX_LENGTH_JSON"] = args.task_max_length_json
    env["TASK_MAX_TOKENS_JSON"] = args.task_max_tokens_json
    env["TASK_TEMPERATURE_JSON"] = args.task_temperature_json
    env["TASK_EXAMPLES_JSON"] = args.task_examples_json
    env["NUM_CONCURRENT"] = args.num_concurrent
    env["LMEVAL_LOG_LEVEL"] = args.log_level

    cmd = ["bash", shell_script, args.tasks]

    print(f"Output directory: {output_dir}")
    print(f"Command: {' '.join(cmd)}")
    print("=" * 60)

    result = subprocess.run(cmd, env=env)

    print(f"Test completed. Output directory: {output_dir}")
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
