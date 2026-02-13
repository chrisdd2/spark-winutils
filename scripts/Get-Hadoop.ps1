function Get-Hadoop {
    <#
        .SYNOPSIS
            Fetches a specific hadoop repository version
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, HelpMessage="Hadoop version")]
        [string]$Version,

        [Parameter(Mandatory=$false, HelpMessage="Destination dir")]
        [string]$Destination=".\hadoop",

        [Parameter(Mandatory=$false, HelpMessage="Hadoop git repository URL")]
        [string]$Repository="https://github.com/apache/hadoop.git",

        [Parameter(HelpMessage="Force destination (may delete existing dirs/files)")]
        [switch]$Force
    )

    function Test-Repository($Path, $RemoteUrl=$null) {
        $result = $false
        Push-Location $Path
        $testRemoteUrl = git config --get remote.origin.url
        if ($null -eq $RemoteUrl) {
            $result = (-not ([string]::IsNullOrEmpty($testRemoteUrl)))
        } else {
            $result = ($testRemoteUrl -eq $RemoteUrl)
        }
        Pop-Location
        return $result
    }

   if (Test-Path -Path $Destination -PathType Leaf) {
        if ($Force) {
            Remove-Item -Path $Destination -Force
        } else {
            Write-Error "Desitnation '$Destination' already exists and is a file. Use -Force in order to delete existing files." -ErrorAction Stop 
        }
    } elseif ((Test-Path -Path $Destination -PathType Container) -and ((Get-ChildItem -Path $Destination | Measure-Object).Count -gt 0) -and (-not (Test-Repository -Path $Destination -RemoteUrl $Repository))) {
        if ($Force) {
            Remove-Item -Path $Destination -Recurse -Force
        } else {
            Write-Error "Desitnation '$Destination' already exists and is not empty. Use -Force in order to delete existing directories." -ErrorAction Stop 
        }
    }
    New-Item -Path $Destination -ItemType Directory -Force | Out-Null

    if (Test-Repository -Path $Destination -RemoteUrl $Repository) {
        # Switch branch
        Push-Location $Destination
        git reset --hard
        git clean -fdx
        git checkout "branch-$Version"
        Pop-Location
    } else {
        # Clone branch
        git clone --branch "branch-$Version" "$Repository" "$Destination"
    }

}
