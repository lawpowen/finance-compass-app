# Homelab Web 17 部署归档

本提交记录 2026-11-24 在 Homelab 运行的 Web 17 同步版本。Web 源码来自部署目录保留的构建输入包，包的 SHA-256 为 `3bfe808954a1072b6225ef816768c212daea182938db371edc7ac6e9bd128eb0`。

## 核对依据

- 部署目录为 `releases/floating-dock-20261124-17`。该目录由源码包展开，原部署没有 Git 提交。
- 运行中的 Web 镜像为 `sha256:aa8b88bece7f847294642151b3f51804de3c55b5f683dc5e446cad8d`。容器的 Caddyfile 和 Service Worker 与源码包字节一致，缓存标识为 `finance-compass-shell-consent-v0.10.1-sync17`。
- 同步镜像为 `sha256:c1d74cd4eb86e4284b84a38f2b31afdaf4e6c5fe5c809ea95c1c016d5e3c61b1`。容器内 12 份 JavaScript 源码及依赖清单的 SHA-256 均与包内对应文件一致。

## 范围与后续使用

源码包包含 Flutter 运行代码、Web 资源、构建工具、字体、Compose 配置和同步后端。包外的桌面及移动平台工程、开发文档和测试继承自 GitHub 基线 `e1db7ae`。因此这些文件视为继承内容，Web 17 当时的开发目录不能由部署包完全复原。源码文本按本仓库 Git 的换行规则保存。原始包及容器文件的 SHA-256 依据未转换的内容计算。

应用使用账号隔离的同步账本及单独的 SQLite 数据卷。部署和回滚通过 `deploy/sync/compose.yml` 操作。生产环境变量放在源码目录之外。升级和切换镜像前先使用 `server/backup.mjs` 生成并核验一致性备份，保留数据卷及入口状态。
