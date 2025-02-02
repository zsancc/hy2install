# Alpine Hysteria 2 安装脚本

这是一个用于 Alpine Linux 的 Hysteria 2 一键安装管理脚本。

## 快速安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/zsancc/hy2install/main/alpinehy2install.sh)
```

## 功能特点

- 专为 Alpine Linux 优化
- 支持多种 TLS 验证方式：
  1. 自定义证书（适用于 NAT VPS）
  2. ACME HTTP 验证（需要 80 端口）
  3. Cloudflare DNS 验证
- 自动生成分享链接和二维码
- 注册系统命令 `hy2` 便于管理
- 支持开机自启动

## 管理命令

安装完成后，运行 `hy2` 命令进入管理菜单：

1. 更新 Hysteria 2
2. 卸载 Hysteria 2
3. 启动服务
4. 停止服务
5. 重启服务
6. 查看状态
7. 查看配置
8. 修改配置
9. 查看日志
10. 查看分享链接
11. 显示分享二维码

## 配置说明

### 基础配置
- 端口：默认 5525
- 密码：默认随机生成
- 伪装站点：默认 https://news.ycombinator.com/

### TLS 配置选项
1. 自定义证书：
   - 适用于 NAT VPS 或已有证书
   - 需要提供证书和私钥路径

2. ACME HTTP 验证：
   - 需要域名已解析到服务器
   - 需要 80 端口可用
   - 自动申请和续期证书

3. Cloudflare DNS 验证：
   - 需要域名使用 Cloudflare 解析
   - 需要 Cloudflare API Token
   - 支持泛域名证书

## 系统要求

- Alpine Linux
- Root 权限
- 基本网络连接

## 注意事项

1. 使用域名功能前请确保：
   - 域名已正确解析
   - 相应端口已开放

2. 使用 Cloudflare DNS 验证时：
   - 需要在 Cloudflare 面板中创建 API Token
   - Token 位置：我的个人资料->API令牌->创建Token->使用 Edit zone DNS 模板->权限类型：Zone / DNS / Edit,资源：Include / Specific zone / 选择你的域名（如 baidu.com）

## 问题反馈

如遇问题，请提供：
1. Alpine 版本
2. 错误信息
3. 相关日志（`hy2` 命令中的查看日志功能）

## 许可证

MIT License

## 鸣谢

- [Hysteria 2](https://github.com/apernet/hysteria)
- 所有贡献者和用户
