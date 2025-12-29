Set-StrictMode -Version Latest
$script:ErrorActionPreference = "Stop"

$paths = [pscustomobject]@{
    Core = Join-Path $PsScriptRoot "core"
    UI = Join-Path $PsScriptRoot "ui"
    Config = Join-Path $PsScriptRoot "config.json"
    Logs = Join-Path $PsScriptRoot "logs"
    Data = Join-Path $PsScriptRoot "data"
}

Import-Module (Join-Path $paths.Core "bootstrap.psm1") -Force

function Start-ReqMultiServ {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Paths
    )

    $app = $null

    try {
        Write-Host "LOADING - $(Get-Date)" -ForegroundColor Yellow

        Initialize-Directory -Path $paths.Logs
        Initialize-Directory -Path $paths.Data

        $config = Import-AppConfig -Path $Paths.Config
        $app = New-App -Paths $Paths -Config $config

        $app.Logger.Info("ReqMultiServ starting")

        # --- Lancement UI ---
        & (Join-Path $Paths.UI "MainWindow.ps1") -App $app

        $app.Logger.Info("ReqMultiServ exited cleanly")
    }
    catch {
        try {
            if ($null -ne $app -and $null -ne $app.Logger) {
                $app.Logger.Error($_.ToString())
            }
        } catch { Write-Error $_ }
        throw
    }
}

Start-ReqMultiServ -Paths $paths
