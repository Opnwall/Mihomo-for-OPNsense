<?php
// status_mihomo.php
header('Content-Type: application/json');

// 检查mihomo进程是否存在
exec("pgrep -x mihomo", $output, $return_var);

if ($return_var === 0) {
    echo json_encode(['status' => 'running']);
} else {
    echo json_encode(['status' => 'stopped']);
}
?>