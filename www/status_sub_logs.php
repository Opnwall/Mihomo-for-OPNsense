<?php
require_once("guiconfig.inc");

define('LOG_FILE', '/var/log/sub.log');

header('Content-Type: text/plain; charset=UTF-8');

if (!is_file(LOG_FILE)) {
    echo "日志文件不存在。";
    exit;
}

$log_lines = @file(LOG_FILE);
if ($log_lines === false) {
    echo "无法读取日志文件。";
    exit;
}

$log_tail = array_slice($log_lines, -200);
echo implode("", $log_tail);