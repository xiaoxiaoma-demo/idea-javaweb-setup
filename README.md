# IDEA JavaWeb Setup

`idea-javaweb-setup` 是一个用于 **传统 Java Web（前后端不分离）项目** 的 Codex Skill，
可自动生成/修正 IntelliJ IDEA 项目配置，减少手动点选配置的时间。

## 功能概览

- 自动配置 Project Structure 关键项（JDK 1.8、Facet、Artifact 等）
- 维护 Tomcat Local 运行配置（写入 `.idea/workspace.xml`）
- 统一项目编码为 UTF-8（项目级）
- 支持 `horizon` 项目根据 `workflow_url` 推导端口和 context path
- 自动处理同级项目 JNDI 端口冲突（1099 起递增）

## 适用场景

- 老 Java Web 项目（典型目录含 `src` 与 `WebRoot/web`）
- 需要快速批量初始化 IDEA 运行环境
- 团队希望统一本地工程结构和 Tomcat 运行配置

## 仓库结构

```text
idea-javaweb-setup/
├─ SKILL.md
└─ scripts/
   └─ configure_idea_javaweb.ps1
```

## 使用方式

在 Codex 中触发该 skill 后，按 `SKILL.md` 指引执行脚本。

单项目示例：

```powershell
powershell -ExecutionPolicy Bypass -File "scripts/configure_idea_javaweb.ps1" -ProjectPath "<project-path>" -ProjectName "<project-name>"
```

多项目示例：

```powershell
powershell -ExecutionPolicy Bypass -File "scripts/configure_idea_javaweb.ps1" -ProjectPath "<path-1>,<path-2>" -ProjectName "<name-1>,<name-2>"
```

## 关键约束

- 不创建共享 run config（`.idea/runConfigurations` 或 `.run`）
- 本项目风格统一维护到 `.idea/workspace.xml`
- 不强制写 `OPEN_IN_BROWSER_URL`
- `jszgbm` 默认 `CONTEXT_PATH` 为空（除非显式覆盖）

## 注意事项

- 本 skill 只改项目级 IDEA 文件，不修改 IntelliJ 全局设置。
- 执行前请确认项目路径与项目名准确。
- 建议先提交一次当前工程状态，再执行自动配置脚本。

