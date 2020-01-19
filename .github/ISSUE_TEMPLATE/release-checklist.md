---
name: Release checklist
about: Release checklist.
title: Release checklist
labels: ''
assignees: ''

---

# Changelog

## Features
- [ ] Features

## Bug fixes
- [ ] Bug fixes

## Enhancements
- [ ] Enhancements

## Tech debt
- [ ] Tech debt

# 通用
- [ ] 关闭 SSH 服务
- [ ] 清除 .bash_history（包括 ubuntu 和 root 用户）
- [ ] 安装 arping 防止同网段虚机和 IP 地址频繁重建引起的问题（apt install iputils-arping）
- [ ] TCP keepalive timeout（基础网络）
- [ ] 支持 NeonSAN（硬盘类型 5 和 6）
- [ ] 支持新实例类型（101，201，301）
- [ ] update document

# 服务功能测试

- [ ] 写入数据，自定义客户端正常读取
- [ ] 在配置项中可自由开关caddy
- [ ] confd升级到最新版本
- [ ] 通过浏览器查看服务日志
- [ ] 日志轮转
- [ ] docker push/pull
- [ ] http/https
- [ ] harbor delete/tag image/repository/project, check local/qingstor storage, (垃圾清理成功之后才会真正删除，web->任务->垃圾清理）
- [ ] helm upload download delete(检查项类似于image, 检查存储)
- [ ] project user group tag tag保留  robot webhook
- [ ] 镜像复制(local <--> 对象存储)
- [ ] 配置管理-->认证模式LDAP 项目定额

# 集群功能测试

## 创建
- [ ] 创建默认配置的集群
- [ ] 创建常用硬件配置的集群
- [ ] 修改常用配置参数，创建集群

## 横向伸缩
- [ ] 增加节点，数据正常
- [ ] 删除节点

## 纵向伸缩
- [ ] 扩容：服务正常
- [ ] 缩容：服务正常

## 升级
- [ ] 数据不丢
- [ ] 升级后设置日志留存大小限制值，查看日志留存配置生效

## 其他
- [ ] 关闭集群并启动集群
- [ ] 删除集群并恢复集群
- [ ] 备份集群并恢复集群
- [ ] 支持多可用区
- [ ] 切换私有网络
- [ ] 绑定公网 IP(vpc)
- [ ] 基础网络部署
- [ ] 自动伸缩（节点数，硬盘容量）
- [ ] 健康检查和自动重启
- [ ] 服务监控

# 高可用

- [ ] 主服务节点断网
- [ ] 关闭服务后，服务可自动启动

# Long Run

- [ ] UI界面中循环进行创建集群--增删节点--重启集群--扩容集群--删除集群的操作
- [ ] 在10G存储，且内存使用率为95%的集群中，循环进行增删节点--扩容缩容集群--重启集群的操作

# 上线

- [ ] 老区（广东 1 区、亚太 1 区）有可部署的版本
- [ ] 所有区可以正常部署
- [ ] 服务价格改为 0
- [ ] 版本号合理命名
