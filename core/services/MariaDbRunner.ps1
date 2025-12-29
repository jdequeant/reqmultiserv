Set-StrictMode -Version Latest

class MariaDbRunner {
    [string] $MySqlExePath

    MariaDbRunner([string]$mysqlPath) {
        if ([string]::IsNullOrWhiteSpace($mysqlPath)) { throw "mysqlPath is required" }
        if (-not (Test-Path -LiteralPath $mysqlPath)) {
            throw ("mysql.exe not found at {0}" -f $mysqlPath)
        }
        $this.MySqlExePath = $mysqlPath
    }

    [pscustomobject] InvokeMySql([object]$Server, [string] $Query) {
        return $this.InvokeMySql($Server, $Query, @())
    }

    [pscustomobject] InvokeMySql(
        [object] $Server,
        [string] $Query,
        [string[]] $Options # Options mysql.exe
    ) {
        $DefaultOptions = @(
            "--ssl-mode=DISABLED",
            "--connect-timeout=3", # TCP + Handshake
            "--quick", # no client buffering
            "--batch" # non-interactive, script-friendly
        )

        $env:MYSQL_PWD = $Server.Password

        try {
            $arguments = @("-h", $Server.DbHost, "-P", $Server.Port, "-u", $Server.User, "-D", $Server.Database) + $DefaultOptions
            if ($Options) { $arguments += $Options }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $this.MySqlExePath
            $psi.RedirectStandardInput  = $true
            $psi.Arguments = ($arguments -join ' ')
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true

            $proc = [System.Diagnostics.Process]::new()
            $proc.StartInfo = $psi
            
            if (-not $proc.Start()) {
                return [pscustomobject]@{
                    Status = "error"
                    ExitCode = 1
                    StdOut = ""
                    StdErr = "Failed to start mysql.exe"
                }
            }
            $proc.StandardInput.WriteLine($Query)
            $proc.StandardInput.Close()

            $stdout = $proc.StandardOutput.ReadToEnd()
            $stderr = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit()

            return [pscustomobject]@{
                Status = $(if ($proc.ExitCode -eq 0) { "done" } else { "error" })
                ExitCode = $proc.ExitCode
                StdOut = $stdout
                StdErr = $stderr
            }
        }
        finally {
            Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
        }
    }
}
