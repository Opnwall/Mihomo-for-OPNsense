<?php
$log_file = "/var/log/mosdns.log"; // 日志文件路径
$max_lines = 5000;
$display_lines = 200; // 前端仅显示最近 200 行

if (!file_exists($log_file)) {
    echo "[错误] 日志文件未找到！";
    exit;
}

$log = new SplFileObject($log_file, 'r');
$log->seek(PHP_INT_MAX);
$total_lines = $log->key();

$log_content = [];
$log->rewind();

// 只保留最后 $max_lines 行
$start_line = max(0, $total_lines - $max_lines);
$log->seek($start_line);

while (!$log->eof()) {
    $log_content[] = trim($log->fgets());
}

// 仅在日志超出 $max_lines 时重写文件
if ($total_lines > $max_lines) {
    file_put_contents($log_file, implode("\n", $log_content) . "\n");
}

// 取最近 $display_lines 行显示
$display_content = array_slice($log_content, -$display_lines);
echo implode("\n", $display_content);
?>
