#!/bin/bash
echo -e ''
echo -e "\033[32m========Mihomo for OPNsense 一键安装脚本=========\033[0m"
echo -e ''

# 定义颜色变量
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
BLUE="\033[34m"
RESET="\033[0m"

# 定义目录变量
ROOT="/usr/local"
BIN_DIR="$ROOT/bin"
WWW_DIR="$ROOT/www"
CONF_DIR="$ROOT/etc"
MENU_DIR="$ROOT/opnsense/mvc/app/models/OPNsense"
RC_DIR="$ROOT/etc/rc.d"
PLUGINS="$ROOT/etc/inc/plugins.inc.d"
ACTIONS="$ROOT/opnsense/service/conf/actions.d"
RC_CONF="/etc/rc.conf.d/"
CONFIG_FILE="/conf/config.xml"
TMP_FILE="/tmp/config.xml.tmp"
TIMESTAMP=$(date +%F-%H%M%S)
BACKUP_FILE="/conf/config.xml.bak.$TIMESTAMP"
TARGET_IF_BLOCK=""

# 定义日志函数
log() {
    local color="$1"
    local level="$2"
    local message="$3"
    local ts
    ts=$(date '+%F %T')
    echo -e "${color}[${ts}] [${level}] ${message}${RESET}"
}

log_info() {
    log "$YELLOW" "INFO" "$1"
}

log_warn() {
    log "$CYAN" "WARN" "$1"
}

log_error() {
    log "$RED" "ERROR" "$1"
}

log_success() {
    log "$GREEN" "OK" "$1"
}

log_step() {
    log "$BLUE" "STEP" "$1"
}

# 创建目录
log_step "创建目录..."
mkdir -p "$CONF_DIR/mihomo" "$CONF_DIR/mosdns" || log_error "目录创建失败！"

# 复制文件
log_step "复制文件并部署组件..."
log_info "生成菜单..."
log_info "生成服务..."
log_info "添加权限..."
chmod +x ./bin/* ./rc.d/*
cp -f bin/* "$BIN_DIR/" || log_error "bin 文件复制失败！"
cp -f www/* "$WWW_DIR/" || log_error "www 文件复制失败！"
cp -f rc.d/* "$RC_DIR/" || log_error "rc.d 文件复制失败！"
cp -f rc.conf/* "$RC_CONF/" || log_error "rc.conf 文件复制失败！"
cp -f plugins/* "$PLUGINS/" || log_error "plugins 文件复制失败！"
cp -f actions/* "$ACTIONS/" || log_error "actions 文件复制失败！"
cp -R -f menu/* "$MENU_DIR/" || log_error "menu 文件复制失败！"
cp -R -f conf/* "$CONF_DIR/mihomo/" || log_error "conf 文件复制失败！"
cp -R -f mosdns/* "$CONF_DIR/mosdns/" || log_error "mosdns 文件复制失败！"
log_success "文件复制完成"

# 新建订阅程序
log_step "添加订阅..."
cat>/usr/bin/sub<<EOF
# 启动mihomo订阅程序
bash /usr/local/etc/mihomo/sub/sub.sh
EOF
chmod +x /usr/bin/sub
log_success "订阅程序添加完成"

# 安装bash
log_step "检查并安装 bash..."
if ! pkg info -q bash > /dev/null 2>&1; then
  if pkg install -y bash > /dev/null 2>&1; then
    log_success "bash 安装完成"
  else
    log_error "bash 安装失败"
  fi
else
  log_warn "bash 已安装，跳过"
fi

# 启动Tun接口
log_step "启动 mihomo 与 mosdns..."
if service mihomo restart > /dev/null 2>&1; then
  log_success "mihomo 重启完成"
else
  log_error "mihomo 重启失败"
fi

if service mosdns restart > /dev/null 2>&1; then
  log_success "mosdns 重启完成"
else
  log_error "mosdns 重启失败"
fi
echo ""

# 备份配置文件
log_step "备份配置文件..."
cp "$CONFIG_FILE" "$BACKUP_FILE" || {
  log_error "配置备份失败，终止操作！"
  echo ""
  exit 1
}
log_success "配置已备份到 $BACKUP_FILE"

TARGET_IF_BLOCK=$(awk '
BEGIN {
  in_block = 0
  current = ""
  found = ""
  max_opt = -1
}
{
  if ($0 ~ /^[[:space:]]*<opt[0-9]+>[[:space:]]*$/) {
    line = $0
    gsub(/^[[:space:]]*</, "", line)
    gsub(/>[[:space:]]*$/, "", line)
    current = line
    in_block = 1

    num = current
    sub(/^opt/, "", num)
    if ((num + 0) > max_opt) {
      max_opt = num + 0
    }
  }

  if (in_block && $0 ~ /<if>tun_3000<\/if>/) {
    found = current
  }

  if (in_block && current != "" && $0 ~ ("^[[:space:]]*</" current ">[[:space:]]*$")) {
    in_block = 0
    current = ""
  }
}
END {
  if (found != "") {
    print found
  } else {
    print "opt" (max_opt + 1)
  }
}
' "$CONFIG_FILE")

log_info "tun_3000 目标接口块：$TARGET_IF_BLOCK"

# 添加tun接口
log_step "添加 tun_3000 接口..."
if grep -q "<if>tun_3000</if>" "$CONFIG_FILE"; then
  log_warn "存在同名接口，忽略"
else
  awk -v target="$TARGET_IF_BLOCK" '
  BEGIN { inserted = 0 }
  {
    print
    if ($0 ~ /<\/lo0>/ && inserted == 0) {
      print "    <" target ">"
      print "      <if>tun_3000</if>"
      print "      <descr>TUN</descr>"
      print "      <enable>1</enable>"
      print "    </" target ">"
      inserted = 1
    }
  }
  END {
    if (inserted == 0) exit 1
  }
  ' "$CONFIG_FILE" > "$TMP_FILE"

  if [ $? -eq 0 ] && [ -s "$TMP_FILE" ]; then
    mv "$TMP_FILE" "$CONFIG_FILE"
    log_success "${TARGET_IF_BLOCK} 接口添加完成"
  else
    rm -f "$TMP_FILE"
    log_error "接口添加失败，请检查配置文件"
  fi
fi
echo ""

# 添加防火墙规则（允许TUN子网互访问）
log_step "添加防火墙规则..."
if grep -q "5a73c3dc-69b1-4e15-89cb-b542aa2c1154" "$CONFIG_FILE"; then
  log_warn "存在同名规则，忽略"
else
  awk -v target="$TARGET_IF_BLOCK" '
  BEGIN { inserted = 0 }
  {
    if ($0 ~ /<rules>/ && inserted == 0) {
      print
      print "          <rule uuid=\"5a73c3dc-69b1-4e15-89cb-b542aa2c1154\">"
      print "            <enabled>1</enabled>"
      print "            <statetype>keep</statetype>"
      print "            <state-policy/>"
      print "            <sequence>200</sequence>"
      print "            <action>pass</action>"
      print "            <quick>1</quick>"
      print "            <interfacenot>0</interfacenot>"
      print "            <interface>" target "</interface>"
      print "            <direction>in</direction>"
      print "            <ipprotocol>inet</ipprotocol>"
      print "            <protocol>any</protocol>"
      print "            <icmptype/>"
      print "            <icmp6type/>"
      print "            <source_net>" target "</source_net>"
      print "            <source_not>0</source_not>"
      print "            <source_port/>"
      print "            <destination_net>" target "</destination_net>"
      print "            <destination_not>0</destination_not>"
      print "            <destination_port/>"
      print "            <divert-to/>"
      print "            <gateway/>"
      print "            <replyto/>"
      print "            <disablereplyto>0</disablereplyto>"
      print "            <log>0</log>"
      print "            <allowopts>0</allowopts>"
      print "            <nosync>0</nosync>"
      print "            <nopfsync>0</nopfsync>"
      print "            <statetimeout/>"
      print "            <udp-first/>"
      print "            <udp-multiple/>"
      print "            <udp-single/>"
      print "            <max-src-nodes/>"
      print "            <max-src-states/>"
      print "            <max-src-conn/>"
      print "            <max/>"
      print "            <max-src-conn-rate/>"
      print "            <max-src-conn-rates/>"
      print "            <overload/>"
      print "            <adaptivestart/>"
      print "            <adaptiveend/>"
      print "            <prio/>"
      print "            <set-prio/>"
      print "            <set-prio-low/>"
      print "            <tag/>"
      print "            <tagged/>"
      print "            <tcpflags1/>"
      print "            <tcpflags2/>"
      print "            <tcpflags_any>0</tcpflags_any>"
      print "            <categories/>"
      print "            <sched/>"
      print "            <tos/>"
      print "            <shaper1/>"
      print "            <shaper2/>"
      print "            <description/>"
      print "          </rule>"
      inserted = 1
      next
    }
    print
  }
  END {
    if (inserted == 0) exit 1
  }
  ' "$CONFIG_FILE" > "$TMP_FILE"

  if [ $? -eq 0 ] && [ -s "$TMP_FILE" ]; then
    mv "$TMP_FILE" "$CONFIG_FILE"
    log_success "${TARGET_IF_BLOCK} 防火墙规则添加完成"
  else
    rm -f "$TMP_FILE"
    log_error "防火墙规则添加失败，请检查配置文件"
  fi
fi
echo ""

# 更改Unbound端口为 5355
sleep 1
log_step "更改 Unbound 端口..."

UNBOUND_STATE=$(awk '
BEGIN {
  in_unbound = 0
  in_general = 0
  has_5355 = 0
  has_other_port = 0
}
{
  if ($0 ~ /<unboundplus[^>]*>/ || $0 ~ /<unbound[^>]*>/) in_unbound = 1
  if (in_unbound && $0 ~ /<general>/) in_general = 1

  if (in_unbound && in_general && $0 ~ /<port>5355<\/port>/) has_5355 = 1
  if (in_unbound && in_general && $0 ~ /<port>[0-9]+<\/port>/ && $0 !~ /<port>5355<\/port>/) has_other_port = 1

  if (in_unbound && $0 ~ /<\/general>/) in_general = 0
  if ($0 ~ /<\/unboundplus>/ || $0 ~ /<\/unbound>/) {
    in_unbound = 0
    in_general = 0
  }
}
END {
  if (has_5355) {
    print "already_ok"
  } else if (has_other_port) {
    print "need_replace"
  } else {
    print "need_insert"
  }
}
' "$CONFIG_FILE")

if [ "$UNBOUND_STATE" = "already_ok" ]; then
  log_warn "端口已经为 5355，跳过"
else
  awk '
  BEGIN {
    in_unbound = 0
    in_general = 0
    port_handled = 0
  }
  {
    if ($0 ~ /<unboundplus[^>]*>/ || $0 ~ /<unbound[^>]*>/) {
      in_unbound = 1
    }

    if (in_unbound && $0 ~ /<general>/) {
      in_general = 1
      print
      next
    }

    if (in_unbound && in_general && $0 ~ /<\/general>/) {
      if (port_handled == 0) {
        print "        <port>5355</port>"
        port_handled = 1
      }
      in_general = 0
      print
      next
    }

    if (in_unbound && in_general && $0 ~ /<port>[0-9]+<\/port>/ && port_handled == 0) {
      sub(/<port>[0-9]+<\/port>/, "<port>5355</port>")
      port_handled = 1
      print
      next
    }

    print

    if ($0 ~ /<\/unboundplus>/ || $0 ~ /<\/unbound>/) {
      in_unbound = 0
      in_general = 0
    }
  }
  END {
    if (port_handled == 0) exit 1
  }
  ' "$CONFIG_FILE" > "$TMP_FILE"

  if [ $? -eq 0 ] && [ -s "$TMP_FILE" ]; then
    mv "$TMP_FILE" "$CONFIG_FILE"
    log_success "端口已设置为 5355"
  else
    rm -f "$TMP_FILE"
    log_error "修改失败，请检查配置文件"
  fi
fi
echo ""

log_step "清理菜单缓存..."
rm -f /var/lib/php/tmp/opnsense_menu_cache.xml
rm -f /var/lib/php/tmp/opnsense_acl_cache.json
log_success "菜单缓存清理完成"

# 重新载入configd
log_step "重新载入 configd..."
if service configd restart > /dev/null 2>&1; then
  log_success "configd 重新载入完成"
else
  log_error "configd 重新载入失败"
fi
echo ""

# 重启 Unbound DNS 服务
log_step "重启 Unbound DNS..."
if configctl unbound restart > /dev/null 2>&1; then
  log_success "Unbound DNS 重启完成"
else
  log_error "Unbound DNS 重启失败"
fi
echo ""

# 重新载入防火墙规则
log_step "重新加载防火墙规则..."
if configctl filter reload > /dev/null 2>&1; then
  log_success "防火墙规则重新加载完成"
else
  log_error "防火墙规则重新加载失败"
fi
echo ""

# 完成提示
log_success "安装完毕，请导航到 VPN > 代理 进行配置。配置过程请参考教程。"
echo ""