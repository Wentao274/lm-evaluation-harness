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
    --ruler-limit "${params.RULER_LIMIT}" 2>&1 | tee output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${params.MODEL}/lm_eval_results.log
echo "=== 测试脚本执行结束 ==="
echo "=== 输出目录 ==="
find output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${params.MODEL}/ -type d
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
                        def logContent = ""
                        def logFile = ""
                        if (env.RESULT_DIR) {
                            def logFile1 = "reports/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${params.MODEL}/lm_eval_results.log"
                            def logFile2 = "reports/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${params.MODEL}/test.log"
                            logFile = fileExists(logFile1) ? logFile1 : (fileExists(logFile2) ? logFile2 : "")
                            logContent = logFile ? readFile(logFile) : ""
                        }
                        
                        def taskResults = []
                        def taskDirs = []
                        def lines = logContent.split('\n')
                        for (int i = 0; i < lines.size(); i++) {
                            def line = lines[i]
                            if (line.contains('Running') && line.contains('with run_task')) {
                                def taskMatch = line =~ /Running (\S+) with run_task_(\S+)/
                                if (taskMatch.find()) {
                                    taskDirs.add([name: taskMatch.group(1), runner: taskMatch.group(2)])
                                }
                            }
                        }
                        
                        def htmlRows = ""
                        if (taskDirs.isEmpty()) {
                            htmlRows = "<tr><td colspan='2'>无任务执行信息</td></tr>"
                        } else {
                            taskDirs.each { task ->
                                htmlRows += """
                                <tr>
                                    <td>${task.name}</td>
                                    <td>使用 ${task.runner} 执行</td>
                                </tr>
                                """
                            }
                        }
                        
                        def hasResult = logContent.length() > 0
                        def resultStatus = hasResult ? "完成" : "失败/无结果"
                        
                        def emailBody = """
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 900px; margin: 0 auto; background-color: #fff; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .header { background-color: ${hasResult ? '#4CAF50' : '#f44336'}; color: white; padding: 20px; border-radius: 5px 5px 0 0; }
        .content { padding: 20px; }
        table { border-collapse: collapse; width: 100%; margin-top: 15px; }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
        th { background-color: #f2f2f2; }
        .footer { margin-top: 20px; padding: 15px; background-color: #f9f9f9; border-radius: 0 0 5px 5px; color: #666; font-size: 12px; }
        pre { background-color: #f4f4f4; padding: 10px; overflow-x: auto; border-radius: 3px; }
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
            
            <h3>执行任务</h3>
            <table>
                <tr style="background-color: #e3f2fd;"><th>任务名称</th><th>执行方式</th></tr>
                ${htmlRows}
            </table>
            
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
                        echo "任务列表: ${taskDirs}"
                        emailext(
                            subject: "[模型推理 - lm-evaluation测试报告] #${BUILD_NUMBER} ${params.CHIP} - ${params.MODEL}",
                            body: emailBody,
                            to: "${params.RECIPIENTS}",
                            mimeType: 'text/html'
                        )
                    }
                }
            }
        }
    }
    post {
        always {
            script {
                archiveArtifacts artifacts: "reports/${params.TESTER}/${env.BUILD_NUMBER}/**", allowEmptyArchive: true, fingerprint: true
                echo "构建完成: ${currentBuild.currentResult}"
            }
        }
        cleanup {
            cleanWs()
        }
    }
}