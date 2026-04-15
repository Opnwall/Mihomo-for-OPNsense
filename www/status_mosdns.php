<?php
// status_mosdns.php
header('Content-Type: application/json');

// 检查mosdns进程是否存在
exec("pgrep -x mosdns", $output, $return_var);

if ($return_var === 0) {
    echo json_encode(['status' => 'running']);
} else {
    echo json_encode(['status' => 'stopped']);
}
?>