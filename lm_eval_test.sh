#!/bin/bash
ROOT_PATH=$(cd `dirname $0`; pwd)

echo $ROOT_PATH
cd ${ROOT_PATH}

CurDate=$(date +'%Y%m%d%H%M%S')

export HF_ENDPOINT=${HF_ENDPOINT:-https://hf-mirror.com}

if [ -z "$LLM_ADDR" ]; then
    ADDR=${ADDR:-127.0.0.1}
    PORT=${PORT:-8080}
    LLM_ADDR="http://$ADDR:$PORT"
fi

API_KEY=${API_KEY:-abc123}
MODEL_NAME=${MODEL_NAME:-kimi-k2.5}
LOCAL_MODEL_PATH=${LOCAL_MODEL_PATH:-"/dingofs/data1/userdata/llms/moonshotai/Kimi-K2.6"}
OUTPUT_BASE=${OUTPUT_BASE:-./output_h100}
LIMIT=${LIMIT:-}
RULER_LIMIT=${RULER_LIMIT:-32}

usage() {
    echo "Usage: $0 [OPTIONS] TASK"
    echo "OPTIONS:"
    echo "  -a, --addr ADDRESS     Server address (default: 127.0.0.1)"
    echo "  -p, --port PORT        Server port (default: 8080)"
    echo "  -k, --api-key KEY      API key (default: abc123)"
    echo "  -l, --llm-addr URL     Full LLM address (overrides addr and port)"
    echo "  -m, --model-name NAME  Model name (default: kimi-k2.5)"
    echo "  -d, --model-path PATH  Local model path"
    echo "  -h, --help             Show this help message"
    echo "TASK:"
    echo "  Task name(s) to run, comma-separated (e.g., mmlu_pro or mmlu_pro,gsm_plus,ruler)"
    echo ""
    echo "Supported tasks:"
    echo "  - mmlu_pro, gsm_plus: run with run_task_other"
    echo "  - ruler: run with run_task_ruler"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--addr)
            ADDR="$2"
            LLM_ADDR="http://$ADDR:$PORT"
            shift 2
            ;;
        -p|--port)
            PORT="$2"
            LLM_ADDR="http://$ADDR:$PORT"
            shift 2
            ;;
        -k|--api-key)
            API_KEY="$2"
            shift 2
            ;;
        -l|--llm-addr)
            LLM_ADDR="$2"
            shift 2
            ;;
        -m|--model-name)
            MODEL_NAME="$2"
            shift 2
            ;;
        -d|--model-path)
            LOCAL_MODEL_PATH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            TASKS="$1"
            shift
            ;;
    esac
done

if [ -z "$TASKS" ]; then
    echo "Error: Task is required"
    usage
fi

# model_args 构造
MODEL_ARGS_BASE_1="{\"model\":\"$MODEL_NAME\",\"base_url\":\"$LLM_ADDR/v1/completions\",\"max_length\":131072,\"tokenizer\":\"$LOCAL_MODEL_PATH\",\"trust_remote_code\":true,\"num_concurrent\":10,\"max_retries\":3,\"timeout\":12000,\"tokenized_requests\":false,\"headers\":{\"Authorization\":\"Bearer $API_KEY\"}}"
MODEL_ARGS_BASE_2="{\"model\":\"$MODEL_NAME\",\"base_url\":\"$LLM_ADDR/v1/completions\",\"max_length\":192512,\"tokenizer\":\"$LOCAL_MODEL_PATH\",\"trust_remote_code\":true,\"num_concurrent\":10,\"max_retries\":3,\"timeout\":12000,\"tokenized_requests\":false,\"headers\":{\"Authorization\":\"Bearer $API_KEY\"}}"

# 运行单个任务的函数
run_task_other() {
	local task_name=$1
	local max_tokens=$2
	local temperature=$3
	local unsafe_code=$4
	
	local do_sample="false"
	[ "$temperature" = "1.0" ] && do_sample="true"

	GEN_KWARGS="{\"max_gen_toks\":$max_tokens,\"do_sample\":$do_sample,\"temperature\":$temperature,\"top_p\":0.95,\"top_k\":40}"

	local unsafe_flag=""
	[ "$unsafe_code" = "true" ] && unsafe_flag="--confirm_run_unsafe_code" && export HF_ALLOW_CODE_EVAL=1
	
	local limit_flag=""
	[ -n "$LIMIT" ] && limit_flag="--limit $LIMIT"
	
	lm_eval \
		--model local-completions \
		--tasks $task_name \
		--output_path ${OUTPUT_BASE}/${task_name} \
		--model_args "$MODEL_ARGS_BASE_1" \
		--batch_size auto \
		--gen_kwargs "$GEN_KWARGS" \
		$limit_flag \
		$unsafe_flag
}


run_task_ruler() {
	local task_name=$1
	local max_tokens=$2
	local temperature=$3
	local unsafe_code=$4
	
	local do_sample="false"
	[ "$temperature" = "1.0" ] && do_sample="true"

	GEN_KWARGS="{\"max_gen_toks\":$max_tokens,\"do_sample\":$do_sample,\"temperature\":$temperature,\"top_p\":0.95,\"top_k\":40}"

	local unsafe_flag=""
	[ "$unsafe_code" = "true" ] && unsafe_flag="--confirm_run_unsafe_code" && export HF_ALLOW_CODE_EVAL=1
	
	local limit_flag="--limit $RULER_LIMIT"
	
	lm_eval \
		--model local-completions \
		--tasks $task_name \
		--output_path ${OUTPUT_BASE}/${task_name} \
		--model_args "$MODEL_ARGS_BASE_2" \
		--batch_size auto \
		--gen_kwargs "$GEN_KWARGS" \
		$limit_flag \
		$unsafe_flag
}

IFS=',' read -ra TASK_LIST <<< "$TASKS"
for task in "${TASK_LIST[@]}"; do
    task=$(echo "$task" | xargs)
    case "$task" in
        mmlu_pro|gsm_plus)
            echo "Running $task with run_task_other"
            run_task_other "$task" 8192 0.0 false
            ;;
        ruler)
            echo "Running $task with run_task_ruler"
            run_task_ruler "$task" 8192 0.0 false
            ;;
        *)
            echo "Unknown task: $task"
            ;;
    esac
done
