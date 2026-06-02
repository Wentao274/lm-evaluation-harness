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
        string(name: 'TASKS', defaultValue: 'mmlu_pro', description: '测试任务 ( 必填，多个使用逗号分隔, 如: mmlu_pro,gsm_plus,ruler）')
        string(name: 'LIMIT', defaultValue: '', description: '限制每个任务运行的样本数量 (非必填，为空则不限制，针对除Ruler任务以外的其他任务)')
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
chmod -R 755 ./*
chmod +x lm_eval_test.sh
ENDSSH
"""
                }
            }
        }
        
        stage('运行lm-evaluation测试') {
            steps {
                script {
                    withCredentials([string(credentialsId: "${API_KEY_CREDENTIALS}", variable: 'API_KEY')]) {
                        sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                            catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                                sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << ENDSSH
set -e
cd ${params.WORK_DIR}
echo "=== 参数信息 ==="
echo "TESTER: ${params.TESTER}"
echo "BUILD_NUMBER: ${BUILD_NUMBER}"
echo "CHIP: ${params.CHIP}"
echo "MODEL: ${params.MODEL}"
echo "MODEL_PATH: ${params.MODEL_PATH}"
echo "BASE_URL: ${params.BASE_URL}"
echo "TASKS: ${params.TASKS}"
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
    --tasks ${params.TASKS} \
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
                            def targetDir = "output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${params.MODEL}"
                            def localDir = "reports/${params.TESTER}/${BUILD_NUMBER}"
                            env.RESULT_DIR = targetDir
                            echo "拉取测试结果目录: ${targetDir}"
                            sh """
mkdir -p ${localDir}
scp -o StrictHostKeyChecking=no \
    -r ${REMOTE_USER}@${REMOTE_HOST}:${params.WORK_DIR}/${targetDir} \
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
                        def tasksUnderscore = params.TASKS.replace(',', '-')
                        def logFileBase = "reports/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${params.MODEL}"
                        def logFilePattern = "${logFileBase}/lm-eval-*.log"
                        def logFile = ""
                        def logContent = ""
                        
                        def files = findFiles(glob: logFilePattern)
                        if (files.length > 0) {
                            logFile = files[0].path
                            logContent = readFile(logFile)
                        } else {
                            def logFileAlt = "${logFileBase}/test.log"
                            if (fileExists(logFileAlt)) {
                                logContent = readFile(logFileAlt)
                                logFile = logFileAlt
                            }
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
                        if (params.TASKS.contains("mmlu_pro")) {
                            taskSummaryRows += "<tr><td>mmlu_pro</td><td>${mmluProScore}</td></tr>"
                        }
                        if (params.TASKS.contains("gsm_plus")) {
                            taskSummaryRows += "<tr><td>gsm_plus</td><td>${gsmPlusScore}</td></tr>"
                        }
                        if (params.TASKS.contains("ruler")) {
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
        pre { background-color: #f4f4f4; padding: 10px; overflow-x: auto; border-radius: 3px; font-size: 12px; }
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
                <tr><th>测试任务</th><td>${params.TASKS}</td></tr>
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
                        
                        if (params.TASKS.contains("mmlu_pro") && mmluProTable) {
                            emailBody += """
            <div class="section-title">MMLU_PRO 任务测试结果</div>
            <table>
                ${mmluProTable}
            </table>
"""
                        }
                        
                        if (params.TASKS.contains("gsm_plus") && gsmPlusTable) {
                            emailBody += """
            <div class="section-title">GSM_PLUS 任务测试结果</div>
            <table>
                ${gsmPlusTable}
            </table>
"""
                        }
                        
                        if (params.TASKS.contains("ruler") && rulerTable) {
                            emailBody += """
            <div class="section-title">RULER 任务测试结果</div>
            <table>
                ${rulerTable}
            </table>
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
                        
                        emailext(
                            subject: "[模型推理 - lm-evaluation测试报告] #${BUILD_NUMBER} ${params.CHIP} - ${params.MODEL}",
                            body: emailBody,
                            to: "${params.RECIPIENTS}",
                            mimeType: 'text/html',
                            attachmentsPattern: logFilePattern
                        )
                    }
                }
            }
        }
    }
    post {
        always {
            script {
                def logFilePattern = "reports/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${params.MODEL}/*"
                archiveArtifacts artifacts: logFilePattern, allowEmptyArchive: true, fingerprint: true
                echo "构建完成: ${currentBuild.currentResult}"
            }
        }
        cleanup {
            cleanWs()
        }
    }
}

def extractLmEvalTable(String content, String taskName) {
    def lines = content.split('\n')
    def inTable = false
    def tableLines = []
    def headerFound = false
    
    for (int i = 0; i < lines.size(); i++) {
        def line = lines[i]
        
        if (line.contains("Running Task: ${taskName}") || (taskName == "mmlu_pro" && line.contains("|mmlu_pro"))) {
            inTable = true
            headerFound = false
        }
        
        if (inTable && line =~ /\|.*\|.*\|/) {
            def trimmed = line.trim()
            if (trimmed && trimmed.startsWith("|")) {
                if (trimmed.contains("Tasks") || trimmed.contains("Groups") || trimmed.contains("Version") || trimmed.contains("-") || trimmed.contains("mmlu_pro") || trimmed.contains("gsm_plus") || trimmed.contains("ruler") || trimmed.contains("niah") || trimmed.contains("ruler_")) {
                    tableLines.add(trimmed)
                    headerFound = true
                }
            }
        } else if (inTable && headerFound && line.trim() && !line.trim().startsWith("|") && !line.contains("Running")) {
            inTable = false
        }
    }
    
    if (tableLines.isEmpty()) {
        return ""
    }
    
    def html = "<tr><th>任务</th><th>Version</th><th>Filter</th><th>n-shot</th><th>Metric</th><th>Value</th><th>Stderr</th></tr>"
    
    tableLines.each { line ->
        def cells = line.split("\\|").collect { it.trim() }.findAll { it }
        if (cells.size() >= 5) {
            def taskName = cells[0]
            def version = cells.size() > 1 ? cells[1] : ""
            def filter = cells.size() > 2 ? cells[2] : ""
            def nshot = cells.size() > 3 ? cells[3] : ""
            def metric = cells.size() > 4 ? cells[4] : ""
            def value = cells.size() > 5 ? cells[5] : ""
            def stderr = cells.size() > 6 ? cells[6] : ""
            
            def rowClass = ""
            if (taskName.contains("-")) {
                rowClass = "style=\"background-color: #f9f9f9;\""
            } else if (taskName == "mmlu_pro" || taskName == "gsm_plus" || taskName == "ruler" || taskName == "Groups" || taskName == "mmlu_pro") {
                rowClass = "class=\"score-highlight\""
            }
            
            html += "<tr ${rowClass}><td>${taskName}</td><td>${version}</td><td>${filter}</td><td>${nshot}</td><td>${metric}</td><td>${value}</td><td>${stderr}</td></tr>"
        }
    }
    
    return html
}

def extractMainScore(String content, String taskName) {
    def pattern = ""
    if (taskName == "mmlu_pro") {
        pattern = /\|mmlu_pro\s+\|\s*(\d+)\|.*?\|(\d+\.\d+)\|/
    } else if (taskName == "gsm_plus") {
        pattern = /\|gsm_plus\s+\|\s*(\d+)\|.*?\|(\d+\.\d+)\|/
    } else if (taskName == "ruler") {
        pattern = /\|Groups\|.*?\|(\d+\.\d+)\|/
    }
    
    def matcher = content =~ pattern
    if (matcher.find()) {
        return matcher.group(2)
    }
    return "N/A"
}