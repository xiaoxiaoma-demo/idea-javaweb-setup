# IDEA JavaWeb Setup

`idea-javaweb-setup` 是一个用于 **传统 Java Web（前后端不分离）项目** 的 Codex Skill，
可自动生成/修正 IntelliJ IDEA 项目配置，减少手动点选配置的时间。

## 功能概览

- 自动配置 Project Structure 关键项（JDK 1.8、Facet、Artifact 等）
- 维护 Tomcat Local 运行配置（写入 `.idea/workspace.xml`）
- 统一项目编码为 UTF-8（项目级）
- 支持 `horizon` 项目根据 `workflow_url` 推导端口和 context path
- 自动处理同级项目 JNDI 端口冲突（1099 起递增）
- 项目名支持用户显式指定；未指定时自动从现有 IDEA 配置或 `*.iml` 推导，不再强依赖目录名

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
powershell -ExecutionPolicy Bypass -File "scripts/configure_idea_javaweb.ps1" -ProjectPath "<project-path>" [-ProjectName "<project-name>"]
```

多项目示例：

```powershell
powershell -ExecutionPolicy Bypass -File "scripts/configure_idea_javaweb.ps1" -ProjectPath "<path-1>,<path-2>" [-ProjectName "<name-1>,<name-2>"]
```

自动解析规则：

- 如果传入的是工作区根目录，且存在唯一一个符合 `src` + `WebRoot/web` 结构的子目录，会自动定位到该项目目录
- 如果未传 `ProjectName`，优先读取 `.idea/modules.xml` 中现有 module 名
- 若没有 `modules.xml`，且项目根目录只有一个 `*.iml`，则使用该文件名
- 以上都没有时，才回退到项目目录名

## 关键约束

- 不创建共享 run config（`.idea/runConfigurations` 或 `.run`）
- 本项目风格统一维护到 `.idea/workspace.xml`
- 不强制写 `OPEN_IN_BROWSER_URL`
- `jszgbm` 默认 `CONTEXT_PATH` 为空（除非显式覆盖）

## 注意事项

- 本 skill 只改项目级 IDEA 文件，不修改 IntelliJ 全局设置。
- 执行前请确认项目路径准确；项目名可选，不传时会自动解析。
- 建议先提交一次当前工程状态，再执行自动配置脚本。

