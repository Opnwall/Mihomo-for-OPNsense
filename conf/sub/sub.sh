#!/bin/sh
# 在线订阅转换脚本

#################### 初始化 ####################
Server_Dir=$(cd "$(dirname "$0")" && pwd)
[ -f "$Server_Dir/env" ] && . "$Server_Dir/env"

API_BASE="https://subconverters.com/sub"

Conf_Dir="$Server_Dir/conf"
Temp_Dir="$Server_Dir/temp"
Clash_Dir="/usr/local/etc/mihomo"
Dashboard_Dir="${Server_Dir}/ui"
mkdir -p "$Conf_Dir" "$Temp_Dir"

command -v jq >/dev/null 2>&1 || {
  echo "缺少 jq 命令，请先安装（用于 URL 编码）"
  exit 1
}

cleanup_tmp_files() {
    [ -n "$TMP_RAW" ] && rm -f "$TMP_RAW"
    [ -n "$TMP_PROXIES" ] && rm -f "$TMP_PROXIES"
    [ -n "$TMP_FINAL" ] && rm -f "$TMP_FINAL"
    rm -f "$Conf_Dir/config.clean.yaml" "$Conf_Dir/config.new.yaml"
}

trap cleanup_tmp_files EXIT INT TERM

# mihomo订阅地址校验
[ -z "$mihomo_URL" ] && {
    echo "错误：未设置 mihomo_URL 环境变量"
    exit 1
}

# 安全密钥
Secret=${mihomo_secret:-$(openssl rand -hex 32)}

#################### 预清理临时文件 ####################
find "$Temp_Dir" -type f -exec rm -f {} \; 2>/dev/null

TMP_RAW=$(mktemp "$Temp_Dir/clash_config.XXXXXX") || {
    echo "创建临时文件失败：TMP_RAW"
    exit 1
}
TMP_PROXIES=$(mktemp "$Temp_Dir/proxies.XXXXXX") || {
    echo "创建临时文件失败：TMP_PROXIES"
    exit 1
}
TMP_FINAL=$(mktemp "$Temp_Dir/config.XXXXXX") || {
    echo "创建临时文件失败：TMP_FINAL"
    exit 1
}

#################### 下载配置 ####################
ENCODED_URL=$(printf "%s" "$mihomo_URL" | jq -s -R -r @uri)
API_URL="${API_BASE}?target=clash&url=${ENCODED_URL}&udp=true&clash.dns=true&list=false"
echo ""
echo "尝试不使用代理从：$API_URL 下载配置..."
if curl -fL -k -sS --retry 3 -m 15 -o "$TMP_RAW" "$API_URL"; then
    echo "下载成功：$TMP_RAW"
else
    echo "下载失败，尝试通过 SOCKS5 代理 127.0.0.1:7891 下载配置..."
    if curl -fL -k -sS --retry 2 -m 15 --socks5-hostname 127.0.0.1:7891 -o "$TMP_RAW" "$API_URL"; then
        echo "下载成功：$TMP_RAW"
    else
        echo "下载失败：$API_URL"
        echo "请检查网络连接或 mihomo 是否运行并监听 127.0.0.1:7891"
        exit 2
    fi
fi

if [ ! -s "$TMP_RAW" ]; then
    echo "下载结果为空，订阅内容无效。"
    exit 1
fi

RAW_SIZE=$(wc -c < "$TMP_RAW" | tr -d ' ')
echo "下载文件大小: ${RAW_SIZE} 字节"

if head -n 20 "$TMP_RAW" | grep -Eiq '^(<!doctype html|<html|<head|<body)'; then
    echo "检测到返回内容为 HTML 页面，订阅可能失效或被拦截。"
    echo "前 20 行内容如下："
    head -n 20 "$TMP_RAW"
    exit 1
fi

if ! grep -q '^proxies:' "$TMP_RAW"; then
    echo "下载结果缺少 proxies: 节点，订阅内容可能无效。"
    echo "前 20 行内容如下："
    head -n 20 "$TMP_RAW"
    exit 1
fi
echo ""

#################### 合成配置 ####################
TEMPLATE_FILE="$Server_Dir/template_config.yaml"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "缺少模板文件，自动生成：$TEMPLATE_FILE"
    cat > "$TEMPLATE_FILE" <<'EOF'
port: 7890
socks-port: 7891
mode: rule
log-level: info #在调试结果后，改为error或warn，减少日志输出。
allow-lan: true
external-controller: '0.0.0.0:9090'
external-ui: /usr/local/etc/mihomo/ui
tun:
  enable: true
  stack: gvisor #使用gvisor栈，提供更好的兼容性和性能，system栈可能在某些环境下存在兼容性问题。
  device: tun_3000
  mtu: 9000
  auto-route: true
  strict-route: true
  auto-detect-interface: true
  dns-hijack:
    - any:53
    - tcp://any:53
dns:
  enable: true
  listen: 0.0.0.0:53
  default-nameserver: 
    - 127.0.0.1:5335 # 指向mosdns
EOF
fi

# 提取代理部分
sed -n '/^proxies:/,$p' "$TMP_RAW" > "$TMP_PROXIES"

if [ ! -s "$TMP_PROXIES" ]; then
    echo "提取代理节点失败，proxies 段为空。"
    exit 1
fi

NODE_COUNT=$(awk '
  BEGIN { count = 0 }
  /^proxies:/ { in_proxies = 1; next }
  in_proxies && /^[^[:space:]]/ { in_proxies = 0 }
  in_proxies && /^[[:space:]]*-[[:space:]]/ { count++ }
  END { print count }
' "$TMP_PROXIES" | tr -d ' ')
echo "提取节点数量: ${NODE_COUNT}"

# 合成配置
echo "合成配置..."
sleep 1
cat "$TEMPLATE_FILE" > "$TMP_FINAL"
cat "$TMP_PROXIES" >> "$TMP_FINAL"

if [ ! -s "$TMP_FINAL" ]; then
    echo "合成后的配置文件为空。"
    exit 1
fi

FINAL_SIZE=$(wc -c < "$TMP_FINAL" | tr -d ' ')
echo "合成配置大小: ${FINAL_SIZE} 字节"

cp "$TMP_FINAL" "$Conf_Dir/config.yaml" || {
    echo "写入临时配置失败：$Conf_Dir/config.yaml"
    exit 1
}

# 先清理旧的 secret，再在 external-ui 行之后插入 secret
awk '!/^secret: / { print }' "$Conf_Dir/config.yaml" > "$Conf_Dir/config.clean.yaml" && mv "$Conf_Dir/config.clean.yaml" "$Conf_Dir/config.yaml"

if grep -q '^external-ui:' "$Conf_Dir/config.yaml"; then
    awk -v secret="secret: ${Secret}" '
      /^external-ui:/ {
          print;
          print secret;
          next
      }
      { print }
    ' "$Conf_Dir/config.yaml" > "$Conf_Dir/config.new.yaml" && mv "$Conf_Dir/config.new.yaml" "$Conf_Dir/config.yaml"
else
    echo "secret: ${Secret}" >> "$Conf_Dir/config.yaml"
fi
echo "合成完成!"
echo ""

#################### 应用配置并重启 ####################
if [ ! -s "$Conf_Dir/config.yaml" ]; then
    echo "目标配置文件为空，停止应用。"
    exit 1
fi

echo "校验配置..."
sleep 1
if /usr/local/bin/mihomo -d "$Clash_Dir" -t -f "$Conf_Dir/config.yaml" >/dev/null 2>&1; then
    echo "配置校验通过"
else
    echo "配置校验失败，未覆盖正式配置。"
    exit 1
fi

echo "替换配置..."
sleep 1
cp "$Conf_Dir/config.yaml" "$Clash_Dir/config.yaml" || {
    echo "替换正式配置失败：$Clash_Dir/config.yaml"
    exit 1
}
echo "重启服务..."
if service mihomo restart >/dev/null 2>&1; then
    echo "重启完成！"
else
    echo "重启失败，请手动检查 mihomo 服务状态。"
fi
echo ""
#################### 输出仪表盘信息 ####################
sleep 1
LAN_IP=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' | xargs -I{} ifconfig {} 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}')
[ -n "$LAN_IP" ] || LAN_IP=$(ifconfig | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}')
echo "仪表盘访问地址: http://${LAN_IP}:9090/ui"
echo "仪表盘访问密钥: ${Secret}"
echo ""

#################### 清理临时文件 ####################
cleanup_tmp_files