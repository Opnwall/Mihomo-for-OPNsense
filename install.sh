#!/bin/bash
echo -e ''
echo -e "\033[32m========Clash for OPNsense 代理全家桶一键安装脚本=========\033[0m"
echo -e ''

# 定义颜色变量
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
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

# 定义日志函数
log() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${RESET}"
}

# 创建目录
log "$YELLOW" "创建目录..."
mkdir -p "$CONF_DIR/clash" "$CONF_DIR/mosdns" || log "$RED" "目录创建失败！"

# 复制文件
log "$YELLOW" "复制文件..."
log "$YELLOW" "生成菜单..."
# 删除菜单缓存
rm -f /tmp/opnsense_menu_cache.xml
rm -f /tmp/opnsense_acl_cache.json
log "$YELLOW" "生成服务..."
log "$YELLOW" "添加权限..."
chmod +x ./bin/* ./rc.d/*
cp -f bin/* "$BIN_DIR/" || log "$RED" "bin 文件复制失败！"
cp -f www/* "$WWW_DIR/" || log "$RED" "www 文件复制失败！"
cp -f rc.d/* "$RC_DIR/" || log "$RED" "rc.d 文件复制失败！"
cp -f rc.conf/* "$RC_CONF/" || log "$RED" "rc.conf 文件复制失败！"
cp -f plugins/* "$PLUGINS/" || log "$RED" "plugins 文件复制失败！"
cp -f actions/* "$ACTIONS/" || log "$RED" "actions 文件复制失败！"
cp -R -f menu/* "$MENU_DIR/" || log "$RED" "menu 文件复制失败！"
cp -R -f conf/* "$CONF_DIR/clash/" || log "$RED" "conf 文件复制失败！"
cp -R -f mosdns/* "$CONF_DIR/mosdns/" || log "$RED" "mosdns 文件复制失败！"

# 新建订阅程序
log "$YELLOW" "添加订阅..."
cat>/usr/bin/sub<<EOF
# 启动clash订阅程序
bash /usr/local/etc/clash/sub/sub.sh
EOF
chmod +x /usr/bin/sub

# 安装bash
log "$GREEN" "安装bash..."
if ! pkg info -q bash > /dev/null 2>&1; then
  pkg install -y bash > /dev/null 2>&1
fi

# 启动Tun接口
log "$YELLOW" "启动clash..."
service clash start > /dev/null 2>&1
echo ""

# 备份配置文件
cp "$CONFIG_FILE" "$BACKUP_FILE" || {
  echo "配置备份失败，终止操作！"
  echo ""
  exit 1
}

# 添加tun接口
log "$YELLOW" "添加tun接口..."
if grep -q "<if>tun_3000</if>" "$CONFIG_FILE"; then
  echo "存在同名接口，忽略"
  echo ""
else
  awk '
  BEGIN { inserted = 0 }
  /<interfaces>/ { print; next }
  /<\/interfaces>/ && inserted == 0 {
    print "    <tun_3000>"
    print "      <if>tun_3000</if>"
    print "      <descr>TUN</descr>"
    print "      <enable>1</enable>"
    print "      <spoofmac/>"
    print "      <gateway_interface>1</gateway_interface>"
    print "      <ipaddr>10.10.0.1</ipaddr>"
    print "      <subnet>32</subnet>"
    print "    </tun_3000>"
    inserted = 1
  }
  { print }
  ' "$CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"
  echo "接口添加完成"
  echo ""
fi

# 添加防火墙规则（将流量导入TUN_GW）
log "$YELLOW" "添加分流规则..."
if grep -q "<gateway>TUN_GW</gateway>" "$CONFIG_FILE"; then
  echo "存在同名规则，忽略"
  echo ""
else
  awk '
  /<filter>/ {
    print
    print "    <rule uuid=\"c0398153-597b-403b-9069-734734b46497\">"
    print "      <type>pass</type>"
    print "      <interface>lan</interface>"
    print "      <ipprotocol>inet</ipprotocol>"
    print "      <statetype>keep state</statetype>"
    print "      <gateway>TUN_GW</gateway>"
    print "      <direction>in</direction>"
    print "      <floating>yes</floating>"
    print "      <quick>1</quick>"
    print "      <source>"
    print "        <network>lan</network>"
    print "      </source>"
    print "      <destination>"
    print "        <any>1</any>"
    print "      </destination>"
    print "    </rule>"
    next
  }
  { print }
  ' "$CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"
  echo "规则添加完成"
  echo ""
fi

# 更改Unbound端口为 5355
sleep 1
log "$YELLOW" "更改Unbound端口..."

PORT_OK=$(awk '
BEGIN {
  in_unbound = 0
  in_general = 0
}
/<unboundplus[^>]*>/ { in_unbound = 1 }
/<\/unboundplus>/ { in_unbound = 0 }
{
  if (in_unbound && /<general>/) {
    in_general = 1
  }
  if (in_unbound && /<\/general>/) {
    in_general = 0
  }
  if (in_unbound && in_general && /<port>5355<\/port>/) {
    print "yes"
    exit
  }
}
' "$CONFIG_FILE")

if [ "$PORT_OK" = "yes" ]; then
  echo "端口已经为5355，跳过"
else
  awk '
  BEGIN {
    in_unbound = 0
    in_general = 0
    port_handled = 0
  }
  {
    if ($0 ~ /<unboundplus[^>]*>/) {
      in_unbound = 1
    }
    if ($0 ~ /<\/unboundplus>/) {
      in_unbound = 0
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

    if (in_unbound && in_general && $0 ~ /<port>.*<\/port>/ && port_handled == 0) {
      sub(/<port>.*<\/port>/, "<port>5355</port>")
      port_handled = 1
      print
      next
    }

    print
  }
  ' "$CONFIG_FILE" > "$TMP_FILE"

  if [ -s "$TMP_FILE" ]; then
    mv "$TMP_FILE" "$CONFIG_FILE"
    echo "端口已设置为5355"
  else
    log "$RED" "修改失败，请检查配置文件"
  fi
fi
echo ""

# 添加订阅和更新任务
log "$YELLOW" "添加订阅和GeoIP（程序）更新任务..."
insert_job_if_missing() {
  CMD="$1"
  JOB_XML="$2"

  if grep -q "<command>$CMD</command>" "$CONFIG_FILE"; then
    echo "任务已存在: $CMD，跳过插入。"
    return
  fi

  echo "插入任务: $CMD"
  echo "$JOB_XML" > /tmp/job_insert.xml

  if grep -q "<jobs/>" "$CONFIG_FILE"; then
    # 如果是空的 <jobs/>，替换为 <jobs>...内容...</jobs>
    awk -v jobfile="/tmp/job_insert.xml" '
      /<jobs\/>/ {
        print "<jobs>"
        while ((getline line < jobfile) > 0) print line
        print "</jobs>"
        next
      }
      { print }
    ' "$CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"
  elif grep -q "<jobs>" "$CONFIG_FILE"; then
    # 否则插入到 </jobs> 前
    awk -v jobfile="/tmp/job_insert.xml" '
      /<\/jobs>/ {
        while ((getline line < jobfile) > 0) print line
      }
      { print }
    ' "$CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"
  else
    echo "错误：未找到 <jobs> 或 <jobs/> 标签，无法插入任务。" >&2
  fi

  rm -f /tmp/job_insert.xml
}

# Job 1 内容
JOB1='        <job uuid="5f284598-ed63-4aa6-845a-f53882583dd7">
          <origin>cron</origin>
          <enabled>1</enabled>
          <minutes>0</minutes>
          <hours>2</hours>
          <days>6</days>
          <months>*</months>
          <weekdays>*</weekdays>
          <who>root</who>
          <command>mosdns update</command>
          <parameters/>
          <description>&#x66F4;&#x65B0;&#x4EE3;&#x7406;&#x548C;GEO&#x6570;&#x636E;</description>
        </job>'

# Job 2 内容
JOB2='        <job uuid="388fcf06-888e-4781-b8f9-95142ce3c71c">
          <origin>cron</origin>
          <enabled>1</enabled>
          <minutes>0</minutes>
          <hours>3</hours>
          <days>6</days>
          <months>*</months>
          <weekdays>*</weekdays>
          <who>root</who>
          <command>clash sub-update</command>
          <parameters/>
          <description>Clash&#x8BA2;&#x9605;&#x66F4;&#x65B0;</description>
        </job>'

# 插入任务
insert_job_if_missing "mosdns update" "$JOB1"
insert_job_if_missing "clash sub-update" "$JOB2"
echo ""

# 重载 cron 服务
log "$YELLOW" "重启cron服务..."
/usr/local/sbin/configctl cron restart > /dev/null 2>&1
echo ""

# 重启服务Unbound
log "$YELLOW" "重启Unbound服务..."
/usr/local/etc/rc.d/unbound restart > /dev/null 2>&1
echo ""

# 重新载入防火墙规则
log "$YELLOW" "重新载入防火墙规则..."
configctl filter reload > /dev/null 2>&1
echo ""

# 重新载入configd
log "$YELLOW" "重新载入configd..."
service configd restart > /dev/null 2>&1
echo ""

# 重启所有服务
# log "$YELLOW" "应用所有更改，请稍等..."
# /usr/local/etc/rc.reload_all >/dev/null 2>&1
# echo "所有服务已重新加载！"
# echo ""

# 完成提示
log "$GREEN" "安装完毕，请刷新浏览器，导航到VPN > Proxy Suite 进行配置。配置完成，请重启防火墙让新配置生效。"
echo ""