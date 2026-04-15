#!/bin/sh

set -eu

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

log() {
    color="$1"
    message="$2"
    echo -e "${color}${message}${RESET}"
}

log_info() {
    log "$YELLOW" "$1"
}

log_ok() {
    log "$GREEN" "$1"
}

log_error() {
    log "$RED" "$1"
}

exit_with_error() {
    log_error "$1"
    exit 1
}

echo ""
echo -e "${GREEN}================== 规则数据更新脚本 ==================${RESET}"
echo ""

PROXY="socks5h://127.0.0.1:7891"
WORKDIR="/tmp/opnsense_update"
IPS="/usr/local/etc/mosdns/ips"
DOMAINS="/usr/local/etc/mosdns/domains"

cleanup() {
    rm -rf "$WORKDIR"
}

trap cleanup EXIT INT TERM

mkdir -p "$WORKDIR" "$IPS" "$DOMAINS"
cd "$WORKDIR" || exit_with_error "无法进入工作目录 $WORKDIR"

download() {
    url="$1"
    output="$2"
    retries=3
    count=1

    while [ "$count" -le "$retries" ]; do
        if curl -fL --connect-timeout 10 --max-time 60 \
            -A "Mozilla/5.0 (compatible; UpdateScript/1.0)" \
            -o "$output" "$url" >/dev/null 2>&1; then
            break
        fi

        log_info "直连下载失败，尝试代理下载（$count/$retries）：$url"
        if curl -fL --socks5-hostname 127.0.0.1:7891 \
            --connect-timeout 10 --max-time 60 \
            -A "Mozilla/5.0 (compatible; UpdateScript/1.0)" \
            -o "$output" "$url" >/dev/null 2>&1; then
            break
        fi

        if [ "$count" -eq "$retries" ]; then
            break
        fi

        log_info "下载失败，重试 $count/$retries：$url"
        count=$((count + 1))
        sleep 2
    done

    if [ ! -s "$output" ]; then
        exit_with_error "下载失败或文件为空：$url"
    fi
}

log_info "正在更新规则数据..."
download "https://ispip.clang.cn/all_cn.txt" "$WORKDIR/all_cn.txt"
download "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/direct-list.txt" "$WORKDIR/direct-list.txt"
download "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/proxy-list.txt" "$WORKDIR/proxy-list.txt"
download "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/gfw.txt" "$WORKDIR/gfw.txt"

copy_file() {
    src="$1"
    dst_dir="$2"
    [ -f "$src" ] || exit_with_error "源文件不存在：$src"
    [ -d "$dst_dir" ] || exit_with_error "目标目录不存在：$dst_dir"
    cp -f "$src" "$dst_dir/" || exit_with_error "复制失败：$src -> $dst_dir"
}

copy_file "$WORKDIR/all_cn.txt" "$IPS"
copy_file "$WORKDIR/direct-list.txt" "$DOMAINS"
copy_file "$WORKDIR/proxy-list.txt" "$DOMAINS"
copy_file "$WORKDIR/gfw.txt" "$DOMAINS"

log_ok "规则数据已更新"
echo ""
log_ok "规则数据更新完成"
echo ""
