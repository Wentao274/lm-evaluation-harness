pipeline {
    agent any
    parameters {
        string(name: 'TESTER', defaultValue: 'liwt', description: '测试人员名称（必填）')
        string(name: 'CHIP', defaultValue: 'nvidia-h100', description: '芯片平台名称（必填）')
        choice(name: 'ENGINE', choices: ['vllm', 'sglang'], description: '推理框架（必填）')
        choice(name: 'PD', choices: ['agg', 'disagg'], description: 'PD分离模式（agg表示非PD分离，disagg表示PD分离）')
        string(name: 'MODEL', defaultValue: 'kimi-k2.5', description: '模型服务名称 (必填)')
        string(name: 'MODEL_PATH', defaultValue: '/dingofs/data2/userdata/llms/moonshotai/Kimi-K2.6', description: '模型文件本地路径，请使用host绝对路径')
        string(name: 'BASE_URL', defaultValue: 'http://10.201.149.10:8080', description: 'API 地址（必填）')
        password(name: 'API_KEY', defaultValue: '', description: 'API Key (可选，无需认证时留空)')
        choice(name: 'CHAT_API', choices: ['OpenAI Completions', 'OpenAI ChatCompletions'], description: '接口类型, OpenAI Completions 使用 /v1/completions, OpenAI ChatCompletions 使用 /v1/chat/completions')
        booleanParam(name: 'TASK_MMLU_PRO', defaultValue: true, description: '运行 mmlu_pro 任务')
        booleanParam(name: 'TASK_GSM_PLUS', defaultValue: true, description: '运行 gsm_plus 任务')
        booleanParam(name: 'TASK_RULER', defaultValue: false, description: '运行 ruler 任务')
        string(name: 'LIMIT', defaultValue: '', description: '限制每个任务运行的样本数量 (非必填，为空则不限制，针对除Ruler任务以外的其他任务)')
        string(name: 'RULER_LIMIT', defaultValue: '32', description: '仅针对Ruler任务样本限制 (默认32)')
        choice(name: 'LMEVAL_LOG_LEVEL', choices: ['INFO', 'DEBUG', 'WARNING', 'ERROR', 'CRITICAL'], description: 'lm-evaluation-harness 日志级别')
        text(name: 'RECIPIENTS', defaultValue: 'liwt@zetyun.com', description: '测试报告邮件接收者（逗号分隔）')
        string(name: 'WORK_DIR', defaultValue: '/dingofs/data2/userdata/liwt/maas-image/lm-evaluation-harness', description: '测试仓库目录，请不要改动')
    }
    environment {
        SSH_CREDENTIALS = 'HOST_SSH_KEY'
        REMOTE_HOST = '10.201.132.50'
        REMOTE_USER = 'root'
    }
    
    stages {
        stage('API 连通性预检') {
            steps {
                sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                    script {
                        try {
                            sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << 'ENDSSH'
set -o pipefail
{
    echo "=== 检查 API 连通性 (/v1/models) ==="
    HTTP_CODE=\$(curl -s --connect-timeout 10 -m 30 -o /dev/null -w "%{http_code}" ${params.BASE_URL}/v1/models)
    if [ "\${HTTP_CODE}" != "200" ]; then
        echo "ERROR: API 连通性检查失败, HTTP状态码: \${HTTP_CODE}, URL: ${params.BASE_URL}/v1/models"
        exit 1
    fi
    echo "API /v1/models 连通性检查通过, HTTP状态码: \${HTTP_CODE}"

    echo "=== 检查 Chat Completions 接口 ==="
    CHAT_RESP=\$(curl -s --connect-timeout 10 -m 60 -w "\\n%{http_code}" ${params.BASE_URL}/v1/chat/completions \\
        -H "Content-Type: application/json" \\
        -d '{"model":"${params.MODEL}","messages":[{"role":"user","content":"hello"}],"max_tokens":10}')
    CHAT_HTTP_CODE=\$(echo "\${CHAT_RESP}" | tail -1)
    if [ "\${CHAT_HTTP_CODE}" != "200" ]; then
        echo "ERROR: Chat Completions 接口检查失败, HTTP状态码: \${CHAT_HTTP_CODE}"
        echo "响应内容: \$(echo "\${CHAT_RESP}" | head -n -1)"
        exit 1
    fi
    echo "Chat Completions 接口检查通过, HTTP状态码: \${CHAT_HTTP_CODE}"
} 2>&1 | tee /tmp/lm_eval_connectivity_${BUILD_NUMBER}.log
ENDSSH
"""
                        } catch (Exception e) {
                            env.CONNECTIVITY_FAILED = 'true'
                            currentBuild.result = 'UNSTABLE'
                            println("=== API 连通性预检失败,后续阶段(环境检查、运行lm-evaluation测试)将跳过 ===")
                        }
                    }
                }
            }
        }

        stage('环境检查') {
            when {
                expression { env.CONNECTIVITY_FAILED != 'true' }
            }
            steps {
                sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                    sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << 'ENDSSH'
set -e
cd ${params.WORK_DIR}
echo "工作目录: \$(pwd)"
ls -la

echo "=== 清理残留进程 (lm_eval / run_eval) ==="
RESIDUAL=\$(pgrep -af "lm_eval|run_eval" 2>/dev/null || true)
if [ -n "\${RESIDUAL}" ]; then
    echo "发现残留进程:"
    echo "\${RESIDUAL}"
    echo "发送 SIGTERM..."
    echo "\${RESIDUAL}" | awk '{print \$1}' | xargs -r kill -TERM 2>/dev/null || true
    sleep 3
    REMAINING=\$(pgrep -af "lm_eval|run_eval" 2>/dev/null || true)
    if [ -n "\${REMAINING}" ]; then
        echo "残留进程未响应 SIGTERM,发送 SIGKILL..."
        echo "\${REMAINING}" | awk '{print \$1}' | xargs -r kill -KILL 2>/dev/null || true
        sleep 1
    fi
    FINAL=\$(pgrep -af "lm_eval|run_eval" 2>/dev/null || true)
    if [ -n "\${FINAL}" ]; then
        echo "WARN: 以下残留进程仍存在,需人工介入:"
        echo "\${FINAL}"
    else
        echo "残留进程清理完成"
    fi
else
    echo "未发现残留进程"
fi

echo "=== 设置权限 ==="
chmod +x lm_eval_test.sh
chmod +x run_eval.py

echo "=== 检查并创建虚拟环境 ==="
if [ ! -d "${params.WORK_DIR}/.venv" ]; then
    export https_proxy=http://100.64.1.68:1080
    export http_proxy=http://100.64.1.68:1080
    echo "创建虚拟环境..."
    cd ${params.WORK_DIR}
    uv venv
    unset https_proxy
    unset http_proxy
fi

cd ${params.WORK_DIR}
echo "=== 虚拟环境准备完成 ==="
ENDSSH
"""
                }
            }
        }
        
        stage('运行lm-evaluation测试') {
            when {
                expression { env.CONNECTIVITY_FAILED != 'true' }
            }
            steps {
                script {
                    def taskList = []
                    if (params.TASK_MMLU_PRO) taskList.add('mmlu_pro')
                    if (params.TASK_GSM_PLUS) taskList.add('gsm_plus')
                    if (params.TASK_RULER) taskList.add('ruler')
                    if (taskList.isEmpty()) {
                        error '至少需要选择一个测试任务'
                    }
                    env.TASKS = taskList.join(',')
                    
                    def modelDir = params.MODEL.contains("/") ? params.MODEL.split("/").last() : params.MODEL
                    env.MODEL_DIR = modelDir
                    
                    env.API_KEY_STR = params.API_KEY?.toString() ?: ''
                    
                    sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                        catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                                sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << ENDSSH
set -e
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
cd ${params.WORK_DIR}
source .venv/bin/activate
echo "=== 参数信息 ==="
echo "TESTER: ${params.TESTER}"
echo "BUILD_NUMBER: ${BUILD_NUMBER}"
echo "CHIP: ${params.CHIP}"
echo "MODEL: ${params.MODEL}"
echo "MODEL_PATH: ${params.MODEL_PATH}"
echo "BASE_URL: ${params.BASE_URL}"
echo "CHAT_API: ${params.CHAT_API}"
echo "TASKS: ${env.TASKS}"
echo "LIMIT: ${params.LIMIT}"
echo "RULER_LIMIT: ${params.RULER_LIMIT}"
echo "LMEVAL_LOG_LEVEL: ${params.LMEVAL_LOG_LEVEL}"
echo "=== 执行Python测试脚本 ==="
python3 run_eval.py \
    --tester ${params.TESTER} \
    --build-number ${BUILD_NUMBER} \
    --chip ${params.CHIP} \
    --model ${params.MODEL} \
    --model-path "${params.MODEL_PATH}" \
    --base-url ${params.BASE_URL} \
    --api-key "${env.API_KEY_STR ?: 'abc123'}" \
    --chat-api "${params.CHAT_API}" \
    --tasks ${env.TASKS} \
    --limit "${params.LIMIT}" \
    --ruler-limit "${params.RULER_LIMIT}" \
    --log-level "${params.LMEVAL_LOG_LEVEL}"
echo "=== 测试脚本执行结束 ==="
echo "=== 输出目录 ==="
find output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${env.MODEL_DIR}/ -type f
ENDSSH
"""
                        }
                    }
                }
            }
        }
        
        stage('拉取测试结果') {
            steps {
                sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                    catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                        script {
                            def remoteDir = "${params.WORK_DIR}/output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${env.MODEL_DIR}"
                            def localDir = "reports/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}"
                            def localBuildsDir = "builds/${BUILD_NUMBER}"
                            env.RESULT_DIR = "output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${env.MODEL_DIR}"
                            echo "拉取测试结果目录: ${remoteDir}"

                            if (env.CONNECTIVITY_FAILED == 'true') {
                                echo "=== 连通性检查未通过,跳过测试结果目录拉取,仅拉取连通性预检日志 ==="
                            } else {
                                sh """
mkdir -p ${localDir}
scp -o StrictHostKeyChecking=no \
    -r ${REMOTE_USER}@${REMOTE_HOST}:${remoteDir} \
    ${localDir}/
echo "=== 拉取结果 ==="
find ${localDir}/ -type f
"""
                            }

                            sh """
mkdir -p ${localBuildsDir}
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ${REMOTE_USER}@${REMOTE_HOST}:/tmp/lm_eval_connectivity_${BUILD_NUMBER}.log \
    ./${localBuildsDir}/lm_eval_connectivity_${BUILD_NUMBER}.log 2>/dev/null \
    && echo "连通性预检日志已拉取: ${localBuildsDir}/lm_eval_connectivity_${BUILD_NUMBER}.log" \
    || echo "WARN: 连通性预检日志拉取失败"
"""
                        }
                    }
                }
            }
        }
        
        stage('发送邮件') {
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                    script {
                        def logContent = ""
                        def logFile = ""
                        def logFileBase = "reports/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${env.MODEL_DIR}"
                        
                        def files = findFiles(glob: "${logFileBase}/**/lm-eval-*.log")
                        if (files.length > 0) {
                            logFile = files[0].path
                            logContent = readFile(logFile)
                        }

                        // 检测连通性预检失败: 优先读取本地已拉取的连通性日志
                        def connectivityLogPath = "builds/${BUILD_NUMBER}/lm_eval_connectivity_${BUILD_NUMBER}.log"
                        def connectivityLogContent = ""
                        def failureReason = ""
                        def connectivityFailureReason = ""
                        if (fileExists(connectivityLogPath)) {
                            connectivityLogContent = readFile(connectivityLogPath)
                            if (connectivityLogContent.contains("API 连通性检查失败") ||
                                connectivityLogContent.contains("Chat Completions 接口检查失败")) {
                                failureReason = "连通性检查未通过"
                                println("DEBUG: 识别到连通性检查失败, 失败原因: ${failureReason}")
                                // 提取失败段落: 从 "=== 检查 ..." 段头开始,
                                // 到下一个 "=== ..." 段头之前结束
                                def logLines = connectivityLogContent.split('\n')
                                def collected = []
                                def inFailureSection = false
                                for (def ll : logLines) {
                                    if (ll.contains("检查 API 连通性") || ll.contains("Chat Completions 接口检查")) {
                                        inFailureSection = true
                                    }
                                    if (inFailureSection) {
                                        if (!collected.isEmpty() && ll.trim().startsWith("===") &&
                                            !ll.contains("检查 API 连通性") && !ll.contains("Chat Completions 接口检查")) {
                                            break
                                        }
                                        collected.add(ll)
                                    }
                                }
                                connectivityFailureReason = collected.join('\n').trim()
                            }
                        } else {
                            println("DEBUG: 未找到连通性预检日志: ${connectivityLogPath}")
                        }
                        // 兜底: 即使日志文件未拉到, 也通过 env 变量判定
                        if (!failureReason && env.CONNECTIVITY_FAILED == 'true') {
                            failureReason = "连通性检查未通过"
                            connectivityFailureReason = "API 连通性或 Chat Completions 接口检查失败,具体日志未拉到,详见 Jenkins 控制台输出。"
                        }

                        def hasResult = logContent.length() > 0
                        def resultStatus = hasResult ? "完成" : "失败/无结果"
                        if (failureReason) {
                            resultStatus = "失败/${failureReason}"
                        }
                        
                        def mmluProTable = extractLmEvalTable(logContent, "mmlu_pro")
                        def gsmPlusTable = extractLmEvalTable(logContent, "gsm_plus")
                        def rulerTable = extractLmEvalTable(logContent, "ruler")
                        
                        def mmluProScore = extractMainScore(logContent, "mmlu_pro")
                        def gsmPlusScore = extractMainScore(logContent, "gsm_plus")
                        def rulerScore = extractMainScore(logContent, "ruler")
                        
                        def taskSummaryRows = ""
                        if (failureReason) {
                            taskSummaryRows = "<tr><td colspan='2'>连通性检查未通过,任务未执行</td></tr>"
                        } else {
                            if (env.TASKS?.contains("mmlu_pro")) {
                                taskSummaryRows += "<tr><td>mmlu_pro</td><td>${mmluProScore}</td></tr>"
                            }
                            if (env.TASKS?.contains("gsm_plus")) {
                                taskSummaryRows += "<tr><td>gsm_plus</td><td>${gsmPlusScore}</td></tr>"
                            }
                            if (env.TASKS?.contains("ruler")) {
                                taskSummaryRows += "<tr><td>ruler</td><td>${rulerScore}</td></tr>"
                            }
                            if (taskSummaryRows.isEmpty()) {
                                taskSummaryRows = "<tr><td colspan='2'>无任务执行</td></tr>"
                            }
                        }

                        // 构建连通性检查失败的提示 HTML (HTML 转义)
                        def connectivityFailureHtml = ""
                        if (failureReason) {
                            def escapedReason = (connectivityFailureReason ?: '')
                                .replace('&', '&amp;')
                                .replace('<', '&lt;')
                                .replace('>', '&gt;')
                            connectivityFailureHtml = """
            <div style="background-color: #ffebee; color: #000000; border-left: 4px solid #d32f2f; padding: 12px 15px; margin-top: 15px; border-radius: 3px;">
                <h3 style="color: #d32f2f; margin-top: 0; margin-bottom: 8px;">⚠️ 连通性检查未通过</h3>
                <p style="margin-top: 0; margin-bottom: 8px; color: #000000;">本次测试未能正常执行用例,原因是 API 连通性检查失败:</p>
                <pre style="background-color: #ffffff; color: #000000; padding: 10px; border-radius: 3px; overflow-x: auto; white-space: pre-wrap; margin: 0; font-family: Menlo, Consolas, monospace; font-size: 12px;">${escapedReason}</pre>
            </div>"""
                        }
                        
                        def emailBody = """
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: #fff; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .header { background-color: ${hasResult ? '#4CAF50' : '#f44336'}; color: white; padding: 20px; border-radius: 5px 5px 0 0; }
        .content { padding: 20px; }
        table { border-collapse: collapse; width: 100%; margin-top: 15px; font-size: 13px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .footer { margin-top: 20px; padding: 15px; background-color: #f9f9f9; border-radius: 0 0 5px 5px; color: #666; font-size: 12px; }
        .section-title { background-color: #e3f2fd; padding: 10px; margin-top: 20px; border-radius: 3px; font-weight: bold; }
        .score-highlight { background-color: #c8e6c9; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2 style="margin: 0;">lm-evaluation-harness 精度测试报告 - 构建 #${BUILD_NUMBER}</h2>
        </div>
        <div class="content">
            <h3>测试概要</h3>
            <table>
                <tr><th>项目</th><td>值</td></tr>
                <tr><th>构建编号</th><td>#${BUILD_NUMBER}</td></tr>
                <tr><th>测试人员</th><td>${params.TESTER}</td></tr>
                <tr><th>芯片平台</th><td>${params.CHIP}</td></tr>
                <tr><th>推理框架</th><td>${params.ENGINE}</td></tr>
                <tr><th>模型名称</th><td>${params.MODEL}</td></tr>
                <tr><th>模型路径</th><td>${params.MODEL_PATH}</td></tr>
                <tr><th>API地址</th><td>${params.BASE_URL}</td></tr>
                <tr><td>PD分离模式</td><td>${params.PD}</td></tr>
                <tr><th>接口类型</th><td>${params.CHAT_API}</td></tr>
                <tr><th>测试任务</th><td>${env.TASKS ?: (failureReason ? '未执行(连通性检查未通过)' : 'N/A')}</td></tr>
                <tr><th>样本限制</th><td>${params.LIMIT ?: '无限制'}</td></tr>
                <tr><th>Ruler样本限制</th><td>${params.RULER_LIMIT}</td></tr>
                <tr><th>执行时间</th><td>${currentBuild.durationString}</td></tr>
                <tr><th>测试状态</th><td>${resultStatus}</td></tr>
                <tr><th>构建状态</th><td>${currentBuild.currentResult}</td></tr>
            </table>

            ${connectivityFailureHtml}

            <h3>任务汇总得分</h3>
            <table>
                <tr style="background-color: #e3f2fd;"><th>任务名称</th><th>得分</th></tr>
                ${taskSummaryRows}
            </table>
"""
                        
                        if (!failureReason && env.TASKS?.contains("mmlu_pro") && mmluProTable) {
                            emailBody += """
            <div class="section-title">MMLU_PRO 任务测试结果</div>
            ${mmluProTable}
"""
                        }

                        if (!failureReason && env.TASKS?.contains("gsm_plus") && gsmPlusTable) {
                            emailBody += """
            <div class="section-title">GSM_PLUS 任务测试结果</div>
            ${gsmPlusTable}
"""
                        }

                        if (!failureReason && env.TASKS?.contains("ruler") && rulerTable) {
                            emailBody += """
            <div class="section-title">RULER 任务测试结果</div>
            ${rulerTable}
"""
                        }
                        
                        emailBody += """
            <h3>输出目录</h3>
            <p>${failureReason ? 'N/A (连通性检查未通过)' : (env.RESULT_DIR ?: 'N/A')}</p>
            
            <p style="margin-top: 20px;">详细日志请查看附件。</p>
            <p>Jenkins 构建地址: <a href="${env.BUILD_URL}">${env.BUILD_URL}</a></p>
        </div>
        <div class="footer">
            此邮件由 Jenkins 自动发送，请勿回复。
        </div>
    </div>
</body>
</html>"""
                        
                        echo "=== lm-evaluation-harness 测试结果 ==="
                        echo "Build Number: ${BUILD_NUMBER}"
                        echo "结果目录: ${env.RESULT_DIR ?: 'N/A'}"
                        echo "测试状态: ${resultStatus}"
                        echo "mmlu_pro 得分: ${mmluProScore}"
                        echo "gsm_plus 得分: ${gsmPlusScore}"
                        echo "ruler 得分: ${rulerScore}"
                        
                        def attachPattern = ""
                        def attachPatterns = []
                        if (logFile) {
                            attachPatterns.add(logFile)
                        }
                        if (fileExists("builds/${BUILD_NUMBER}/lm_eval_connectivity_${BUILD_NUMBER}.log")) {
                            attachPatterns.add("builds/${BUILD_NUMBER}/lm_eval_connectivity_${BUILD_NUMBER}.log")
                        }
                        attachPattern = attachPatterns.join(',')
                        emailext(
                            subject: "[模型推理 - lm-evaluation精度测试报告] #${BUILD_NUMBER} ${params.CHIP} - ${params.MODEL}",
                            body: emailBody,
                            to: "${params.RECIPIENTS}",
                            mimeType: 'text/html',
                            attachmentsPattern: attachPattern
                        )
                    }
                }
            }
        }
    }
    post {
        always {
            script {
                archiveArtifacts artifacts: "reports/${params.TESTER}/${BUILD_NUMBER}/**,builds/${BUILD_NUMBER}/**", allowEmptyArchive: true, fingerprint: true
                echo "构建完成: ${currentBuild.currentResult}"
            }
        }
        cleanup {
            cleanWs()
        }
    }
}

def extractLmEvalTable(String content, String tName) {
    def lines = content.split('\n')
    def taskRows = []
    def groupRows = []
    def inSection = false
    def currentTable = null
    
    for (int i = 0; i < lines.size(); i++) {
        def line = lines[i].trim()
        
        if (line.contains("Running Task: ${tName}")) {
            inSection = true
            taskRows = []
            groupRows = []
            currentTable = null
        }
        if (!inSection) continue
        if (line.contains("Running Task:") && !line.contains(tName)) {
            inSection = false
            continue
        }
        
        if (line.startsWith("|") && line.contains("Tasks") && line.contains("Version") && line.contains("Metric")) {
            currentTable = 'tasks'
            continue
        }
        if (line.startsWith("|") && line.contains("Groups") && line.contains("Version")) {
            currentTable = 'groups'
            continue
        }
        if (line.startsWith("|") && line.contains("---")) continue
        if (!line.startsWith("|")) continue
        if (currentTable == null) continue
        
        def row = parsePipeRow(line)
        if (row != null) {
            if (currentTable == 'tasks') taskRows.add(row)
            else groupRows.add(row)
        }
    }
    
    if (taskRows.isEmpty() && groupRows.isEmpty()) return ""
    
    def html = ""
    
    def summaryRow = null
    if (groupRows.size() > 0) {
        summaryRow = groupRows[0]
    } else {
        for (def r : taskRows) {
            if (r.name == tName) { summaryRow = r; break }
        }
    }
    
    if (tName == "ruler") {
        def subVals = []
        for (def r : taskRows) {
            if (r.name.startsWith("-") && r.value != "" && r.value != "N/A") {
                subVals.add(r)
            }
        }
        if (summaryRow == null && subVals.size() > 0) {
            def ref = subVals[0]
            def sum = 0.0
            def count = 0
            for (def r : subVals) {
                sum += r.value.toDouble()
                count++
            }
            def avgVal = count > 0 ? String.format("%.4f", sum / count) : "N/A"
            summaryRow = [name: "ruler", version: ref.version, filter: ref.filter, nshot: ref.nshot, metric: ref.metric, value: avgVal, stderr: "N/A"]
        } else if (summaryRow != null && (summaryRow.value == "" || summaryRow.value == "N/A") && subVals.size() > 0) {
            def sum = 0.0
            def count = 0
            for (def r : subVals) {
                sum += r.value.toDouble()
                count++
            }
            if (count > 0) {
                summaryRow.value = String.format("%.4f", sum / count)
                summaryRow.stderr = "N/A"
            }
        }
    }
    
    def subTaskRows = []
    def siblingRows = []
    for (def r : taskRows) {
        if (r.name.startsWith("-") || r.name.startsWith(" -")) {
            subTaskRows.add(r)
        } else if (r.name == "" && r.filter != "") {
            siblingRows.add(r)
        }
    }
    
    html += "<table><tr><th>任务</th><th>Version</th><th>Filter</th><th>n-shot</th><th>Metric</th><th>Value</th><th>Stderr</th></tr>"
    if (summaryRow != null) {
        html += "<tr class=\"score-highlight\"><td>${summaryRow.name}</td><td>${summaryRow.version}</td><td>${summaryRow.filter}</td><td>${summaryRow.nshot}</td><td>${summaryRow.metric}</td><td>${summaryRow.value}</td><td>${summaryRow.stderr}</td></tr>"
    }
    for (def r : siblingRows) {
        html += "<tr><td>${tName}</td><td>${r.version}</td><td>${r.filter}</td><td>${r.nshot}</td><td>${r.metric}</td><td>${r.value}</td><td>${r.stderr}</td></tr>"
    }
    html += "</table>"
    
    if (subTaskRows.size() > 0) {
        html += "<table style=\"margin-top: 10px;\"><tr><th>子任务</th><th>Version</th><th>Filter</th><th>n-shot</th><th>Metric</th><th>Value</th><th>Stderr</th></tr>"
        for (def r : subTaskRows) {
            html += "<tr style=\"background-color: #f9f9f9;\"><td>${r.name}</td><td>${r.version}</td><td>${r.filter}</td><td>${r.nshot}</td><td>${r.metric}</td><td>${r.value}</td><td>${r.stderr}</td></tr>"
        }
        html += "</table>"
    }
    
    return html
}

def parsePipeRow(String line) {
    def rawCells = line.split("\\|", -1)
    def cells = rawCells.collect { it.trim() }
    
    def upIdx = -1
    def pmIdx = -1
    for (int i = 0; i < cells.size(); i++) {
        if (cells[i] == '↑') upIdx = i
        if (cells[i] == '±') pmIdx = i
    }
    
    def value = ""
    def stderr = ""
    if (upIdx >= 0 && upIdx + 1 < cells.size()) value = cells[upIdx + 1].trim()
    if (pmIdx >= 0 && pmIdx + 1 < cells.size()) stderr = cells[pmIdx + 1].trim()
    
    def name = cells.size() > 1 ? cells[1].trim() : ""
    def version = cells.size() > 2 ? cells[2].trim() : ""
    def filter = cells.size() > 3 ? cells[3].trim() : ""
    def nshot = cells.size() > 4 ? cells[4].trim() : ""
    def metric = cells.size() > 5 ? cells[5].trim() : ""
    
    if (name == "" && value == "" && metric == "") return null
    
    return [name: name, version: version, filter: filter, nshot: nshot, metric: metric, value: value, stderr: stderr]
}

def extractMainScore(String content, String tName) {
    def lines = content.split('\n')
    
    if (tName == "gsm_plus") {
        for (int i = 0; i < lines.size(); i++) {
            def line = lines[i].trim()
            if (!line.startsWith("|")) continue
            if (!line.contains("strict-match")) continue
            def row = parsePipeRow(line)
            if (row != null && row.value != "" && row.value != "N/A") {
                return row.value
            }
        }
    }
    
    for (int i = 0; i < lines.size(); i++) {
        def line = lines[i].trim()
        if (!line.startsWith("|")) continue
        if (!line.contains(tName)) continue
        
        def row = parsePipeRow(line)
        if (row != null && row.name == tName && row.value != "" && row.value != "N/A") {
            def prev = i > 0 ? lines[i - 1].trim() : ""
            if (prev.contains("Groups") || prev.contains("---")) {
                return row.value
            }
        }
    }
    
    for (int i = 0; i < lines.size(); i++) {
        def line = lines[i].trim()
        if (!line.startsWith("|")) continue
        if (!line.contains(tName)) continue
        
        def row = parsePipeRow(line)
        if (row != null && row.name == tName && row.value != "" && row.value != "N/A") {
            if (!line.contains(" -")) {
                return row.value
            }
        }
    }
    
    if (tName == "ruler") {
        def sum = 0.0
        def count = 0
        for (int i = 0; i < lines.size(); i++) {
            def line = lines[i].trim()
            if (!line.startsWith("|")) continue
            if (!line.contains("niah") && !line.contains("ruler_")) continue
            if (!line.contains(" -")) continue
            
            def row = parsePipeRow(line)
            if (row != null && row.value != "" && row.value != "N/A") {
                sum += row.value.toDouble()
                count++
            }
        }
        if (count > 0) {
            return String.format("%.4f", sum / count)
        }
    }
    
    return "N/A"
}