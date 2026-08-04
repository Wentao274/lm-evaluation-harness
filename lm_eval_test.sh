#!/bin/bash
ROOT_PATH=$(cd `dirname $0`; pwd)

echo $ROOT_PATH
cd ${ROOT_PATH}

CurDate=$(date +'%Y%m%d%H%M%S')

export HF_ENDPOINT=${HF_ENDPOINT:-https://hf-mirror.com}
export LMEVAL_LOG_LEVEL=${LMEVAL_LOG_LEVEL:-INFO}

if [ -z "$LLM_ADDR" ]; then
    ADDR=${ADDR:-127.0.0.1}
    PORT=${PORT:-8080}
    LLM_ADDR="http://$ADDR:$PORT"
fi

API_KEY=${API_KEY:-abc123}
MODEL_NAME=${MODEL_NAME:-kimi-k2.5}
LOCAL_MODEL_PATH=${LOCAL_MODEL_PATH:-"/dingofs/data2/userdata/llms/moonshotai/Kimi-K2.6"}
OUTPUT_BASE=${OUTPUT_BASE:-./output_h100}
LIMIT=${LIMIT:-}
RULER_LIMIT=${RULER_LIMIT:-32}
CHAT_API=${CHAT_API:-"OpenAI Completions"}

if [ "$CHAT_API" = "OpenAI ChatCompletions" ]; then
    API_MODEL="local-chat-completions"
    API_URL_SUFFIX="/v1/chat/completions"
    CHAT_TEMPLATE_FLAG="--apply_chat_template"
else
    API_MODEL="local-completions"
    API_URL_SUFFIX="/v1/completions"
    CHAT_TEMPLATE_FLAG=""
fi

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
    echo "  Task name(s) to run, comma-separated (e.g., mmlu_pro or mmlu_pro,gsm_plus,humaneval,ruler)"
    echo ""
    echo "Supported tasks:"
    echo "  - mmlu_pro, gsm_plus: run with run_task_other"
    echo "  - humaneval: run with run_task_humaneval"
    echo "  - ruler: run with run_task_ruler (last)"
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

# 生成日志文件路径
TASKS_UNDERSCORE=$(echo "$TASKS" | tr ',' '-')
LOG_FILE="${OUTPUT_BASE}/lm-eval-${TASKS_UNDERSCORE}.log"
mkdir -p ${OUTPUT_BASE}

# 记录开始时间
echo "========================================" | tee "$LOG_FILE"
echo "lm-evaluation-harness Test Start" | tee -a "$LOG_FILE"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Config:" | tee -a "$LOG_FILE"
echo "  LLM_ADDR: $LLM_ADDR" | tee -a "$LOG_FILE"
echo "  MODEL_NAME: $MODEL_NAME" | tee -a "$LOG_FILE"
echo "  CHAT_API: $CHAT_API" | tee -a "$LOG_FILE"
echo "  API_MODEL: $API_MODEL" | tee -a "$LOG_FILE"
echo "  API_URL: $LLM_ADDR$API_URL_SUFFIX" | tee -a "$LOG_FILE"
echo "  TASKS: $TASKS" | tee -a "$LOG_FILE"
echo "  LIMIT: ${LIMIT:-<unlimited>}" | tee -a "$LOG_FILE"
echo "  RULER_LIMIT: $RULER_LIMIT" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# model_args 构造
MODEL_ARGS_BASE_OTHER="{\"model\":\"$MODEL_NAME\",\"base_url\":\"$LLM_ADDR$API_URL_SUFFIX\",\"max_length\":32768,\"tokenizer\":\"$LOCAL_MODEL_PATH\",\"trust_remote_code\":true,\"num_concurrent\":10,\"max_retries\":3,\"timeout\":1200,\"tokenized_requests\":false,\"headers\":{\"Authorization\":\"Bearer $API_KEY\"}}"
MODEL_ARGS_BASE_HUMANEVAL="{\"model\":\"$MODEL_NAME\",\"base_url\":\"$LLM_ADDR$API_URL_SUFFIX\",\"max_length\":16384,\"tokenizer\":\"$LOCAL_MODEL_PATH\",\"trust_remote_code\":true,\"num_concurrent\":1,\"max_retries\":3,\"timeout\":120,\"tokenized_requests\":false,\"headers\":{\"Authorization\":\"Bearer $API_KEY\"}}"
MODEL_ARGS_BASE_RULER="{\"model\":\"$MODEL_NAME\",\"base_url\":\"$LLM_ADDR$API_URL_SUFFIX\",\"max_length\":137216,\"tokenizer\":\"$LOCAL_MODEL_PATH\",\"trust_remote_code\":true,\"num_concurrent\":10,\"max_retries\":3,\"timeout\":1200,\"tokenized_requests\":false,\"headers\":{\"Authorization\":\"Bearer $API_KEY\"}}"

# 运行单个任务的函数
run_task_other() {
	local task_name=$1
	local max_tokens=$2
	local temperature=$3
	local unsafe_code=$4
	local num_fewshot=$5
	
	local do_sample="false"
	if awk -v t="$temperature" 'BEGIN{exit !(t > 0.0)}'; then do_sample="true"; fi

	GEN_KWARGS="{\"max_gen_toks\":$max_tokens,\"do_sample\":$do_sample,\"temperature\":$temperature,\"top_p\":0.95,\"top_k\":40}"

	local unsafe_flag=""
	[ "$unsafe_code" = "true" ] && unsafe_flag="--confirm_run_unsafe_code" && export HF_ALLOW_CODE_EVAL=1
	
	local limit_flag=""
	[ -n "$LIMIT" ] && limit_flag="--limit $LIMIT"
	
	echo "" | tee -a "$LOG_FILE"
	echo "========================================" | tee -a "$LOG_FILE"
	echo "Running Task: $task_name" | tee -a "$LOG_FILE"
	echo "========================================" | tee -a "$LOG_FILE"
	
	lm_eval \
		--model $API_MODEL \
		--tasks $task_name \
		--output_path ${OUTPUT_BASE}/${task_name} \
		--model_args "$MODEL_ARGS_BASE_OTHER" \
		--batch_size auto \
		--gen_kwargs "$GEN_KWARGS" \
		--num_fewshot $num_fewshot \
		--log_samples \
		$CHAT_TEMPLATE_FLAG \
		$limit_flag \
		$unsafe_flag 2>&1 | tee -a "$LOG_FILE"
}


run_task_humaneval() {
	local task_name=$1
	local max_tokens=$2
	local temperature=$3
	local unsafe_code=$4
	local num_fewshot=$5
	
	local do_sample="false"
	if awk -v t="$temperature" 'BEGIN{exit !(t > 0.0)}'; then do_sample="true"; fi

	GEN_KWARGS="{\"max_gen_toks\":$max_tokens,\"do_sample\":$do_sample,\"temperature\":$temperature}"

	local unsafe_flag=""
	[ "$unsafe_code" = "true" ] && unsafe_flag="--confirm_run_unsafe_code" && export HF_ALLOW_CODE_EVAL=1
	
	local limit_flag=""
	[ -n "$LIMIT" ] && limit_flag="--limit $LIMIT"
	
	echo "" | tee -a "$LOG_FILE"
	echo "========================================" | tee -a "$LOG_FILE"
	echo "Running Task: $task_name" | tee -a "$LOG_FILE"
	echo "========================================" | tee -a "$LOG_FILE"
	
	lm_eval \
		--model $API_MODEL \
		--tasks $task_name \
		--output_path ${OUTPUT_BASE}/${task_name} \
		--model_args "$MODEL_ARGS_BASE_HUMANEVAL" \
		--batch_size auto \
		--gen_kwargs "$GEN_KWARGS" \
		--num_fewshot $num_fewshot \
		--log_samples \
		$CHAT_TEMPLATE_FLAG \
		$limit_flag \
		$unsafe_flag 2>&1 | tee -a "$LOG_FILE"
	
	unset HF_ALLOW_CODE_EVAL
}


run_task_ruler() {
	local task_name=$1
	local max_tokens=$2
	local temperature=$3
	local unsafe_code=$4
	local num_fewshot=$5
	
	local do_sample="false"
	if awk -v t="$temperature" 'BEGIN{exit !(t > 0.0)}'; then do_sample="true"; fi

	GEN_KWARGS="{\"max_gen_toks\":$max_tokens,\"do_sample\":$do_sample,\"temperature\":$temperature,\"top_p\":0.95,\"top_k\":40}"

	local unsafe_flag=""
	[ "$unsafe_code" = "true" ] && unsafe_flag="--confirm_run_unsafe_code" && export HF_ALLOW_CODE_EVAL=1
	
	local limit_flag="--limit $RULER_LIMIT"
	
	echo "" | tee -a "$LOG_FILE"
	echo "========================================" | tee -a "$LOG_FILE"
	echo "Running Task: $task_name" | tee -a "$LOG_FILE"
	echo "========================================" | tee -a "$LOG_FILE"
	
	lm_eval \
		--model $API_MODEL \
		--tasks $task_name \
		--output_path ${OUTPUT_BASE}/${task_name} \
		--model_args "$MODEL_ARGS_BASE_RULER" \
		--batch_size auto \
		--gen_kwargs "$GEN_KWARGS" \
		--num_fewshot $num_fewshot \
		--log_samples \
		$CHAT_TEMPLATE_FLAG \
		$limit_flag \
		$unsafe_flag 2>&1 | tee -a "$LOG_FILE"
}

IFS=',' read -ra TASK_LIST <<< "$TASKS"
for task in "${TASK_LIST[@]}"; do
    task=$(echo "$task" | xargs)
    case "$task" in
        mmlu_pro)
            run_task_other "$task" 2048 0.0 false 5
            ;;
        gsm_plus)
            run_task_other "$task" 2048 0.0 false 8
            ;;
        humaneval)
            run_task_humaneval "$task" 4096 0.0 true 0
            ;;
        ruler)
            run_task_ruler "$task" 4096 0.0 false 0
            ;;
        *)
            echo "Unknown task: $task" | tee -a "$LOG_FILE"
            ;;
    esac
done

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "lm-evaluation-harness Test Complete" | tee -a "$LOG_FILE"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
