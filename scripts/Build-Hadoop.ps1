. "$PSScriptRoot\Get-Hadoop.ps1"
. "$PSScriptRoot\Export-Headers.ps1"

function Build-Hadoop {
    <#
        .SYNOPSIS
            Builds winutils for a specific hadoop version
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, HelpMessage="Hadoop version")]
        [string]$Version,

        [Parameter(Mandatory=$false, HelpMessage="Destination dir")]
        [string]$Destination=".\hadoop",

        [Parameter(Mandatory=$false, HelpMessage="Hadoop git repository URL")]
        [string]$Repository="https://github.com/apache/hadoop.git",

        [Parameter(Mandatory=$false, HelpMessage="Hadoop commons repository sub path")]
        [string]$WinutilsRepositoryBasePath="hadoop-common-project\hadoop-common",

        [Parameter(Mandatory=$false, HelpMessage="Src")]
        [string]$HeaderSrc="src\main\java",

        [Parameter(Mandatory=$false, HelpMessage="Destination dir")]
        [string]$HeaderDestination="target\native\javah",

        [Parameter(HelpMessage="Skip downloading Hadoop source (assume it already exists)")]
        [switch]$SkipGetHadoop,

        [Parameter(HelpMessage="Force destination (may delete existing dirs/files)")]
        [switch]$Force
    )

    function Open-Explorer($Path=".") {
        Push-Location $Path
        Invoke-Item .
        Pop-Location
    }

    $BinDir = "$Destination\$WinutilsRepositoryBasePath\target\bin"
    $WinutilsSlnPath = "$Destination\$WinutilsRepositoryBasePath\src\main\winutils\winutils.sln"
    $WinutilsX64Path = "$Destination\$WinutilsRepositoryBasePath\src\main\winutils\x64\Release"
    $WinutilsX32Path = "$Destination\$WinutilsRepositoryBasePath\src\main\winutils\x32\Release"
    $NativeSlnPath = "$Destination\$WinutilsRepositoryBasePath\src\main\native\native.sln"

    if (-not $SkipGetHadoop) {
        Invoke-Expression "Get-Hadoop -Version '$Version' -Destination '$Destination' -Repository '$Repository' -Force:$(if($Force){'$true'} else {'$false'})"
    }
    Export-Headers -Project (Join-Path $Destination $WinutilsRepositoryBasePath) -Src $HeaderSrc -Destination $HeaderDestination

    # Find MSBuild
    $msbuild = (vswhere -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | Select-Object -First 1)
    if (-not $msbuild) {
        throw "MSBuild not found"
    }
    Write-Host "Using MSBuild: $msbuild"

    # Build winutils
    Write-Host "Building winutils..."
    $WinutilsRoot = Join-Path $Destination "$WinutilsRepositoryBasePath\src\main\winutils"

    # Patch source files to avoid GetFileInformationByName conflict
    Get-ChildItem -Recurse -Include *.c,*.h -Path $WinutilsRoot | ForEach-Object {
        $content = Get-Content $_ -Raw
        if ($content -match '\bGetFileInformationByName\b') {
            $content = $content -replace '\bGetFileInformationByName\b', 'HadoopGetFileInformationByName'
            Set-Content $_ -Value $content -Encoding UTF8
        }
    }

    & $msbuild $WinutilsSlnPath /nologo /p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v143 /p:ForcePlatformToolset=true /p:WindowsTargetPlatformVersion=10.0 /p:OutDir=bin\ /p:IntermediateOutputPath=\Winutils\ /p:WsceConfigDir="../etc/config" /p:WsceConfigFile="wsce-site.xml"
    if ($LASTEXITCODE -ne 0) {
        throw "Winutils build failed"
    }

    # Try to copy binaries to bin dir (needed for hadoop natives)
    New-Item -Path $BinDir -ItemType Directory -Force | Out-Null
    if (Test-Path -Path $WinutilsX64Path -PathType Container) {
        Copy-Item "$WinutilsX64Path\libwinutils.lib" -Destination "$BinDir\"
        Copy-Item "$WinutilsX64Path\libwinutils.pdb" -Destination "$BinDir\"
        Copy-Item "$WinutilsX64Path\winutils.exe" -Destination "$BinDir\"
        Copy-Item "$WinutilsX64Path\winutils.pdb" -Destination "$BinDir\"
    } elseif (Test-Path -Path $WinutilsX32Path -PathType Container) {
        Copy-Item "$WinutilsX32Path\libwinutils.lib" -Destination "$BinDir\"
        Copy-Item "$WinutilsX32Path\libwinutils.pdb" -Destination "$BinDir\"
        Copy-Item "$WinutilsX32Path\winutils.exe" -Destination "$BinDir\"
        Copy-Item "$WinutilsX32Path\winutils.pdb" -Destination "$BinDir\"
    }

    # Build native DLLs
    Write-Host "Building native DLLs..."
    $NativeRoot = Join-Path $Destination "$WinutilsRepositoryBasePath\src\main\native"

    # Patch source files to avoid GetFileInformationByName conflict
    Get-ChildItem -Recurse -Include *.c,*.h -Path $NativeRoot | ForEach-Object {
        $content = Get-Content $_ -Raw
        if ($content -match '\bGetFileInformationByName\b') {
            $content = $content -replace '\bGetFileInformationByName\b', 'HadoopGetFileInformationByName'
            Set-Content $_ -Value $content -Encoding UTF8
        }
    }

    & $msbuild $NativeSlnPath /nologo /p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v143 /p:ForcePlatformToolset=true /p:WindowsTargetPlatformVersion=10.0 /p:OutDir=bin\ /p:IntermediateOutputPath=\native\
    if ($LASTEXITCODE -ne 0) {
        throw "Native build failed"
    }

    Open-Explorer -Path $BinDir

}
