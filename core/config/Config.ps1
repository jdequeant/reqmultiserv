Set-StrictMode -Version Latest

class AppConfig {
    [string] $MySqlExePath
    [int] $MaxParallelWorkers
    [System.Collections.Generic.List[Server]] $Servers

    AppConfig(
        [string]$mySqlExePath,
        [int]$maxParallelWorkers,
        [System.Collections.Generic.List[Server]]$servers
    ) {
        if ([string]::IsNullOrWhiteSpace($mySqlExePath)) { throw "mysql_exe_path is required" }
        if ($null -eq $servers) { throw "servers is required" }

        $this.MySqlExePath = $mySqlExePath
        $this.MaxParallelWorkers = $maxParallelWorkers
        $this.Servers = $servers
    }

    static [AppConfig] Load([string] $path) {
        if ([string]::IsNullOrWhiteSpace($path)) { throw "path is required" }
        if (-not (Test-Path -LiteralPath $path)) { throw "Configuration file not found: $path" }

        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json

        # --- MySQL exe path ---
        if ($null -eq $json -or -not $json.PSObject.Properties.Match('mysql_exe_path')) {
            throw "Missing field 'mysql_exe_path' in config"
        }

        $mysqlPath = [string]$json.globals.mysql_exe_path
        if ([string]::IsNullOrWhiteSpace($mysqlPath)) { throw "Invalid 'mysql_exe_path' (empty)" }
        if (-not (Test-Path -LiteralPath $mysqlPath)) { throw "mysql.exe not found at $mysqlPath" }

        # --- Max parallel workers
        $maxParallel = 8

        if ($json.PSObject.Properties.Match('globals') -and
            $json.globals.PSObject.Properties.Match('max_parallel_workers')) {

            $raw = $json.globals.max_parallel_workers
            $parsed = 0

            if (-not [int]::TryParse([string]$raw, [ref]$parsed)) {
                throw "Invalid 'globals.max_parallel_workers' (not an integer)"
            }

            if ($parsed -lt 1 -or $parsed -gt 20) {
                throw "Invalid 'globals.max_parallel_workers' (allowed range: 1-20)"
            }

            $maxParallel = $parsed
        }

        # --- Servers ---
        if ($null -eq $json -or $null -eq $json.servers -or $json.servers.Count -eq 0) {
            throw "No servers defined in configuration"
        }

        $names = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $serverList = [System.Collections.Generic.List[Server]]::new()

        for ($i = 0; $i -lt $json.servers.Count; $i++) {
            $s = $json.servers[$i]

            foreach ($key in "name","host","port","user","password","database","enabled_by_default") {
                if (-not $s.PSObject.Properties.Match($key)) {
                    throw "Missing field '$key' in server definition (index=$i)"
                }
            }

            $name = [string]$s.name
            if ([string]::IsNullOrWhiteSpace($name)) { throw "Invalid 'name' (empty) in server definition (index=$i)" }
            if (-not $names.Add($name)) { throw "Duplicate server name: $name" }

            $dbHost = [string]$s.host
            if ([string]::IsNullOrWhiteSpace($dbHost)) { throw "Invalid 'host' (empty) for server '$name'" }

            $port = 0
            if (-not [int]::TryParse([string]$s.port, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
                throw "Invalid 'port' for server '$name' (value='$($s.port)')"
            }

            $enabled = $false
            if ($s.enabled_by_default -is [bool]) {
                $enabled = [bool]$s.enabled_by_default
            } else {
                [void][bool]::TryParse([string]$s.enabled_by_default, [ref]$enabled)
            }

            $serverList.Add([Server]::new(
                $name,
                $dbHost,
                $port,
                [string]$s.user,
                [string]$s.password,
                [string]$s.database,
                $enabled
            )) | Out-Null
        }

        return [AppConfig]::new($mysqlPath, $maxParallel, $serverList)
    }
}

function Import-AppConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    [AppConfig]::Load($Path)
}
