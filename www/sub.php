<?php
require_once("guiconfig.inc");
include("head.inc");
include("fbegin.inc");

define('ENV_FILE', '/usr/local/etc/mihomo/sub/env');
define('LOG_FILE', '/var/log/sub.log');
define('SUB_SCRIPT', '/usr/local/etc/mihomo/sub/sub.sh');

$message = '';
$message_type = 'info';

// 执行命令
function execCommand($command) {
    $output = [];
    $return_var = 0;
    exec($command . " 2>&1", $output, $return_var);
    return [implode("\n", $output), $return_var];
}

// 后台执行命令
function execBackgroundCommand($command) {
    $bg_command = "nohup sh -c " . escapeshellarg($command) . " >/dev/null 2>&1 &";
    exec($bg_command);
}

// 写日志
function log_message($message, $log_file = LOG_FILE) {
    $time = date("Y-m-d H:i:s");
    $log_entry = "[{$time}] {$message}\n";
    @file_put_contents($log_file, $log_entry, FILE_APPEND | LOCK_EX);
}

// 清空日志
function clear_log($log_file = LOG_FILE) {
    if (!file_exists($log_file)) {
        return ["日志文件不存在，无需清空。", "warning"];
    }

    if (!is_writable($log_file)) {
        return ["日志清空失败，请确保日志文件可写。", "danger"];
    }

    return file_put_contents($log_file, '', LOCK_EX) !== false
        ? ["日志已清空！", "success"]
        : ["日志清空失败！", "danger"];
}

// 安全转义 env 值
function escape_env_value($value) {
    return str_replace("'", "'\"'\"'", $value);
}

// 保存环境变量
function save_env_variable($key, $value, $env_file = ENV_FILE) {
    if ($key === '') {
        return [false, "变量名不能为空"];
    }

    $dir = dirname($env_file);
    if (!is_dir($dir)) {
        return [false, "目录不存在: " . $dir];
    }

    if (!is_writable($dir)) {
        return [false, "目录不可写: " . $dir];
    }

    $lines = file_exists($env_file)
        ? file($env_file, FILE_IGNORE_NEW_LINES)
        : [];

    $new_lines = [];

    foreach ($lines as $line) {
        if (!preg_match('/^(export\s+)?' . preg_quote($key, '/') . '=/', $line)) {
            $new_lines[] = $line;
        }
    }

    $escaped_value = escape_env_value($value);
    $new_lines[] = "{$key}='{$escaped_value}'";

    $tmp_file = $env_file . '.tmp';
    $content = implode("\n", array_filter($new_lines, static function ($line) {
        return $line !== null;
    })) . "\n";

    if (@file_put_contents($tmp_file, $content, LOCK_EX) === false) {
        @unlink($tmp_file);
        return [false, "临时文件写入失败: " . $tmp_file];
    }

    if (!@rename($tmp_file, $env_file)) {
        @unlink($tmp_file);
        return [false, "无法替换目标文件: " . $env_file];
    }

    return [true, "保存成功"];
}

// 读取环境变量
function load_env_variables($env_file = ENV_FILE) {
    $env_vars = [];

    if (!file_exists($env_file)) {
        return $env_vars;
    }

    $env_lines = file($env_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($env_lines as $line) {
        if (preg_match("/^(?:export\s+)?([A-Za-z0-9_]+)='(.*)'$/", $line, $matches)) {
            $env_vars[$matches[1]] = str_replace("'\"'\"'", "'", $matches[2]);
        }
    }

    return $env_vars;
}

// 删除订阅临时文件
function cleanup_temp_files() {
    $files = [
        "/usr/local/etc/mihomo/sub/temp/mihomo_config.yaml",
        "/usr/local/etc/mihomo/sub/temp/proxies.txt",
        "/usr/local/etc/mihomo/sub/temp/config.yaml",
    ];

    foreach ($files as $file) {
        @unlink($file);
    }
}

// 处理表单提交
function handle_form_submission() {
    global $message, $message_type;

    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        return;
    }

    $action = isset($_POST['action']) ? trim((string)$_POST['action']) : '';
    $is_save = isset($_POST['save']);

    if ($is_save) {
        $url = isset($_POST['subscribe_url']) ? trim((string)$_POST['subscribe_url']) : '';
        $secret = isset($_POST['mihomo_secret']) ? trim((string)$_POST['mihomo_secret']) : '';

        if ($url === '') {
            $message = "订阅地址不能为空！";
            $message_type = "danger";
            return;
        }

        list($url_saved, $url_msg) = save_env_variable('mihomo_URL', $url);
        list($secret_saved, $secret_msg) = save_env_variable('mihomo_secret', $secret);

        if (!$url_saved) {
            $message = "保存订阅地址失败：" . $url_msg;
            $message_type = "danger";
            return;
        }

        if (!$secret_saved) {
            $message = "保存访问密钥失败：" . $secret_msg;
            $message_type = "danger";
            return;
        }

        log_message("订阅地址已保存。");
        log_message("访问密钥已保存。");

        $message = "设置已成功保存。";
        $message_type = "success";
        return;
    }

    if ($action === 'subscribe_now') {
        cleanup_temp_files();

        @file_put_contents(LOG_FILE, '', LOCK_EX);
        log_message("订阅任务已提交，开始后台执行。");

        $command =
            "bash " . escapeshellarg(SUB_SCRIPT) .
            " >> " . escapeshellarg(LOG_FILE) . " 2>&1; " .
            "echo \"[$(date '+%Y-%m-%d %H:%M:%S')] 订阅任务执行完毕。\" >> " . escapeshellarg(LOG_FILE);

        execBackgroundCommand($command);

        $message = "订阅任务已提交，请稍候查看日志。";
        $message_type = "success";
        return;
    }

    if ($action === 'clear_log') {
        list($message, $message_type) = clear_log();
        return;
    }

    $message = "无效的操作！";
    $message_type = "danger";
}

handle_form_submission();

$env_vars = load_env_variables();
$current_url = $env_vars['mihomo_URL'] ?? '';
$current_secret = $env_vars['mihomo_secret'] ?? '';

$log_lines = file_exists(LOG_FILE) ? file(LOG_FILE) : [];
$log_tail = array_slice($log_lines, -200);
$log_content = htmlspecialchars(implode("", $log_tail), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
?>

<style>
.sub-action-bar {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    align-items: center;
}

.sub-action-bar .btn {
    min-width: 108px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    font-weight: 600;
}

.sub-log-bar {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    align-items: center;
}

.sub-section-title {
    display: flex;
    align-items: center;
    gap: 8px;
    font-weight: 700;
    color: #333;
    line-height: 1.2;
    padding: 2px 0;
}

.sub-section-title i {
    color: #777;
    width: 14px;
    text-align: center;
}

.sub-panel-cell {
    padding-top: 10px !important;
    padding-bottom: 10px !important;
}
</style>

<?php if (!empty($message)): ?>
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
                                <td class="sub-panel-cell">
                                    <div class="sub-section-title">
                                        <i class="fa fa-link"></i>
                                        <span>订阅管理</span>
                                    </div>
                                </td>
                            </tr>
                            <tr>
                                <td>
                                    <form method="post" class="form-group">
                                        <label for="subscribe_url">订阅地址：</label>
                                        <input
                                            type="text"
                                            id="subscribe_url"
                                            name="subscribe_url"
                                            value="<?= htmlspecialchars($current_url, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); ?>"
                                            class="form-control"
                                            placeholder="输入订阅地址"
                                            autocomplete="off"
                                        />

                                        <label for="mihomo_secret" style="margin-top:10px;">访问密钥：</label>
                                        <input
                                            type="text"
                                            id="mihomo_secret"
                                            name="mihomo_secret"
                                            value="<?= htmlspecialchars($current_secret, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); ?>"
                                            class="form-control"
                                            placeholder="输入安全密钥"
                                            autocomplete="off"
                                        />

                                        <br>
                                        <div class="sub-action-bar">
                                            <button type="submit" name="save" value="1" class="btn btn-danger">
                                                <i class="fa fa-save"></i>
                                                <span>保存设置</span>
                                            </button>
                                            <button type="submit" name="action" value="subscribe_now" class="btn btn-success">
                                                <i class="fa fa-sync"></i>
                                                <span>开始订阅</span>
                                            </button>
                                        </div>
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
                                <td class="sub-panel-cell">
                                    <div class="sub-section-title">
                                        <i class="fa fa-file-text"></i>
                                        <span>日志查看</span>
                                    </div>
                                </td>
                            </tr>
                            <tr>
                                <td>
                                    <form method="post" class="sub-log-bar" style="margin-bottom:10px;">
                                        <button type="submit" name="action" value="clear_log" class="btn btn-default">
                                            <i class="fa fa-trash"></i> 清空日志
                                        </button>
                                    </form>
                                    <textarea
                                        readonly
                                        style="max-width:none;font-family:monospace;"
                                        id="log-viewer"
                                        rows="20"
                                        class="form-control"
                                    ><?= $log_content; ?></textarea>
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
function refreshLogs() {
    fetch('/status_sub_logs.php', { cache: 'no-store' })
        .then(response => {
            if (!response.ok) {
                throw new Error('HTTP ' + response.status);
            }
            return response.text();
        })
        .then(logContent => {
            const logViewer = document.getElementById('log-viewer');
            if (!logViewer) {
                return;
            }

            const trimmed = logContent.trim();
            if (
                trimmed.startsWith('<!doctype html') ||
                trimmed.startsWith('<html') ||
                trimmed.includes('<title>OPNsense') ||
                trimmed.includes('页面未找到')
            ) {
                logViewer.value = '[错误] 日志接口返回了 HTML 页面，请检查 status_sub_logs.php 是否存在且路径正确。';
                return;
            }

            logViewer.value = logContent;
            logViewer.scrollTop = logViewer.scrollHeight;
        })
        .catch((error) => {
            const logViewer = document.getElementById('log-viewer');
            if (!logViewer) {
                return;
            }
            logViewer.value = '[错误] 无法加载日志：' + error.message;
        });
}

document.addEventListener('DOMContentLoaded', () => {
    refreshLogs();
    setInterval(refreshLogs, 3000);
});
</script>

<?php include("foot.inc"); ?>