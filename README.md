# Hysteria 2 一键安装管理脚本

这是一个用于安装和管理 Hysteria 2 的 Shell 脚本，支持 Alpine Linux 在内的多个 Linux 发行版。

## 功能特点

- 支持多个 Linux 发行版（包括 Alpine Linux）
- 自动检测系统类型并安装依赖
- 交互式配置，包括端口、密码、域名等
- 支持 ACME 自动申请证书
- 支持自定义 ACL 规则
- 自动生成分享链接和二维码
- 注册系统命令 `hy2` 便于管理
- 支持开机自启动

## 快速开始

### 安装

```bash
wget -O /usr/local/bin/hy2 https://raw.githubusercontent.com/your-repo/hy2.sh
chmod +x /usr/local/bin/hy2
hy2
```

### 使用方法

安装完成后，可以使用 `hy2` 命令进行管理，支持以下功能：

1. 安装 Hysteria 2
2. 更新 Hysteria 2
3. 卸载 Hysteria 2
4. 启动 Hysteria 2
5. 停止 Hysteria 2
6. 重启 Hysteria 2
7. 查看运行状态
8. 查看配置
9. 修改配置
10. 查看日志
11. 查看分享链接
12. 显示分享二维码

## 配置说明

### 基础配置

- 端口：默认 5525
- 密码：默认随机生成
- 伪装站点：默认 https://news.ycombinator.com/

### ACME 配置

如果选择配置域名，脚本会自动：
- 配置 ACME 自动申请证书
- 使用域名生成分享链接

### ACL 规则

支持两种配置方式：
1. 使用预设规则（屏蔽中国 IP 和广告域名）
2. 自定义 ACL 规则

## 系统要求

- 支持的系统：
  - Alpine Linux
  - Debian/Ubuntu
  - CentOS/RHEL
  - 其他主流 Linux 发行版

- 需要 root 权限
- 需要基本的网络连接

## 注意事项

1. 使用域名功能前请确保：
   - 域名已经正确解析到服务器 IP
   - 服务器防火墙已开放相应端口

2. 首次安装后建议：
   - 保存好生成的配置信息
   - 保存分享链接和二维码
   - 测试连接是否正常

3. 如果使用 ACL 规则：
   - 规则按从上到下的顺序匹配
   - 建议参考官方文档了解更多规则用法

## 问题反馈

如果遇到问题，请提供以下信息：
1. 系统版本
2. 错误信息
3. 相关日志

## 许可证

MIT License

## 鸣谢

- [Hysteria 2](https://github.com/apernet/hysteria)
- 所有贡献者和用户
