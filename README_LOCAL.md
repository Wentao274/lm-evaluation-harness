## 离线数据集执行lm-eval任务操作步骤

**步骤一：clone整个测试目录到测试机器或容器上**

**步骤二：复制数据集** <br/>
- 将datasets/lm-eval/gsm_plus下的数据集目录qintongli___gsm-plus复制到/root/.cache/huggingface/datasets下（如果没有datasets目录，可自行创建）;
- 将datasets/lm-eval/mmlu_pro下的数据集目录TIGER-Lab___mmlu-pro复制到/root/.cache/huggingface/datasets下；
- 将datasets/lm-eval/ruler下的数据集目录babar, baber___paul_graham_essays和数据集文件dev-v2.0.json，hotpot_dev_distractor_v1.json复制到/root/.cache/huggingface/datasets下;
- 然后将datasets/lm-eval/ruler下的nltk_data目录复制到/root/下

**步骤三：到lm-evaluation-harness目录下，执行**
```shell
# 安装uv，并根据安装后的提示（类似source ~/.bashrc）使uv生效
curl -LsSf https://astral.sh/uv/install.sh | sh

# 创建虚拟环境
uv venv

# 激活虚拟环境
source .venv/bin/activate

# 安装依赖
uv pip install "lm_eval[vllm]"
uv pip install "lm_eval[api]"
uv pip install "lm_eval[ruler]"

# 验证安装
lm-eval -h

```

**步骤四：编辑执行脚本lm_eval_test.sh**
```shell
#!/bin/bash
ROOT_PATH=$(cd `dirname $0`; pwd)

echo $ROOT_PATH
cd ${ROOT_PATH}

CurDate=`date +'%Y%m%d'`

export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1

#export HF_ENDPOINT=https://hf-mirror.com

ADDR=${ADDR:-127.0.0.1}
PORT=${PORT:-8080}
API_KEY=${API_KEY:-abc123}
LLM_ADDR="http://$ADDR:$PORT"

# 自动获取模型名和 tokenizer 路径
#MODEL_NAME=$(curl -s --header "Authorization: Bearer $API_KEY" $LLM_ADDR/v1/models | jq -r .data[0].id)
#MODEL_PATH=$(curl -s --header "Authorization: Bearer $API_KEY" $LLM_ADDR/v1/models | jq -r .data[0].root)
MODEL_NAME="minimax-m2.5"  # 这里需要修改为被测试的模型服务名称
LOCAL_MODEL_PATH="/data/MiniMax-M2.5-W8A8-INT8-Dynamic" # 这里需要修改为被测试模型的完整路径

# model_args 构造
MODEL_ARGS_BASE_1="{\"model\":\"$MODEL_NAME\",\"base_url\":\"$LLM_ADDR/v1/completions\",\"max_length\":131072,\"tokenizer\":\"$LOCAL_MODEL_PATH\",\"trust_remote_code\":true,\"num_concurrent\":10,\"max_retries\":3,\"timeout\":12000,\"tokenized_requests\":false,\"headers\":{\"Authorization\":\"Bearer $API_KEY\"}}"
MODEL_ARGS_BASE_2="{\"model\":\"$MODEL_NAME\",\"base_url\":\"$LLM_ADDR/v1/completions\",\"max_length\":192512,\"tokenizer\":\"$LOCAL_MODEL_PATH\",\"trust_remote_code\":true,\"num_concurrent\":10,\"max_retries\":3,\"timeout\":12000,\"tokenized_requests\":false,\"headers\":{\"Authorization\":\"Bearer $API_KEY\"}}"

# 运行单个任务的函数
run_task_1() {
        local task_name=$1
        local max_tokens=$2
        local temperature=$3
        local unsafe_code=$4

        local do_sample="false"
        [ "$temperature" = "1.0" ] && do_sample="true"

        GEN_KWARGS="{\"max_gen_toks\":$max_tokens,\"do_sample\":$do_sample,\"temperature\":$temperature,\"top_p\":0.95,\"top_k\":40}"

        local unsafe_flag=""
        [ "$unsafe_code" = "true" ] && unsafe_flag="--confirm_run_unsafe_code" && export HF_ALLOW_CODE_EVAL=1

        lm_eval \
                --model local-completions \
                --tasks $task_name \
                --output_path ./output/${task_name}/${MODEL_NAME}_${CurDate} \
                --model_args "$MODEL_ARGS_BASE_1" \
                --batch_size auto \
                --gen_kwargs "$GEN_KWARGS" \
                $unsafe_flag
}


run_task_2() {
        local task_name=$1
        local max_tokens=$2
        local temperature=$3
        local unsafe_code=$4

        local do_sample="false"
        [ "$temperature" = "1.0" ] && do_sample="true"

        GEN_KWARGS="{\"max_gen_toks\":$max_tokens,\"do_sample\":$do_sample,\"temperature\":$temperature,\"top_p\":0.95,\"top_k\":40}"

        local unsafe_flag=""
        [ "$unsafe_code" = "true" ] && unsafe_flag="--confirm_run_unsafe_code" && export HF_ALLOW_CODE_EVAL=1

        lm_eval \
                --model local-completions \
                --tasks $task_name \
                --output_path ./output/${task_name}/${MODEL_NAME}_${CurDate} \
                --model_args "$MODEL_ARGS_BASE_2" \
                --batch_size auto \
                --limit 32 \
                --gen_kwargs "$GEN_KWARGS" \ 
                $unsafe_flag
}


#sleep 120
run_task_1 mmlu_pro 8192 0.0 false

sleep 120
run_task_1 gsm_plus 8192 0.0 false

sleep 120
run_task_2 ruler 8192 0.0 false
```

**步骤五：执行测试**
```shell
nohup ./lm_eval_test.sh > ./output/xxxx.log 2>&1 &

```