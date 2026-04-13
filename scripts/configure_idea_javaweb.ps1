param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,
    [string]$ProjectName,
    [string]$TomcatName = "Tomcat 8.5.72",
    [string]$JdkName = "1.8",
    [int]$HttpPort = 8080,
    [int]$BaseJndiPort = 1099,
    [string]$ContextPath,
    [string]$WorkflowUrl,
    [switch]$UseWorkflowUrlRule = $true,
    [switch]$SkipConfirm = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$Path) {
    if (!(Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory | Out-Null
    }
}

function Get-WorkflowUrlFromYaml([string]$YamlPath) {
    if (!(Test-Path $YamlPath)) { return $null }
    $line = Select-String -Path $YamlPath -Pattern '^\s*workflow_url\s*:\s*(\S+)' | Select-Object -First 1
    if ($null -eq $line) { return $null }
    return $line.Matches[0].Groups[1].Value.Trim()
}

function Test-JavaWebProjectLayout([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path $Path)) { return $false }
    $hasSrc = Test-Path (Join-Path $Path 'src')
    $hasWebRoot = (Test-Path (Join-Path $Path 'WebRoot')) -or (Test-Path (Join-Path $Path 'web'))
    return ($hasSrc -and $hasWebRoot)
}

function Find-WorkflowUrl([string]$ProjectPath, [string]$ProjectName, [string]$GivenWorkflowUrl) {
    if ($GivenWorkflowUrl) { return $GivenWorkflowUrl }

    $localYaml = Join-Path $ProjectPath 'resources/application.yml'
    $local = Get-WorkflowUrlFromYaml -YamlPath $localYaml
    if ($local) { return $local }

    $parent = Split-Path -Path $ProjectPath -Parent
    if (!(Test-Path $parent)) { return $null }

    $candidates = Get-ChildItem -Path $parent -Directory | ForEach-Object {
        Join-Path $_.FullName 'resources/application.yml'
    } | Where-Object { Test-Path $_ }

    foreach ($yaml in $candidates) {
        $u = Get-WorkflowUrlFromYaml -YamlPath $yaml
        if ($u -and $u -match "/$ProjectName/?$") { return $u }
    }
    return $null
}

function Resolve-ProjectPath([string]$PathIn, [string]$ProjectName) {
    $resolved = (Resolve-Path $PathIn).Path
    if (Test-JavaWebProjectLayout -Path $resolved) { return $resolved }

    if ($ProjectName) {
        $candidate = Join-Path $resolved $ProjectName
        if (Test-JavaWebProjectLayout -Path $candidate) {
            Write-Warning "ProjectPath appears to be workspace root. Auto-corrected to: $candidate"
            return (Resolve-Path $candidate).Path
        }
    }

    $childProjects = @(Get-ChildItem -Path $resolved -Directory -ErrorAction SilentlyContinue | Where-Object {
        Test-JavaWebProjectLayout -Path $_.FullName
    })
    if ($childProjects.Count -eq 1) {
        Write-Warning "ProjectPath appears to be workspace root. Auto-detected child project: $($childProjects[0].FullName)"
        return $childProjects[0].FullName
    }

    return $resolved
}

function Get-RelativePath([string]$BasePath, [string]$TargetPath) {
    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\')
    $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath)
    $baseUri = [uri]($baseFullPath + '\')
    $targetUri = [uri]$targetFullPath
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    return [uri]::UnescapeDataString($relativeUri.ToString()).Replace('/', '\')
}

function Resolve-ModuleDefinition([string]$ProjectPath, [string]$ExplicitProjectName) {
    $ideaDir = Join-Path $ProjectPath '.idea'
    $modulesXmlPath = Join-Path $ideaDir 'modules.xml'
    $existingImlPath = $null
    $resolvedImlPath = $null
    $resolvedName = $null

    if (Test-Path $modulesXmlPath) {
        try {
            [xml]$modulesDoc = Get-Content $modulesXmlPath
            $moduleNodes = @($modulesDoc.SelectNodes('/project/component[@name="ProjectModuleManager"]/modules/module'))
            foreach ($moduleNode in $moduleNodes) {
                $rawPath = $moduleNode.filepath
                if ([string]::IsNullOrWhiteSpace($rawPath)) {
                    $rawPath = $moduleNode.fileurl -replace '^file://', ''
                }
                if ([string]::IsNullOrWhiteSpace($rawPath)) { continue }

                $candidateRelative = $rawPath.Replace('$PROJECT_DIR$', '').TrimStart('/','\').Replace('/', '\')
                $candidatePath = Join-Path $ProjectPath $candidateRelative
                if (Test-Path $candidatePath) {
                    $existingImlPath = (Resolve-Path $candidatePath).Path
                    break
                }
            }
        } catch {
            Write-Warning "Failed to parse existing modules.xml: $modulesXmlPath"
        }
    }

    if ($ExplicitProjectName) {
        if ($existingImlPath -and [System.IO.Path]::GetFileNameWithoutExtension($existingImlPath) -ieq $ExplicitProjectName) {
            $resolvedImlPath = $existingImlPath
        } else {
            $explicitImlPath = Join-Path $ProjectPath "$ExplicitProjectName.iml"
            if ($existingImlPath) {
                $explicitImlPath = Join-Path (Split-Path -Path $existingImlPath -Parent) "$ExplicitProjectName.iml"
            }
            $resolvedImlPath = $explicitImlPath
        }
        $resolvedName = $ExplicitProjectName
    } elseif ($existingImlPath) {
        $resolvedImlPath = $existingImlPath
        $resolvedName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedImlPath)
    } else {
        $rootImlFiles = @(Get-ChildItem -Path $ProjectPath -Filter '*.iml' -File -ErrorAction SilentlyContinue)
        if ($rootImlFiles.Count -eq 1) {
            $resolvedImlPath = $rootImlFiles[0].FullName
            $resolvedName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedImlPath)
        }
    }

    if (-not $resolvedImlPath) {
        $resolvedName = Split-Path -Path $ProjectPath -Leaf
        $resolvedImlPath = Join-Path $ProjectPath "$resolvedName.iml"
    }

    return [pscustomobject]@{
        ProjectName = $resolvedName
        ModuleImlPath = $resolvedImlPath
        ModuleImlRelativePath = Get-RelativePath -BasePath $ProjectPath -TargetPath $resolvedImlPath
    }
}

function Split-ListArg([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return ,@() }
    return ,@($Value -split '\s*[,;]\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-UsedJndiPorts([string]$ScanRoot, [string]$CurrentProjectPath) {
    $used = New-Object System.Collections.Generic.List[int]
    if (!(Test-Path $ScanRoot)) { return @() }

    $projectDirs = Get-ChildItem -Path $ScanRoot -Directory -ErrorAction SilentlyContinue
    foreach ($d in $projectDirs) {
        if ($d.FullName -ieq $CurrentProjectPath) { continue }
        $workspace = Join-Path $d.FullName '.idea/workspace.xml'
        if (!(Test-Path $workspace)) { continue }
        $hits = Select-String -Path $workspace -Pattern '<option name="JNDI_PORT" value="(\d+)"' -AllMatches -ErrorAction SilentlyContinue
        foreach ($h in $hits) {
            foreach ($m in $h.Matches) {
                [void]$used.Add([int]$m.Groups[1].Value)
            }
        }
    }
    return @($used | Sort-Object -Unique)
}

function Resolve-JndiPort([int]$BasePort, [int[]]$UsedPorts) {
    $p = $BasePort
    while ($UsedPorts -contains $p) { $p++ }
    return $p
}

function Get-BaseDirectoryName([string]$WorkspacePath, [string]$TomcatName) {
    if (Test-Path $WorkspacePath) {
        try {
            [xml]$doc = Get-Content $WorkspacePath
            $config = $doc.SelectSingleNode("/project/component[@name='RunManager']/configuration[@type='#com.intellij.j2ee.web.tomcat.TomcatRunConfigurationFactory' and @factoryName='Local' and @APPLICATION_SERVER_NAME='$TomcatName']")
            if ($null -eq $config) {
                $config = $doc.SelectSingleNode("/project/component[@name='RunManager']/configuration[@name='$TomcatName' and @type='#com.intellij.j2ee.web.tomcat.TomcatRunConfigurationFactory' and @factoryName='Local']")
            }
            if ($null -ne $config) {
                $baseOption = $config.SelectSingleNode("server-settings/option[@name='BASE_DIRECTORY_NAME']")
                if ($null -ne $baseOption -and -not [string]::IsNullOrWhiteSpace($baseOption.value)) {
                    return $baseOption.value
                }
            }
        } catch {
            # ignore parse errors and generate new id
        }
    }
    return [guid]::NewGuid().ToString()
}

function Build-RunManagerXml(
    [string]$TomcatName,
    [string]$ProjectName,
    [string]$ContextPath,
    [int]$HttpPort,
    [int]$JndiPort,
    [string]$BaseDirectoryName
) {
@"
<component name="RunManager">
  <configuration name="$TomcatName" type="#com.intellij.j2ee.web.tomcat.TomcatRunConfigurationFactory" factoryName="Local" APPLICATION_SERVER_NAME="$TomcatName" ALTERNATIVE_JRE_ENABLED="false" nameIsGenerated="true">
    <option name="COMMON_VM_ARGUMENTS" value="-Dfile.encoding=UTF-8" />
    <option name="UPDATING_POLICY" value="restart-server" />
    <deployment>
      <artifact name="$ProjectName">
        <settings>
          <option name="CONTEXT_PATH" value="$ContextPath" />
        </settings>
      </artifact>
    </deployment>
    <server-settings>
      <option name="BASE_DIRECTORY_NAME" value="$BaseDirectoryName" />
      <option name="HTTP_PORT" value="$HttpPort" />
      <option name="JNDI_PORT" value="$JndiPort" />
    </server-settings>
    <predefined_log_file enabled="true" id="Tomcat" />
    <predefined_log_file enabled="true" id="Tomcat Catalina" />
    <method v="2">
      <option name="Make" enabled="true" />
      <option name="BuildArtifacts" enabled="true">
        <artifact name="$ProjectName" />
      </option>
    </method>
  </configuration>
</component>
"@
}

function Build-ArtifactsWorkspaceXml([string]$ProjectName) {
@"
<component name="ArtifactsWorkspaceSettings">
  <artifacts-to-build>
    <artifact name="$ProjectName" />
  </artifacts-to-build>
</component>
"@
}

function Upsert-WorkspaceComponents(
    [string]$WorkspacePath,
    [string]$RunManagerXml,
    [string]$ArtifactsWorkspaceXml
) {
    if (Test-Path $WorkspacePath) {
        [xml]$doc = Get-Content $WorkspacePath
        if (-not $doc.project) {
            [xml]$doc = "<?xml version='1.0' encoding='UTF-8'?><project version='4'></project>"
        }
    } else {
        [xml]$doc = "<?xml version='1.0' encoding='UTF-8'?><project version='4'></project>"
    }

    $components = @($doc.SelectNodes('/project/component'))
    $toRemove = @()
    foreach ($c in $components) {
        if ($c.name -eq 'RunManager' -or $c.name -eq 'ArtifactsWorkspaceSettings') {
            $toRemove += $c
        }
    }
    foreach ($r in $toRemove) { [void]$doc.project.RemoveChild($r) }

    [xml]$runDoc = "<root>$RunManagerXml</root>"
    [xml]$artDoc = "<root>$ArtifactsWorkspaceXml</root>"
    [void]$doc.project.AppendChild($doc.ImportNode($artDoc.root.component, $true))
    [void]$doc.project.AppendChild($doc.ImportNode($runDoc.root.component, $true))

    $doc.Save($WorkspacePath)
}

function Ensure-TomcatServerPortsInWorkspace(
    [string]$WorkspacePath,
    [string]$TomcatName,
    [int]$HttpPort,
    [int]$JndiPort,
    [string]$BaseDirectoryName
) {
    if (!(Test-Path $WorkspacePath)) { return }

    [xml]$doc = Get-Content $WorkspacePath
    if (-not $doc.project) { return }

    $runManager = $doc.SelectSingleNode("/project/component[@name='RunManager']")
    if ($null -eq $runManager) { return }

    $config = $runManager.SelectSingleNode("configuration[@type='#com.intellij.j2ee.web.tomcat.TomcatRunConfigurationFactory' and @factoryName='Local' and @APPLICATION_SERVER_NAME='$TomcatName']")
    if ($null -eq $config) {
        $config = $runManager.SelectSingleNode("configuration[@name='$TomcatName' and @type='#com.intellij.j2ee.web.tomcat.TomcatRunConfigurationFactory' and @factoryName='Local']")
    }
    if ($null -eq $config) { return }

    $serverSettings = $config.SelectSingleNode("server-settings")
    if ($null -eq $serverSettings) {
        $serverSettings = $doc.CreateElement("server-settings")
        [void]$config.AppendChild($serverSettings)
    }

    $baseOption = $serverSettings.SelectSingleNode("option[@name='BASE_DIRECTORY_NAME']")
    if ($null -eq $baseOption) {
        $baseOption = $doc.CreateElement("option")
        [void]$baseOption.SetAttribute("name", "BASE_DIRECTORY_NAME")
        [void]$serverSettings.AppendChild($baseOption)
    }
    [void]$baseOption.SetAttribute("value", "$BaseDirectoryName")

    $httpOption = $serverSettings.SelectSingleNode("option[@name='HTTP_PORT']")
    if ($null -eq $httpOption) {
        $httpOption = $doc.CreateElement("option")
        [void]$httpOption.SetAttribute("name", "HTTP_PORT")
        [void]$serverSettings.AppendChild($httpOption)
    }
    [void]$httpOption.SetAttribute("value", "$HttpPort")

    $jndiOption = $serverSettings.SelectSingleNode("option[@name='JNDI_PORT']")
    if ($null -eq $jndiOption) {
        $jndiOption = $doc.CreateElement("option")
        [void]$jndiOption.SetAttribute("name", "JNDI_PORT")
        [void]$serverSettings.AppendChild($jndiOption)
    }
    [void]$jndiOption.SetAttribute("value", "$JndiPort")

    $legacyJmxOption = $serverSettings.SelectSingleNode("option[@name='JMX_PORT']")
    if ($null -ne $legacyJmxOption) {
        [void]$serverSettings.RemoveChild($legacyJmxOption)
    }

    $doc.Save($WorkspacePath)
}

 $projectPathList = Split-ListArg -Value $ProjectPath
 $projectNameList = Split-ListArg -Value $ProjectName

if ($projectPathList.Count -eq 0) {
    throw "ProjectPath is empty."
}

if ($projectNameList.Count -gt 0 -and $projectNameList.Count -ne $projectPathList.Count) {
    throw "ProjectName count must be 1 or equal to ProjectPath count."
}

$targets = @()
for ($i = 0; $i -lt $projectPathList.Count; $i++) {
    $name = $null
    if ($projectNameList.Count -eq 1) { $name = $projectNameList[0] }
    elseif ($projectNameList.Count -gt 1) { $name = $projectNameList[$i] }

    $resolvedPath = Resolve-ProjectPath -PathIn $projectPathList[$i] -ProjectName $name
    if (-not (Test-JavaWebProjectLayout -Path $resolvedPath)) {
        throw "Resolved path is not a Java Web project layout (missing src and WebRoot/web): $resolvedPath"
    }
    $moduleDefinition = Resolve-ModuleDefinition -ProjectPath $resolvedPath -ExplicitProjectName $name
    $targets += [pscustomobject]@{
        ProjectPath = $resolvedPath
        ProjectName = $moduleDefinition.ProjectName
        ModuleImlPath = $moduleDefinition.ModuleImlPath
        ModuleImlRelativePath = $moduleDefinition.ModuleImlRelativePath
    }
}

if (-not $SkipConfirm) {
    Write-Host ""
    Write-Host "================ IDEA Config Confirm ================"
    $idx = 1
    foreach ($t in $targets) {
        Write-Host "[$idx] ProjectPath : $($t.ProjectPath)"
        Write-Host "    ProjectName : $($t.ProjectName)"
        Write-Host "    ModuleIml   : $($t.ModuleImlRelativePath)"
        $idx++
    }
    Write-Host "TomcatName  : $TomcatName"
    Write-Host "====================================================="
    $confirm = Read-Host "Type Y to continue all projects"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        throw "Canceled by user."
    }
}

$allChanged = New-Object System.Collections.Generic.List[string]
foreach ($t in $targets) {
    $projectPath = $t.ProjectPath
    $projectName = $t.ProjectName
    $moduleImlPath = $t.ModuleImlPath
    $moduleImlRelativePath = $t.ModuleImlRelativePath

    $ideaDir = Join-Path $projectPath '.idea'
    $artifactsDir = Join-Path $ideaDir 'artifacts'
    $librariesDir = Join-Path $ideaDir 'libraries'
    Ensure-Dir $ideaDir
    Ensure-Dir $artifactsDir
    Ensure-Dir $librariesDir

    $webRootDirName = if (Test-Path (Join-Path $projectPath 'WebRoot')) { 'WebRoot' } elseif (Test-Path (Join-Path $projectPath 'web')) { 'web' } else { 'WebRoot' }
    $libraryRootDirName = if (Test-Path (Join-Path $projectPath 'WebRoot/WEB-INF/lib')) { 'WebRoot' } else { $webRootDirName }
    $webXmlPath = "file://`$MODULE_DIR`$/$webRootDirName/WEB-INF/web.xml"

    $localHttpPort = $HttpPort
    $localContextPath = $ContextPath
    if ([string]::IsNullOrWhiteSpace($localContextPath)) {
        if ($projectName -ieq 'jszgbm') {
            $localContextPath = ''
        } else {
            $localContextPath = "/$projectName"
        }
    }

    if ($UseWorkflowUrlRule) {
        $candidateWorkflowUrl = Find-WorkflowUrl -ProjectPath $projectPath -ProjectName $projectName -GivenWorkflowUrl $WorkflowUrl
        if ($candidateWorkflowUrl) {
            try {
                $uri = [uri]$candidateWorkflowUrl
                if ($projectName -ieq 'horizon') {
                    if ($uri.Port -gt 0) { $localHttpPort = $uri.Port }
                    if ($uri.AbsolutePath -and $uri.AbsolutePath -ne '/') {
                        $localContextPath = $uri.AbsolutePath.TrimEnd('/')
                    }
                }
            } catch {
                Write-Warning "workflow_url parse failed: $candidateWorkflowUrl"
            }
        }
    }

    $scanRoot = Split-Path -Path $projectPath -Parent
    $usedJndiPorts = Get-UsedJndiPorts -ScanRoot $scanRoot -CurrentProjectPath $projectPath
    $jndiPort = Resolve-JndiPort -BasePort $BaseJndiPort -UsedPorts $usedJndiPorts


    $miscXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectRootManager" version="2" languageLevel="JDK_1_8" project-jdk-name="$JdkName" project-jdk-type="JavaSDK">
    <output url="file://`$PROJECT_DIR`$/out" />
  </component>
</project>
"@

    $modulesXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectModuleManager">
    <modules>
      <module fileurl="file://`$PROJECT_DIR`$/$($moduleImlRelativePath.Replace('\', '/'))" filepath="`$PROJECT_DIR`$/$($moduleImlRelativePath.Replace('\', '/'))" />
    </modules>
  </component>
</project>
"@

    $encodingsXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="Encoding">
    <file url="file://`$PROJECT_DIR`$" charset="UTF-8" />
    <file url="PROJECT" charset="UTF-8" />
    <file url="`$PROJECT_DIR`$/src" charset="UTF-8" />
    <file url="`$PROJECT_DIR`$/resources" charset="UTF-8" />
    <file url="`$PROJECT_DIR`$/$webRootDirName" charset="UTF-8" />
    <property name="defaultCharsetForPropertiesFiles" value="UTF-8" />
  </component>
</project>
"@

    $libraryXml = @"
<component name="libraryTable">
  <library name="lib">
    <CLASSES>
      <root url="file://`$PROJECT_DIR`$/$libraryRootDirName/WEB-INF/lib" />
    </CLASSES>
    <JAVADOC />
    <SOURCES>
      <root url="file://`$PROJECT_DIR`$/$libraryRootDirName/WEB-INF/lib" />
    </SOURCES>
    <jarDirectory url="file://`$PROJECT_DIR`$/$libraryRootDirName/WEB-INF/lib" recursive="false" />
    <jarDirectory url="file://`$PROJECT_DIR`$/$libraryRootDirName/WEB-INF/lib" recursive="false" type="SOURCES" />
  </library>
</component>
"@

    $imlXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<module type="JAVA_MODULE" version="4">
  <component name="FacetManager">
    <facet type="web" name="Web">
      <configuration>
        <descriptors>
          <deploymentDescriptor name="web.xml" url="$webXmlPath" />
        </descriptors>
        <webroots>
          <root url="file://`$MODULE_DIR`$/$webRootDirName" relative="/" />
          <root url="file://`$MODULE_DIR`$/resources" relative="WEB-INF/classes" />
        </webroots>
      </configuration>
    </facet>
  </component>
  <component name="NewModuleRootManager" inherit-compiler-output="true">
    <exclude-output />
    <content url="file://`$MODULE_DIR`$">
      <sourceFolder url="file://`$MODULE_DIR`$/src" isTestSource="false" />
    </content>
    <orderEntry type="inheritedJdk" />
    <orderEntry type="sourceFolder" forTests="false" />
    <orderEntry type="library" name="lib" level="project" />
  </component>
</module>
"@

    $artifactXml = @"
<component name="ArtifactManager">
  <artifact type="exploded-war" name="$projectName">
    <output-path>`$PROJECT_DIR`$/out/artifacts/$projectName</output-path>
    <root id="root">
      <element id="javaee-facet-resources" facet="$projectName/web/Web" />
      <element id="directory" name="WEB-INF">
        <element id="directory" name="classes">
          <element id="module-output" name="$projectName" />
        </element>
        <element id="directory" name="lib">
          <element id="library" level="project" name="lib" />
        </element>
      </element>
    </root>
  </artifact>
</component>
"@

    Set-Content -Path (Join-Path $ideaDir 'misc.xml') -Value $miscXml -Encoding UTF8
    Set-Content -Path (Join-Path $ideaDir 'modules.xml') -Value $modulesXml -Encoding UTF8
    Set-Content -Path (Join-Path $ideaDir 'encodings.xml') -Value $encodingsXml -Encoding UTF8
    Set-Content -Path (Join-Path $librariesDir 'lib.xml') -Value $libraryXml -Encoding UTF8
    Set-Content -Path $moduleImlPath -Value $imlXml -Encoding UTF8
    Set-Content -Path (Join-Path $artifactsDir "$projectName.xml") -Value $artifactXml -Encoding UTF8

    $workspacePath = Join-Path $ideaDir 'workspace.xml'
    $baseDirectoryName = Get-BaseDirectoryName -WorkspacePath $workspacePath -TomcatName $TomcatName
    $runManagerXml = Build-RunManagerXml -TomcatName $TomcatName -ProjectName $projectName -ContextPath $localContextPath -HttpPort $localHttpPort -JndiPort $jndiPort -BaseDirectoryName $baseDirectoryName
    $artifactsWorkspaceXml = Build-ArtifactsWorkspaceXml -ProjectName $projectName
    Upsert-WorkspaceComponents -WorkspacePath $workspacePath -RunManagerXml $runManagerXml -ArtifactsWorkspaceXml $artifactsWorkspaceXml
    Ensure-TomcatServerPortsInWorkspace -WorkspacePath $workspacePath -TomcatName $TomcatName -HttpPort $localHttpPort -JndiPort $jndiPort -BaseDirectoryName $baseDirectoryName

    $changed = @(
        (Join-Path $ideaDir 'misc.xml'),
        (Join-Path $ideaDir 'modules.xml'),
        (Join-Path $ideaDir 'encodings.xml'),
        (Join-Path $librariesDir 'lib.xml'),
        $moduleImlPath,
        (Join-Path $artifactsDir "$projectName.xml"),
        $workspacePath
    )
    foreach ($c in $changed) { [void]$allChanged.Add($c) }

    Write-Host "Configured IntelliJ files for: $projectName"
    Write-Host "Project: $projectPath"
    Write-Host "Tomcat: $TomcatName"
    Write-Host "Port: $localHttpPort"
    Write-Host "JndiPort: $jndiPort"
    Write-Host "ContextPath: $localContextPath"
    Write-Host "Encoding: UTF-8"
}

Write-Host "ChangedFiles:"
$allChanged | Sort-Object -Unique | ForEach-Object { Write-Host " - $_" }


