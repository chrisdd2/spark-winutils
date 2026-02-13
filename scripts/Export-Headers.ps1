function Export-Headers {
    <#
        .SYNOPSIS
            Generates and saves the JNI header files, needed to compile winutils
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, HelpMessage="Project dir")]
        [ValidateScript({Test-Path -Path $_ -PathType Container})]
        [string]$Project=(Get-Location).Path,

        [Parameter(Mandatory=$false, HelpMessage="Src")]
        [string]$Src="src\main\java",

        [Parameter(Mandatory=$false, HelpMessage="Destination dir")]
        [string]$Destination="target\native\javah"
    )
        
    function New-TemporaryDirectory {
        $parent = [System.IO.Path]::GetTempPath()
        [string] $name = [System.Guid]::NewGuid()
        return New-Item -ItemType Directory -Path (Join-Path $parent $name)
    }

    function Resolve-Path-Relative($BasePath, $ResolvePath) {
        $resolvedPath = $ResolvePath
        if (-not [System.IO.Path]::IsPathRooted("$ResolvePath")) {
            $resolvedPath = Join-Path $BasePath $ResolvePath
        }
        $resolvedItem = (Get-Item $resolvedPath -ErrorAction SilentlyContinue).FullName
        
        if ($null -ne $resolvedItem) {
            return $resolvedItem
        } else {
            return $resolvedPath
        }
    }

    function Get-MavenDependency($Group, $Artifact, $Version, $Destination) {
        $MvnTempDir = New-TemporaryDirectory
        Push-Location -Path "$MvnTempDir"
@"
        <project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
            <modelVersion>4.0.0</modelVersion>
            <groupId>tmp</groupId><artifactId>tmp</artifactId><version>0</version>
            <dependencies>
                <dependency>
                    <groupId>$Group</groupId>
                    <artifactId>$Artifact</artifactId>
                    <version>$Version</version>
                </dependency>
            </dependencies>
        </project>   
"@      | Out-File ".\pom.xml"
        mvn dependency:copy-dependencies -q
        Get-ChildItem -Path ".\target\dependency" -Recurse | Copy-Item -Destination "$Destination"
        Pop-Location
        Remove-Item -Path "$MvnTempDir" -Recurse -Force
    }


    $Src = Get-Item -Path (Resolve-Path-Relative $Project $Src)
    $Destination = New-Item -Path (Resolve-Path-Relative $Project $Destination) -ItemType Directory -Force


    Write-Host "Generating JNI headers for '$Project' and placing them in '$Destination'"
    Push-Location -Path "$Project"

    # Create work dir
    $WorkDir = New-TemporaryDirectory
    $DependencyDir = New-Item -Path (Join-Path $WorkDir 'deps') -ItemType Directory
    $ClassDir = New-Item -Path (Join-Path $WorkDir 'cls') -ItemType Directory
    $HeaderDir = New-Item -Path (Join-Path $WorkDir 'headers') -ItemType Directory
    Write-Host "Use workdir '$WorkDir'"

    # Get project dependency
    $DependencyGroup = mvn help:evaluate -Dexpression="project.groupId" -q -DforceStdout
    $DependencyArtifact = mvn help:evaluate -Dexpression="project.artifactId" -q -DforceStdout
    $DependencyVersion = mvn help:evaluate -Dexpression="project.version" -q -DforceStdout
    $DependencyCoordinate = "${DependencyGroup}:${DependencyArtifact}:${DependencyVersion}"
    Write-Host "Fetch project dependency '$DependencyCoordinate'"
    Get-MavenDependency -Group $DependencyGroup -Artifact $DependencyArtifact -Version $DependencyVersion -Destination $DependencyDir

    # Find possible JNI java files and generate headers
    $JniFiles = Get-ChildItem -Path $Src -Recurse | Where-Object {$_.Name -like "*.java"} | Where-Object {$_ | Get-Content -Raw | Select-String -Pattern "(?sm)native .*;" -CaseSensitive}
    foreach ($JniFile in $JniFiles) {
        Write-Host "Generate headers for '$JniFile'"
        javac -cp "$DependencyDir\*" -h "$HeaderDir" -d "$ClassDir" "$JniFile"
    }
    Get-ChildItem -Path $HeaderDir | Where-Object {$_.Name -like "*.h"} | Copy-Item -Destination $Destination

    Remove-Item -Path "$WorkDir" -Recurse -Force
    Pop-Location
}
