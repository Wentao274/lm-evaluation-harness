# lm-evaluation-harness 本地与 Jenkins 测试指南

本文档介绍如何使用 `lm_eval_test.sh` / `run_eval.py` 手动执行 lm-evaluation-harness 精度评测，以及通过 `Jenkinsfile` 自动触发测试的完整流程。

支持的评测任务：

| 任务        | 说明                  | 运行函数             | max_gen_toks | temperature | unsafe_code | num_fewshot |
| ----------- | --------------------- | -------------------- | ------------ | ----------- | ----------- | ----------- |
| `mmlu_pro`  | 综合知识问答          | `run_task_other`     | 8192         | 0.0         | false       | 5           |
| `gsm_plus`  | 数学推理              | `run_task_other`     | 8192         | 0.0         | false       | 8           |
| `humaneval` | 代码生成（含不安全码）| `run_task_humaneval` | 4096         | 0.0         | true        | 0           |
| `ruler`     | 长上下文检索          | `run_task_ruler`     | 8192         | 0.0         | false       | 0           |

---

## 一、环境准备

### 1. 克隆仓库

将整个测试目录克隆到测试机器或容器上：

```shell
git clone <repo-url> lm-evaluation-harness
cd lm-evaluation-harness
```

### 2. 准备离线数据集

> 网络通畅时可跳过本步，lm-eval 会自动从 HuggingFace 下载。离线环境下需手动复制数据集到缓存目录（默认 `/root/.cache/huggingface/datasets`，若不存在可自行创建）。

- 将 gsm_plus任务用到的离线下载的 `qintongli___gsm-plus` 目录复制到缓存目录；
- 将 mmlu_pro任务用到的离线下载的 `TIGER-Lab___mmlu-pro` 目录复制到缓存目录；
- 将 humaneval任务用到的离线下载的 `openai` 目录复制到缓存目录；
- 将 ruler任务用到的离线下载的 `babar`或者`baber___paul_graham_essays` 目录(根据实际下载的数据集目录结构为准)及 `dev-v2.0.json`、`hotpot_dev_distractor_v1.json` 文件复制到缓存目录；
- 将 ruler任务用到的离线下载的 `nltk_data` 目录复制到 `/root/` 下（供 ruler 任务使用）。

### 3. 安装 uv 并创建虚拟环境

```shell
# 安装 uv，并根据安装后的提示（类似 source ~/.bashrc）使 uv 生效
curl -LsSf https://astral.sh/uv/install.sh | sh

# 创建虚拟环境
uv venv

# 激活虚拟环境
source .venv/bin/activate
```

### 4. 安装依赖

```shell
# 安装本仓库（lm_eval 本体）
uv pip install .

# 按需安装各可选依赖
uv pip install "lm_eval[api]"          # OpenAI 兼容 API 接口
uv pip install "lm_eval[unsafe_code]"  # humaneval 等需执行代码的任务
uv pip install "lm_eval[ruler]"        # ruler 任务（nltk / wonderwords / scipy）
uv pip install "lm_eval[hf]"           # HuggingFace tokenizer 支持
uv pip install "lm_eval[sglang]"       # sglang 后端（可选）

# 验证安装
lm-eval -h
```

### 5. 赋予脚本执行权限

```shell
chmod +x lm_eval_test.sh
chmod +x run_eval.py
```

---

## 二、手动执行测试

手动执行有两种方式：直接调用 `lm_eval_test.sh`，或通过 Python 封装脚本 `run_eval.py`（后者会自动生成带时间戳的输出目录并设置环境变量）。

### 方式一：直接执行 `lm_eval_test.sh`

#### 用法

```shell
./lm_eval_test.sh [OPTIONS] TASK
```

**位置参数**

| 参数   | 说明                                                                | 是否必填 |
| ------ | ------------------------------------------------------------------- | -------- |
| `TASK` | 任务名称，逗号分隔，如 `mmlu_pro` 或 `mmlu_pro,gsm_plus,humaneval,ruler` | 是       |

**可选参数**

| 参数                      | 说明                                   |
| ------------------------- | -------------------------------------- |
| `-a, --addr ADDRESS`      | 服务地址（默认 `127.0.0.1`）           |
| `-p, --port PORT`         | 服务端口（默认 `8080`）                |
| `-k, --api-key KEY`       | API Key（默认 `abc123`）               |
| `-l, --llm-addr URL`      | 完整 LLM 地址（覆盖 addr/port）       |
| `-m, --model-name NAME`   | 模型名称（默认 `kimi-k2.5`）          |
| `-d, --model-path PATH`   | 本地模型路径（用于加载 tokenizer）     |
| `-h, --help`              | 显示帮助                               |

**关键环境变量**（优先级高于命令行默认值）

| 环境变量           | 默认值                                                 | 说明                                                                        |
| ------------------ | ------------------------------------------------------ | --------------------------------------------------------------------------- |
| `LLM_ADDR`         | `http://$ADDR:$PORT`                                   | 完整 LLM 地址，设置后覆盖 addr/port                                         |
| `ADDR` / `PORT`    | `127.0.0.1` / `8080`                                   | 服务地址与端口（仅当 `LLM_ADDR` 未设置时生效）                              |
| `API_KEY`          | `abc123`                                               | Bearer 认证 Key                                                             |
| `MODEL_NAME`       | `kimi-k2.5`                                            | 模型服务名称                                                                |
| `LOCAL_MODEL_PATH` | `/dingofs/data2/userdata/llms/moonshotai/Kimi-K2.6`    | 本地模型路径（tokenizer 来源）                                              |
| `OUTPUT_BASE`      | `./output_h100`                                        | 结果输出根目录                                                              |
| `CHAT_API`         | `OpenAI Completions`                                   | 接口类型：`OpenAI Completions`→`/v1/completions`；`OpenAI ChatCompletions`→`/v1/chat/completions` 并启用 `--apply_chat_template` |
| `LIMIT`            | 空                                                     | 限制每个任务样本数（ruler 任务除外），为空则不限制                          |
| `RULER_LIMIT`      | `32`                                                   | 仅针对 ruler 任务的样本限制                                                 |
| `HF_ENDPOINT`      | `https://hf-mirror.com`                               | HuggingFace 镜像地址                                                        |
| `LMEVAL_LOG_LEVEL` | `INFO`                                                 | lm-eval 日志级别                                                            |

#### 执行示例

```shell
# 设置环境变量（按实际环境修改）
export LLM_ADDR="http://127.0.0.1:8080"
export API_KEY="abc123"
export MODEL_NAME="kimi-k2.5"
export LOCAL_MODEL_PATH="/dingofs/data2/userdata/llms/moonshotai/Kimi-K2.6"
export OUTPUT_BASE="./output_h100"

# 运行单个任务
./lm_eval_test.sh mmlu_pro

# 运行多个任务
./lm_eval_test.sh mmlu_pro,gsm_plus,humaneval,ruler

# 通过命令行参数指定地址与模型
./lm_eval_test.sh -a 10.201.149.10 -p 8080 -m kimi-k2.5 -d /path/to/model mmlu_pro

# 后台运行并将日志输出到文件
nohup ./lm_eval_test.sh mmlu_pro,gsm_plus > ./lm_eval_run.log 2>&1 &
```

### 方式二：通过 `run_eval.py` 执行

`run_eval.py` 是对 `lm_eval_test.sh` 的 Python 封装，会自动创建带时间戳的结果目录并通过环境变量传递参数，适合需要规范化输出路径的场景。

#### 用法

```shell
python3 run_eval.py \
    --tester <测试人员> \
    --build-number <构建编号> \
    --chip <芯片平台> \
    --model <模型名称> \
    --model-path <模型路径> \
    --base-url <API地址> \
    [--api-key <API_KEY>] \
    [--chat-api <接口类型>] \
    [--tasks <任务列表>] \
    [--limit <样本限制>] \
    [--ruler-limit <ruler样本限制>] \
    [--log-level <日志级别>]
```

#### 参数说明

| 参数             | 类型 | 默认值               | 说明                                                          |
| ---------------- | ---- | -------------------- | ------------------------------------------------------------- |
| `--tester`       | 必填 | -                    | 测试人员名称                                                  |
| `--build-number` | 必填 | -                    | 构建编号                                                      |
| `--chip`         | 必填 | -                    | 芯片平台名称                                                  |
| `--model`        | 必填 | -                    | 模型服务名称（含路径前缀时取最后一段作为目录名）              |
| `--model-path`   | 必填 | -                    | 本地模型文件路径                                              |
| `--base-url`     | 必填 | -                    | LLM 基础地址，如 `http://127.0.0.1:8080`                      |
| `--api-key`      | 可选 | 空                   | Bearer 认证 Key                                               |
| `--chat-api`     | 可选 | `OpenAI Completions` | 接口类型：`OpenAI Completions` / `OpenAI ChatCompletions`     |
| `--tasks`        | 可选 | `mmlu_pro`           | 任务列表，逗号分隔                                            |
| `--limit`        | 可选 | 空                   | 样本数限制（ruler 除外）                                      |
| `--ruler-limit`  | 可选 | `32`                 | ruler 任务样本限制                                            |
| `--log-level`    | 可选 | `INFO`               | 日志级别：DEBUG/INFO/WARNING/ERROR/CRITICAL                   |

#### 执行示例

```shell
source .venv/bin/activate

python3 run_eval.py \
    --tester liwt \
    --build-number 1 \
    --chip nvidia-h100 \
    --model kimi-k2.5 \
    --model-path /dingofs/data2/userdata/llms/moonshotai/Kimi-K2.6 \
    --base-url http://127.0.0.1:8080 \
    --api-key abc123 \
    --chat-api "OpenAI Completions" \
    --tasks mmlu_pro,gsm_plus,humaneval,ruler \
    --ruler-limit 32 \
    --log-level INFO
```

### 脚本内部执行流程

1. **解析参数并构造 model_args**：根据 `CHAT_API` 选择 `/v1/completions` 或 `/v1/chat/completions` 接口，并为不同任务生成对应的 `model_args`（humaneval 使用 `local-completions` 且 `num_concurrent=1`）。
2. **生成日志文件**：`$OUTPUT_BASE/lm-eval-<tasks>.log`，所有输出同时写入终端与日志。
3. **按任务顺序执行**：依次调用 `lm_eval` CLI，结果输出到 `$OUTPUT_BASE/<task_name>/`。
4. **ruler 任务**固定使用 `--limit $RULER_LIMIT`，其他任务在 `LIMIT` 非空时启用 `--limit`。
5. **humaneval 任务**会自动设置 `HF_ALLOW_CODE_EVAL=1` 并附加 `--confirm_run_unsafe_code`，执行后取消该环境变量。

### 输出目录结构

- 直接执行 `lm_eval_test.sh`：

  ```
  $OUTPUT_BASE/
  ├── lm-eval-<tasks>.log      # 汇总日志
  ├── mmlu_pro/                # 各任务结果
  ├── gsm_plus/
  ├── humaneval/
  └── ruler/
  ```

- 通过 `run_eval.py` 执行：

  ```
  ./output/<tester>/<build_number>/<chip>/<model_dir>/<timestamp>/
  ├── lm-eval-<tasks>.log
  ├── mmlu_pro/
  ├── gsm_plus/
  ├── humaneval/
  └── ruler/
  ```

### 查看测试结果

测试完成后，日志中会输出每个任务的结果表格，示例片段如下：

```text
|Tasks|Version|Filter|n-shot|Metric|   |Value |   |Stderr|
|-----|------:|-----|-----:|------|---|-----:|---|-----:|
|mmlu |      2|none |     5|acc   |↑  |0.7563|±  |0.0121|
```

重点关注各任务的主指标：`mmlu_pro`（acc）、`gsm_plus`（strict-match）、`humaneval`（pass@1）、`ruler`（各子任务均值）。

---

## 三、Jenkins 流水线

lm-evaluation-harness 的 Jenkins 测试流水线：

**构建 Pipeline**（`lm-evaluation-harness/Jenkinsfile`）：通过 SSH 远程执行实际的 lm-eval 评测。

#### 执行节点与远程主机

- **Jenkins Agent**：`slave-2`
- **远程执行主机**：`10.201.132.50`（用户 `root`），通过 `sshagent` 凭据 `HOST_SSH_KEY` 免密登录
- **远程工作目录**（`WORK_DIR`）：默认 `/dingofs/data2/userdata/liwt/maas-image/lm-evaluation-harness`

#### 构建参数

| 参数              | 类型     | 默认值                                                | 说明                                                                  |
| ----------------- | -------- | ----------------------------------------------------- | --------------------------------------------------------------------- |
| `TESTER`          | string   | `liwt`                                                | 测试人员名称（必填）                                                  |
| `CHIP`            | string   | `nvidia-h100`                                         | 芯片平台名称（必填）                                                  |
| `ENGINE`          | choice   | `vllm` / `sglang`                                     | 推理框架（必填）                                                      |
| `PD`              | choice   | `agg` / `disagg`                                      | PD 分离模式（`agg` 非分离，`disagg` PD 分离）                         |
| `MODEL`           | string   | `kimi-k2.5`                                           | 模型服务名称（必填）                                                  |
| `MODEL_PATH`      | string   | `/dingofs/data2/userdata/llms/moonshotai/Kimi-K2.6`   | 模型文件本地路径（host 绝对路径）                                     |
| `BASE_URL`        | string   | `http://10.201.149.10:8080`                           | API 地址（必填）                                                      |
| `API_KEY`         | password | 空                                                    | API Key（可选，无需认证时留空，留空时脚本默认使用 `abc123`）          |
| `CHAT_API`        | choice   | `OpenAI ChatCompletions` / `OpenAI Completions`       | 接口类型                                                              |
| `TASK_MMLU_PRO`   | bool     | `true`                                                | 运行 mmlu_pro 任务                                                    |
| `TASK_GSM_PLUS`   | bool     | `true`                                                | 运行 gsm_plus 任务                                                    |
| `TASK_HUMANEVAL`  | bool     | `true`                                                | 运行 humaneval 任务                                                   |
| `TASK_RULER`      | bool     | `true`                                                | 运行 ruler 任务                                                       |
| `LIMIT`           | string   | 空                                                    | 每个任务样本数限制（ruler 除外，为空则不限制）                        |
| `RULER_LIMIT`     | string   | `32`                                                  | ruler 任务样本限制                                                    |
| `LMEVAL_LOG_LEVEL`| choice   | `INFO` / `DEBUG` / `WARNING` / `ERROR` / `CRITICAL`   | lm-eval 日志级别                                                      |
| `DESCRIPTION`     | string   | 空                                                    | 模型服务的描述信息                                                    |
| `RECIPIENTS`      | text     | `liwt@zetyun.com`                                     | 测试报告邮件接收者（逗号分隔）                                        |
| `WORK_DIR`        | string   | `/dingofs/data2/userdata/liwt/maas-image/lm-evaluation-harness` | 测试仓库目录（请勿改动）                                    |

#### 执行阶段

流水线包含以下阶段，按顺序执行：

1. **打印测试参数**：输出本次构建的所有参数信息。
2. **API 连通性预检**：SSH 到远程主机，对 `/v1/models` 与 `/v1/chat/completions` 接口发起请求。若失败，将构建标记为 `UNSTABLE` 并设置 `CONNECTIVITY_FAILED`，后续阶段（环境检查、运行测试）跳过。
3. **环境检查**（连通性通过后执行）：
   - 清理可能残留的 `lm_eval` / `run_eval` 进程（先 SIGTERM，未响应再 SIGKILL）
   - 赋予脚本执行权限（`lm_eval_test.sh`、`run_eval.py`）
   - 若 `.venv` 不存在，则通过代理执行 `uv venv` 并安装依赖（`uv pip install .`、`lm_eval[api]`、`lm_eval[unsafe_code]`、`lm_eval[ruler]`、`lm_eval[sglang]`、`lm_eval[hf]`）
4. **运行 lm-evaluation 测试**（连通性通过后执行）：
   - 根据勾选的任务布尔参数拼接 `TASKS` 列表（如 `mmlu_pro,gsm_plus,humaneval,ruler`）
   - 激活远程虚拟环境，执行 `python3 run_eval.py` 并传入全部参数
   - 远程输出目录：`output/<TESTER>/<BUILD_NUMBER>/<CHIP>/<MODEL_DIR>/`
5. **拉取测试结果**：通过 `scp` 将远程结果目录拉取到 Jenkins 的 `reports/<TESTER>/<BUILD_NUMBER>/<CHIP>/`，同时拉取连通性预检日志到 `builds/<BUILD_NUMBER>/`。
6. **发送邮件**：解析日志中各任务的得分表格与主指标，生成 HTML 邮件报告发送给 `RECIPIENTS`，并附带日志附件。连通性失败时邮件中会展示失败原因段落。

#### 构建后处理

- **归档产物**：`reports/<TESTER>/<BUILD_NUMBER>/**` 与 `builds/<BUILD_NUMBER>/**` 全部归档至 Jenkins
- **清理工作空间**：每次构建后执行 `cleanWs()`

#### 构建状态说明

| 情况                  | 构建结果                   |
| --------------------- | -------------------------- |
| 连通性预检失败        | `UNSTABLE`                 |
| 测试阶段失败          | `UNSTABLE`（阶段 `FAILURE`）|
| 拉取结果/邮件失败     | `UNSTABLE`（阶段 `FAILURE`）|
| 全部成功              | `SUCCESS`                  |

---

## 四、注意事项

1. **接口类型选择**：`OpenAI Completions` 使用 `/v1/completions` 且不启用 chat template；`OpenAI ChatCompletions` 使用 `/v1/chat/completions` 并附加 `--apply_chat_template`。请根据被测模型服务支持的接口选择。
2. **模型路径**：`LOCAL_MODEL_PATH` / `MODEL_PATH` 仅用于加载 tokenizer，不会加载模型权重，确保该路径下包含正确的 tokenizer 配置文件。
3. **humaneval 安全码**：该任务需执行模型生成的代码，脚本会自动设置 `HF_ALLOW_CODE_EVAL=1`，请在可信环境中运行。
4. **离线环境**：若网络受限，请提前完成离线数据集复制（见「环境准备」），并可设置 `HF_HUB_OFFLINE=1`、`TRANSFORMERS_OFFLINE=1`。
5. **超时与重试**：model_args 中默认配置 `num_concurrent=10`、`max_retries=3`、`timeout=1200`（humaneval 为 `num_concurrent=1`、`timeout=120`）。如遇大量超时，可适当增大 timeout 或降低并发数。
