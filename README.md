## Mihomo for OPNsense
在 OPNsense 上运行 mihomo、mosdns，实现透明代理。支持订阅、DNS 分流。可以进行配置修改、程序控制、日志查看。在 OPNsense 26.1.6 上测试通过。

![](images/proxy.png)

## 集成程序
[MosDNS](https://github.com/IrineSistiana/mosdns) 

[Vincent-Loeng大佬魔改Mihomo](https://github.com/Vincent-Loeng/mihomo) 

## 注意事项
1. 当前仅支持 x86_64 平台。
2. 脚本不提供任何订阅信息，请准备好自己的订阅 URL。
3. 脚本会自动添加 tun 接口、防火墙规则，修改 dns 端口，重启服务并应用配置。
4. 脚本已集成了可用的默认配置，只需替换 proxies 和 rule 部分配置即可使用。
5. 为减少长期运行保存的日志数量，在调试完成后，请将所有配置的日志类型修改为 error 或 warn。

## 安装命令
```bash
sh install.sh
```
## 卸载命令
```bash
sh uninstall.sh
```

## 配置过程
1. 安装完成，转到接口>分配，将 tun_3000 虚拟网卡添加为接口并启用，无需输入 IPv4 地址和网关。
2. 为避免端口冲突，将 Unbound DNS 端口修改为5355端口，并作为 mosdns 的默认上游 DNS。
3. 转到防火墙>规则(新)，在 tun 接口添加一条any to any防火墙规则，允许 tun 子网访问。
4. 导航到 VPN>代理 菜单，修改 mihomo 配置并保存。
5. 启动服务，客户端访问 ip111.cn，检查分流是否正常。

## 其他事项
1. 在 OPNsense上，stack 参数只能使用 gvisor栈。
2. 默认配置文件开启了 api 功能，访问 http://lan_ip:9090/ui 登录仪表盘。
3. 转到系统>设置>任务，添加”Renew mihomo Subsribe”和“mosdns rule_list updates”任务，自动更新订阅和规则列表。
