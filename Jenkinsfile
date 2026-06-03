pipeline {
    agent any
    parameters {
        string(name: 'TESTER', description: '测试人员名称 (必填)')
        choice(name: 'INFRA', choices: ['vllm', 'sglang'], description: '推理框架')
        choice(name: 'PD', choices: ['agg', 'disagg'], description: 'PD分离模式,agg 表示非 PD 分离, disagg 表示 PD 分离')
        string(name: 'CHIP', defaultValue: 'nvidia-h100', description: '芯片平台名称 (必填)')
        string(name: 'MODEL', defaultValue: 'kimi-k2.5', description: '模型服务名称 (必填)')
        string(name: 'MODEL_PATH', defaultValue: '/dingofs/data1/userdata/llms/moonshotai/Kimi-K2.6', description: '模型本地路径 (必填)')
        string(name: 'BASE_URL', defaultValue: 'http://10.201.149.10:8080', description: 'API 地址 (必填)')
        booleanParam(name: 'TASK_MMLU_PRO', defaultValue: true, description: '运行 mmlu_pro 任务')
        booleanParam(name: 'TASK_GSM_PLUS', defaultValue: false, description: '运行 gsm_plus 任务')
        booleanParam(name: 'TASK_RULER', defaultValue: false, description: '运行 ruler 任务')
        string(name: 'LIMIT', defaultValue: '10', description: '限制每个任务运行的样本数量 (非必填，为空则不限制，针对除Ruler任务以外的其他任务)')
        string(name: 'RULER_LIMIT', defaultValue: '32', description: '仅针对Ruler任务样本限制 (默认32)')
        text(name: 'RECIPIENTS', defaultValue: 'liwt@zetyun.com', description: '邮件接收者（逗号分隔）')
        string(name: 'WORK_DIR', defaultValue: '/dingofs/data1/userdata/liwt/maas-image/lm-evaluation-harness', description: '远程工作目录')
    }
    environment {
        SSH_CREDENTIALS = 'HOST_SSH_KEY'
        API_KEY_CREDENTIALS = 'API_KEY'
        REMOTE_HOST = '10.201.132.50'
        REMOTE_USER = 'root'
    }
    
    stages {
        stage('环境检查') {
            steps {
                sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                    sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << 'ENDSSH'
set -e
cd ${params.WORK_DIR}
echo "工作目录: \$(pwd)"
ls -la

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
                    
                    withCredentials([string(credentialsId: "${API_KEY_CREDENTIALS}", variable: 'API_KEY')]) {
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
echo "TASKS: ${env.TASKS}"
echo "LIMIT: ${params.LIMIT}"
echo "RULER_LIMIT: ${params.RULER_LIMIT}"
echo "=== 执行Python测试脚本 ==="
python3 run_eval.py \
    --tester ${params.TESTER} \
    --build-number ${BUILD_NUMBER} \
    --chip ${params.CHIP} \
    --model ${params.MODEL} \
    --model-path "${params.MODEL_PATH}" \
    --base-url ${params.BASE_URL} \
    --api-key ${API_KEY} \
    --tasks ${env.TASKS} \
    --limit "${params.LIMIT}" \
    --ruler-limit "${params.RULER_LIMIT}"
echo "=== 测试脚本执行结束 ==="
echo "=== 输出目录 ==="
find output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${params.MODEL}/ -type f
ENDSSH
"""
                            }
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
                            def remoteDir = "${params.WORK_DIR}/output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${params.MODEL}"
                            def localDir = "reports/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}"
                            env.RESULT_DIR = "output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${params.MODEL}"
                            echo "拉取测试结果目录: ${remoteDir}"
                            sh """
mkdir -p ${localDir}
scp -o StrictHostKeyChecking=no \
    -r ${REMOTE_USER}@${REMOTE_HOST}:${remoteDir} \
    ${localDir}/
echo "=== 拉取结果 ==="
find ${localDir}/ -type f
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
                        def logFileBase = "reports/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${params.MODEL}"
                        
                        def files = findFiles(glob: "${logFileBase}/**/lm-eval-*.log")
                        if (files.length > 0) {
                            logFile = files[0].path
                            logContent = readFile(logFile)
                        }
                        
                        def hasResult = logContent.length() > 0
                        def resultStatus = hasResult ? "完成" : "失败/无结果"
                        
                        def mmluProTable = extractLmEvalTable(logContent, "mmlu_pro")
                        def gsmPlusTable = extractLmEvalTable(logContent, "gsm_plus")
                        def rulerTable = extractLmEvalTable(logContent, "ruler")
                        
                        def mmluProScore = extractMainScore(logContent, "mmlu_pro")
                        def gsmPlusScore = extractMainScore(logContent, "gsm_plus")
                        def rulerScore = extractMainScore(logContent, "ruler")
                        
                        def taskSummaryRows = ""
                        if (env.TASKS.contains("mmlu_pro")) {
                            taskSummaryRows += "<tr><td>mmlu_pro</td><td>${mmluProScore}</td></tr>"
                        }
                        if (env.TASKS.contains("gsm_plus")) {
                            taskSummaryRows += "<tr><td>gsm_plus</td><td>${gsmPlusScore}</td></tr>"
                        }
                        if (env.TASKS.contains("ruler")) {
                            taskSummaryRows += "<tr><td>ruler</td><td>${rulerScore}</td></tr>"
                        }
                        if (taskSummaryRows.isEmpty()) {
                            taskSummaryRows = "<tr><td colspan='2'>无任务执行</td></tr>"
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
                <tr><th>构建编号</th><td>#${BUILD_NUMBER}</td></tr>
                <tr><th>测试人员</th><td>${params.TESTER}</td></tr>
                <tr><th>芯片平台</th><td>${params.CHIP}</td></tr>
                <tr><th>模型名称</th><td>${params.MODEL}</td></tr>
                <tr><th>模型路径</th><td>${params.MODEL_PATH}</td></tr>
                <tr><th>API地址</th><td>${params.BASE_URL}</td></tr>
                <tr><th>测试任务</th><td>${env.TASKS}</td></tr>
                <tr><th>样本限制</th><td>${params.LIMIT ?: '无限制'}</td></tr>
                <tr><th>Ruler样本限制</th><td>${params.RULER_LIMIT}</td></tr>
                <tr><th>执行时间</th><td>${currentBuild.durationString}</td></tr>
                <tr><th>测试状态</th><td>${resultStatus}</td></tr>
                <tr><th>构建状态</th><td>${currentBuild.currentResult}</td></tr>
            </table>
            
            <h3>任务汇总得分</h3>
            <table>
                <tr style="background-color: #e3f2fd;"><th>任务名称</th><th>得分</th></tr>
                ${taskSummaryRows}
            </table>
"""
                        
                        if (env.TASKS.contains("mmlu_pro") && mmluProTable) {
                            emailBody += """
            <div class="section-title">MMLU_PRO 任务测试结果</div>
            ${mmluProTable}
"""
                        }
                        
                        if (env.TASKS.contains("gsm_plus") && gsmPlusTable) {
                            emailBody += """
            <div class="section-title">GSM_PLUS 任务测试结果</div>
            ${gsmPlusTable}
"""
                        }
                        
                        if (env.TASKS.contains("ruler") && rulerTable) {
                            emailBody += """
            <div class="section-title">RULER 任务测试结果</div>
            ${rulerTable}
"""
                        }
                        
                        emailBody += """
            <h3>输出目录</h3>
            <p>${env.RESULT_DIR ?: 'N/A'}</p>
            
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
                        
                        def attachPattern = logFile ? "${logFile}" : ""
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
                archiveArtifacts artifacts: "reports/${params.TESTER}/${BUILD_NUMBER}/**", allowEmptyArchive: true, fingerprint: true
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
    
    return "N/A"
}