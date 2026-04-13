---
name: idea-javaweb-setup
description: "Configure IntelliJ IDEA for legacy Java Web projects (non-separate frontend/backend): JDK 1.8, Web Facet, exploded-war artifact, Tomcat run config, UTF-8 encoding, and horizon workflow_url-based port rule (without forcing OPEN_IN_BROWSER_URL)."
---

# IDEA JavaWeb Setup Skill

Use this skill when the user wants Codex to auto-configure IntelliJ IDEA project files for old-style Java Web projects.

## Scope

- Project Structure basics: JDK/language level/module/facet/library/artifact
- Tomcat Local run configuration
- UTF-8 project encodings
- Special rule: `horizon` port/context from `workflow_url`
- JNDI port de-duplication across sibling projects (conflict => `+1`)
- Local Tomcat run config should be maintained in `.idea/workspace.xml` for this project style

## Required confirmation

Before writing files, confirm with user in chat:
1. Target project path(s)
2. Target project name(s), if the user wants to override auto-detected names

Script execution must require terminal input `Y` to continue by default.
For multi-project setup, confirm once and execute all.

## Execution workflow

1. Resolve target project path and project name(s).
   - Preferred: user gives exact project directory.
   - If user gives workspace root and `<root>/<project-name>` matches JavaWeb layout (`src` + `WebRoot/web`), script auto-corrects to that child path.
   - If user gives workspace root and there is exactly one child directory matching JavaWeb layout (`src` + `WebRoot/web`), script auto-detects that child even when project name is omitted.
   - If user omits `ProjectName`, script auto-detects it in this order:
     1. existing `.idea/modules.xml` referenced module name
     2. the only `*.iml` file in project root
     3. project directory name as final fallback
2. Confirm with user in chat.
3. Run (single project):

```powershell
powershell -ExecutionPolicy Bypass -File "C:/Users/mamama/.codex/skills/idea-javaweb-setup/scripts/configure_idea_javaweb.ps1" -ProjectPath "<project-path>" [-ProjectName "<project-name>"]
```

4. Run (batch two projects, one `Y` confirmation):

```powershell
powershell -ExecutionPolicy Bypass -File "C:/Users/mamama/.codex/skills/idea-javaweb-setup/scripts/configure_idea_javaweb.ps1" -ProjectPath "<path-1>,<path-2>" [-ProjectName "<name-1>,<name-2>"]
```

5. Report changed files and key runtime values (HTTP port, JNDI port, context path, tomcat name).

## Hard constraints from execution lessons

- Do not create shared run-config files (`.idea/runConfigurations` or `.run`) for this project style.
- Keep local run config in `.idea/workspace.xml` and keep naming style consistent (e.g. `Tomcat 8.5.72`, no extra suffix like `- horizon`).
- Do not assume module file is always `<project>/<name>.iml`; parse existing `.idea/modules.xml` and write Facet into the module file IDEA actually references.
- Keep artifact facet/module name consistent with resolved module name.
- Keep JNDI port unique among sibling projects:
  - default base `1099`
  - if occupied, increment (`1100`, `1101`, ...)
- In Tomcat Local server-settings, keep HTTP_PORT and JNDI_PORT as sibling options.
- Do not write OPEN_IN_BROWSER_URL in run configuration.
- For `jszgbm`, keep deployment `CONTEXT_PATH` empty (`value=""`) unless explicitly overridden by script parameter.
- SKILL.md must be saved as UTF-8 without BOM, and the first byte of file must start with --- frontmatter delimiter.
- Keep `BASE_DIRECTORY_NAME` in `server-settings` (reuse existing value when present).
- If wrong parent path was configured previously, cleanup should be explicit and user-confirmed.

## Notes

- This skill updates project-level IDEA files only.
- IntelliJ global setting `Settings -> Editor -> File Encodings -> Global Encoding` is IDE-user scope and is not guaranteed to be enforced by project files.



