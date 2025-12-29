Set-StrictMode -Version Latest

if (Test-Path Variable:\script:BOOTSTRAP_LOADED) { return }
$script:BOOTSTRAP_LOADED = $true

function Resolve-CoreFile {
    param([Parameter(Mandatory)][string]$RelativePath)

    $full = Join-Path $PSScriptRoot $RelativePath
    if (-not (Test-Path -LiteralPath $full)) {
        throw "Missing core file: $full"
    }
    return $full
}

$files = @(
    'entities/Server.ps1'
    'entities/Worker.ps1'

    'parsing/MysqlResultSchema.ps1'
    'parsing/MysqlResultParser.ps1'

    'logging/Logger.ps1'
    'config/Config.ps1'
    'state/AppState.ps1'

    'services/MariaDbExecutor.ps1'
    'services/MariaDbRunner.ps1'
    'services/MariaDbInspector.ps1'
    'services/MariaDbKiller.ps1'
    'services/MariaDbService.ps1'
    'services/MariaDbEngine.ps1'

    'utils/Fs.ps1'
    'CompositionRoot.ps1'
) | ForEach-Object { Resolve-CoreFile $_ }

foreach ($f in $files) { . $f }

Export-ModuleMember -Function @(
    'Initialize-Directory',
    'Import-AppConfig',
    'New-App'
)
