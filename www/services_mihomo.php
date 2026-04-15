<?php
require_once("guiconfig.inc");
include("head.inc");
include("fbegin.inc");

// 配置文件路径
$config_file = "/usr/local/etc/mihomo/config.yaml";
$log_file = "/var/log/mihomo.log";
$message = "";
$message_type = "info";

// 执行命令的通用函数
function execCommand($command)
{
    $output = [];
    $return_var = 0;
    exec($command . " 2>&1", $output, $return_var);
    return [implode("\n", $output), $return_var];
}

// 后台执行命令，避免 Web 请求阻塞
function execBackgroundCommand($command)
{
    $bg_command = "nohup sh -c " . escapeshellarg($command) . " >/dev/null 2>&1 &";
    exec($bg_command);
}

// 获取服务状态
function getServiceStatus()
{
    list($output, $return_var) = execCommand("service mihomo onestatus");
    return $return_var === 0 ? "running" : "stopped";
}

// 校验配置文件
function validateConfigContent($content, $current_file)
{
    $temp_file = $current_file . ".webtmp";
    $config_dir = dirname($current_file);

    if (file_put_contents($temp_file, $content, LOCK_EX) === false) {
        return [false, "临时配置写入失败，无法校验。"];
    }

    list($output, $return_var) = execCommand(
        "/usr/local/bin/mihomo -d " . escapeshellarg($config_dir) .
            " -t -f " . escapeshellarg($temp_file)
    );
    @unlink($temp_file);

    if ($return_var === 0) {
        return [true, "配置校验通过。"];
    }

    return [false, "配置校验失败：\n" . $output];
}

// 保存配置文件
function saveConfig($file, $content)
{
    if (empty(trim($content))) {
        return ["配置内容不能为空！", "danger"];
    }

    $dir = dirname($file);
    if (!is_dir($dir) || !is_writable($dir)) {
        return ["配置保存失败，目标目录不可写。", "danger"];
    }

    list($is_valid, $validate_message) = validateConfigContent($content, $file);
    if (!$is_valid) {
        return [$validate_message, "danger"];
    }

    $backup_file = $file . ".bak." . date("Ymd_His");
    $backup_created = false;
    if (file_exists($file)) {
        if (!@copy($file, $backup_file)) {
            return ["配置备份失败，已取消保存。", "danger"];
        }
        $backup_created = true;
    }

    $temp_file = $file . ".tmp";
    if (file_put_contents($temp_file, $content, LOCK_EX) === false) {
        @unlink($temp_file);
        if ($backup_created) {
            @unlink($backup_file);
        }
        return ["配置保存失败，临时文件写入失败。", "danger"];
    }

    if (!@rename($temp_file, $file)) {
        @unlink($temp_file);
        if ($backup_created) {
            @unlink($backup_file);
        }
        return ["配置保存失败，无法替换正式配置文件。", "danger"];
    }

    return ["配置保存成功！", "success"];
}

// 清空日志
function clearLogFile($file)
{
    if (!file_exists($file)) {
        return ["日志文件不存在，无需清空。", "warning"];
    }

    if (!is_writable($file)) {
        return ["日志清空失败，请确保日志文件可写。", "danger"];
    }

    return file_put_contents($file, "", LOCK_EX) !== false
        ? ["日志已清空！", "success"]
        : ["日志清空失败！", "danger"];
}

// 处理服务操作
function handleServiceAction($action)
{
    $allowedActions = ['start', 'stop', 'restart'];
    if (!in_array($action, $allowedActions, true)) {
        return ["无效的操作！", "danger"];
    }

    $messages = [
        'start' => ["mihomo 启动命令已提交，请稍候刷新状态。", "mihomo 服务启动失败！"],
        'stop' => ["mihomo 服务已停止！", "mihomo 服务停止失败！"],
        'restart' => ["mihomo 重启命令已提交，请稍候刷新状态。", "mihomo 服务重启失败！"]
    ];

    // 启动改为后台执行，避免页面等待过久
    if ($action === 'start') {
        execBackgroundCommand("service mihomo start");
        return [$messages['start'][0], "success"];
    }

    // 重启继续后台执行，避免 504 超时
    if ($action === 'restart') {
        execBackgroundCommand("service mihomo restart");
        return [$messages['restart'][0], "success"];
    }

    // 停止保持同步执行
    list($output, $return_var) = execCommand("service mihomo stop");

    // 特殊处理：已经停止的情况
    if ($action === 'stop' && stripos($output, 'not running') !== false) {
        return ["mihomo 服务已停止！", "success"];
    }

    // 正常成功
    if ($return_var === 0) {
        return [$messages[$action][0], "success"];
    }

    // 其他失败
    $detail = trim($output) !== "" ? "\n" . $output : "";
    return [$messages[$action][1] . $detail, "danger"];
}

// 处理表单提交
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = isset($_POST['action']) ? trim((string)$_POST['action']) : '';

    switch ($action) {
        case 'save_config':
            $config_content_raw = isset($_POST['config_content']) ? (string)$_POST['config_content'] : '';
            list($message, $message_type) = saveConfig($config_file, $config_content_raw);
            break;
        case 'clear_log':
            list($message, $message_type) = clearLogFile($log_file);
            break;
        case 'start':
        case 'stop':
        case 'restart':
            list($message, $message_type) = handleServiceAction($action);
            break;
        default:
            $message = "无效的操作！";
            $message_type = "danger";
            break;
    }
}

// 读取配置文件内容
$config_content = file_exists($config_file)
    ? htmlspecialchars(file_get_contents($config_file), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8')
    : "配置文件未找到！";

$service_status = getServiceStatus();

$show_message = !empty($message) && !in_array($message, [
    'mihomo 启动命令已提交，请稍候刷新状态。',
    'mihomo 服务已停止！',
    'mihomo 重启命令已提交，请稍候刷新状态。'
], true);
?>

<style>
    .mihomo-action-bar {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        align-items: center;
    }

    .mihomo-action-bar .btn {
        min-width: 92px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 6px;
        font-weight: 600;
    }

    .mihomo-log-bar {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        align-items: center;
    }

    .mihomo-section-title {
        display: flex;
        align-items: center;
        gap: 8px;
        font-weight: 700;
        color: #333;
        line-height: 1.2;
        padding: 2px 0;
    }

    .mihomo-section-title i {
        color: #777;
        width: 14px;
        text-align: center;
    }

    .mihomo-status-box {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 12px 14px;
        border-radius: 3px;
        border: 1px solid #d8dee3;
        background: #f7f7f7;
        color: #333;
        margin-bottom: 0;
        line-height: 1.4;
    }

    .mihomo-status-box.is-running {
        background: #f3fbf4;
        border-color: #b7dec0;
    }

    .mihomo-status-box.is-stopped {
        background: #fff5f5;
        border-color: #e5bcbc;
    }

    .mihomo-status-light {
        width: 12px;
        height: 12px;
        min-width: 12px;
        border-radius: 50%;
        display: inline-block;
        box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.12);
    }

    .mihomo-status-light.is-running {
        background: #51a351;
    }

    .mihomo-status-light.is-stopped {
        background: #d9534f;
    }

    .mihomo-status-text {
        font-weight: 600;
    }

    .mihomo-status-subtext {
        color: #666;
        font-size: 12px;
        margin-left: 4px;
    }

    .mihomo-panel-cell {
        padding-top: 10px !important;
        padding-bottom: 10px !important;
    }
</style>

<?php if ($show_message): ?>
    <div>
        <div class="alert alert-<?= htmlspecialchars($message_type, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); ?>">
            <pre style="margin:0;border:0;background:transparent;padding:0;white-space:pre-wrap;word-break:break-word;"><?= htmlspecialchars($message, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); ?></pre>
        </div>
    </div>
<?php endif; ?>

<section class="page-content-main">
    <div class="container-fluid">
        <div class="row">
            <section class="col-xs-12">
                <div class="content-box tab-content table-responsive __mb">
                    <table class="table table-striped">
                        <tbody>
                            <tr>
                                <td class="mihomo-panel-cell">
                                    <div class="mihomo-section-title">
                                        <i class="fa fa-heartbeat"></i>
                                        <span>服务状态</span>
                                    </div>
                                </td>
                            </tr>
                            <tr>
                                <td>
                                    <div
                                        id="mihomo-status"
                                        class="mihomo-status-box <?= $service_status === 'running' ? 'is-running' : 'is-stopped'; ?>">
                                        <span
                                            class="mihomo-status-light <?= $service_status === 'running' ? 'is-running' : 'is-stopped'; ?>"></span>
                                        <span class="mihomo-status-text">
                                            <?= $service_status === 'running' ? 'mihomo 正在运行' : 'mihomo 已停止'; ?>
                                        </span>
                                        <span class="mihomo-status-subtext">
                                            <?= $service_status === 'running' ? '服务状态正常' : '服务当前未运行'; ?>
                                        </span>
                                    </div>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </section>

            <section class="col-xs-12">
                <div class="content-box tab-content table-responsive __mb">
                    <table class="table table-striped">
                        <tbody>
                            <tr>
                                <td class="mihomo-panel-cell">
                                    <div class="mihomo-section-title">
                                        <i class="fa fa-sliders"></i>
                                        <span>服务控制</span>
                                    </div>
                                </td>
                            </tr>
                            <tr>
                                <td>
                                    <form method="post" class="mihomo-action-bar">
                                        <button type="submit" name="action" value="start" class="btn btn-success">
                                            <i class="fa fa-play"></i>
                                            <span>启动</span>
                                        </button>
                                        <button type="submit" name="action" value="stop" class="btn btn-danger">
                                            <i class="fa fa-stop"></i>
                                            <span>停止</span>
                                        </button>
                                        <button type="submit" name="action" value="restart" class="btn btn-warning">
                                            <i class="fa fa-refresh"></i>
                                            <span>重启</span>
                                        </button>
                                    </form>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </section>

            <section class="col-xs-12">
                <div class="content-box tab-content table-responsive __mb">
                    <table class="table table-striped">
                        <tbody>
                            <tr>
                                <td class="mihomo-panel-cell">
                                    <div class="mihomo-section-title">
                                        <i class="fa fa-file-text-o"></i>
                                        <span>配置管理</span>
                                    </div>
                                </td>
                            </tr>
                            <tr>
                                <td>
                                    <form method="post">
                                        <textarea style="max-width:none;font-family:monospace;" name="config_content" rows="11" class="form-control"><?= $config_content; ?></textarea>
                                        <br>
                                        <button type="submit" name="action" value="save_config" class="btn btn-danger">
                                            <i class="fa fa-save"></i> 保存配置
                                        </button>
                                    </form>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </section>

            <section class="col-xs-12">
                <div class="content-box tab-content table-responsive __mb">
                    <table class="table table-striped">
                        <tbody>
                            <tr>
                                <td class="mihomo-panel-cell">
                                    <div class="mihomo-section-title">
                                        <i class="fa fa-file-text"></i>
                                        <span>日志视图</span>
                                    </div>
                                </td>
                            </tr>
                            <tr>
                                <td>
                                    <form method="post" class="mihomo-log-bar" style="margin-bottom:10px;">
                                        <button type="submit" name="action" value="clear_log" class="btn btn-default">
                                            <i class="fa fa-trash"></i> 清空日志
                                        </button>
                                    </form>
                                    <textarea style="max-width:none;font-family:monospace;" id="log-viewer" rows="11" class="form-control" readonly></textarea>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </section>
        </div>
    </div>
</section>

<script>
    function renderStatus(status) {
        const statusElement = document.getElementById('mihomo-status');
        if (!statusElement) {
            return;
        }

        if (status === 'running') {
            statusElement.className = 'mihomo-status-box is-running';
            statusElement.innerHTML =
                '<span class="mihomo-status-light is-running"></span>' +
                '<span class="mihomo-status-text">mihomo 正在运行</span>' +
                '<span class="mihomo-status-subtext">服务状态正常</span>';
        } else {
            statusElement.className = 'mihomo-status-box is-stopped';
            statusElement.innerHTML =
                '<span class="mihomo-status-light is-stopped"></span>' +
                '<span class="mihomo-status-text">mihomo 已停止</span>' +
                '<span class="mihomo-status-subtext">服务当前未运行</span>';
        }
    }

    function checkmihomoStatus() {
        fetch('/status_mihomo.php', {
                cache: 'no-store'
            })
            .then(response => response.json())
            .then(data => {
                renderStatus(data.status === 'running' ? 'running' : 'stopped');
            })
            .catch(() => {
                renderStatus('stopped');
            });
    }

    function refreshLogs() {
        fetch('/status_mihomo_logs.php', {
                cache: 'no-store'
            })
            .then(response => response.text())
            .then(logContent => {
                const logViewer = document.getElementById('log-viewer');
                logViewer.value = logContent;
                logViewer.scrollTop = logViewer.scrollHeight;
            })
            .catch(() => {
                const logViewer = document.getElementById('log-viewer');
                logViewer.value = '[错误] 无法加载日志，请检查网络或服务器状态。';
            });
    }

    document.addEventListener('DOMContentLoaded', () => {
        checkmihomoStatus();
        refreshLogs();

        // 状态更快刷新，提升启动/重启后的反馈速度
        setInterval(checkmihomoStatus, 2000);

        // 日志维持较温和刷新频率
        setInterval(refreshLogs, 5000);
    });
</script>

<?php include("foot.inc"); ?>