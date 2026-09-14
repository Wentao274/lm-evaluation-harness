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
CHAT_API=${CHAT_API:-"OpenAI ChatCompletions"}

# 每任务 JSON 参数 (带默认值)
TASK_MAX_LENGTH_JSON=${TASK_MAX_LENGTH_JSON:-'{"mmlu_pro":32768,"gsm_plus":32768,"humaneval":16384,"ruler":137216}'}
TASK_MAX_TOKENS_JSON=${TASK_MAX_TOKENS_JSON:-'{"mmlu_pro":2048,"gsm_plus":2048,"humaneval":4096,"ruler":4096}'}
TASK_TEMPERATURE_JSON=${TASK_TEMPERATURE_JSON:-'{"mmlu_pro":1.0,"gsm_plus":1.0,"humaneval":1.0,"ruler":1.0}'}
TASK_EXAMPLES_JSON=${TASK_EXAMPLES_JSON:-'{"ruler":32}'}
NUM_CONCURRENT=${NUM_CONCURRENT:-1}

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
    echo "  - mmlu_pro, gsm_plus, humaneval, ruler"
    echo ""
    echo "Environment variables for per-task configuration:"
    echo "  TASK_MAX_LENGTH_JSON   JSON dict of per-task max_length (default: {\"mmlu_pro\":32768,...})"
    echo "  TASK_MAX_TOKENS_JSON   JSON dict of per-task max_tokens (default: {\"mmlu_pro\":2048,...})"
    echo "  TASK_TEMPERATURE_JSON  JSON dict of per-task temperature (default: all 1.0)"
    echo "  TASK_EXAMPLES_JSON     JSON dict of per-task sample limit (default: {\"ruler\":32}; empty = full set)"
    echo "  NUM_CONCURRENT         Concurrent requests (default: 1)"
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

# 从 JSON 字典中提取指定任务的值，未找到则返回默认值
json_get() {
    local json="$1"
    local key="$2"
    local default="$3"
    if [ -z "$json" ]; then
        echo "$default"
        return
    fi
    local val
    val=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    v = d.get(sys.argv[2])
    print('' if v is None else str(v))
except Exception:
    print('')
" "$json" "$key" 2>/dev/null)
    if [ -z "$val" ] || [ "$val" = "None" ]; then
        echo "$default"
    else
        echo "$val"
    fi
}

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
echo "  LLM_ADDR:             $LLM_ADDR" | tee -a "$LOG_FILE"
echo "  MODEL_NAME:           $MODEL_NAME" | tee -a "$LOG_FILE"
echo "  CHAT_API:             $CHAT_API" | tee -a "$LOG_FILE"
echo "  API_MODEL:            $API_MODEL" | tee -a "$LOG_FILE"
echo "  API_URL:              $LLM_ADDR$API_URL_SUFFIX" | tee -a "$LOG_FILE"
echo "  TASKS:                $TASKS" | tee -a "$LOG_FILE"
echo "  NUM_CONCURRENT:       $NUM_CONCURRENT" | tee -a "$LOG_FILE"
echo "  TASK_MAX_LENGTH_JSON:  $TASK_MAX_LENGTH_JSON" | tee -a "$LOG_FILE"
echo "  TASK_MAX_TOKENS_JSON:  $TASK_MAX_TOKENS_JSON" | tee -a "$LOG_FILE"
echo "  TASK_TEMPERATURE_JSON: $TASK_TEMPERATURE_JSON" | tee -a "$LOG_FILE"
echo "  TASK_EXAMPLES_JSON:    $TASK_EXAMPLES_JSON" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# 统一的 model_args 构造：max_length 按任务从 JSON 读取，num_concurrent 取全局值
build_model_args() {
    local max_length=$1
    echo "{\"model\":\"$MODEL_NAME\",\"base_url\":\"$LLM_ADDR$API_URL_SUFFIX\",\"max_length\":$max_length,\"tokenizer\":\"$LOCAL_MODEL_PATH\",\"trust_remote_code\":true,\"num_concurrent\":$NUM_CONCURRENT,\"max_retries\":3,\"timeout\":1200,\"tokenized_requests\":false,\"enable_thinking\":false,\"headers\":{\"Authorization\":\"Bearer $API_KEY\"}}"
}

# 统一的任务运行函数
# 参数: task_name max_length max_tokens temperature limit unsafe_code num_fewshot batch_size gen_kwargs_type
# gen_kwargs_type: "full" = 含 top_p/top_k, "simple" = 不含 (仅 humaneval)
run_task() {
    local task_name=$1
    local max_length=$2
    local max_tokens=$3
    local temperature=$4
    local limit=$5
    local unsafe_code=$6
    local num_fewshot=$7
    local batch_size=$8
    local gen_kwargs_type=$9

    local do_sample="false"
    if awk -v t="$temperature" 'BEGIN{exit !(t > 0.0)}'; then do_sample="true"; fi

    local GEN_KWARGS
    if [ "$gen_kwargs_type" = "simple" ]; then
        GEN_KWARGS="{\"max_gen_toks\":$max_tokens,\"do_sample\":$do_sample,\"temperature\":$temperature}"
    else
        GEN_KWARGS="{\"max_gen_toks\":$max_tokens,\"do_sample\":$do_sample,\"temperature\":$temperature,\"top_p\":0.95,\"top_k\":40}"
    fi

    local MODEL_ARGS
    MODEL_ARGS=$(build_model_args "$max_length")

    local unsafe_flag=""
    [ "$unsafe_code" = "true" ] && unsafe_flag="--confirm_run_unsafe_code" && export HF_ALLOW_CODE_EVAL=1

    local limit_flag=""
    [ -n "$limit" ] && limit_flag="--limit $limit"

    echo "" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    echo "Running Task: $task_name" | tee -a "$LOG_FILE"
    echo "  max_length:     $max_length" | tee -a "$LOG_FILE"
    echo "  max_tokens:     $max_tokens" | tee -a "$LOG_FILE"
    echo "  temperature:    $temperature" | tee -a "$LOG_FILE"
    echo "  limit:          ${limit:-<unlimited>}" | tee -a "$LOG_FILE"
    echo "  num_concurrent: $NUM_CONCURRENT" | tee -a "$LOG_FILE"
    echo "  batch_size:     $batch_size" | tee -a "$LOG_FILE"
    echo "  unsafe_code:    $unsafe_code" | tee -a "$LOG_FILE"
    echo "  num_fewshot:    $num_fewshot" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"

    lm_eval \
        --model $API_MODEL \
        --tasks $task_name \
        --output_path ${OUTPUT_BASE}/${task_name} \
        --model_args "$MODEL_ARGS" \
        --batch_size $batch_size \
        --gen_kwargs "$GEN_KWARGS" \
        --num_fewshot $num_fewshot \
        --log_samples \
        $CHAT_TEMPLATE_FLAG \
        $limit_flag \
        $unsafe_flag 2>&1 | tee -a "$LOG_FILE"

    unset HF_ALLOW_CODE_EVAL
}

IFS=',' read -ra TASK_LIST <<< "$TASKS"
for task in "${TASK_LIST[@]}"; do
    task=$(echo "$task" | xargs)

    # 任务固有配置: unsafe_code num_fewshot batch_size gen_kwargs_type
    case "$task" in
        mmlu_pro)
            t_unsafe="false"; t_fewshot="5"; t_batch="8"; t_gen_type="full"
            ;;
        gsm_plus)
            t_unsafe="false"; t_fewshot="8"; t_batch="8"; t_gen_type="full"
            ;;
        humaneval)
            t_unsafe="true"; t_fewshot="0"; t_batch="8"; t_gen_type="simple"
            ;;
        ruler)
            t_unsafe="false"; t_fewshot="0"; t_batch="1"; t_gen_type="full"
            ;;
        *)
            echo "Unknown task: $task" | tee -a "$LOG_FILE"
            continue
            ;;
    esac

    # 从 JSON 字典获取每任务的运行参数 (带安全兜底默认值)
    t_max_length=$(json_get "$TASK_MAX_LENGTH_JSON" "$task" "32768")
    t_max_tokens=$(json_get "$TASK_MAX_TOKENS_JSON" "$task" "4096")
    t_temperature=$(json_get "$TASK_TEMPERATURE_JSON" "$task" "1.0")
    t_limit=$(json_get "$TASK_EXAMPLES_JSON" "$task" "")

    run_task "$task" "$t_max_length" "$t_max_tokens" "$t_temperature" "$t_limit" \
             "$t_unsafe" "$t_fewshot" "$t_batch" "$t_gen_type"
done

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "lm-evaluation-harness Test Complete" | tee -a "$LOG_FILE"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
