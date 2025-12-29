Set-StrictMode -Version Latest

class Logger {
    [string] $LogDir
    [string] $Prefix = "ReqMultiServ"
    hidden [object] $LockObj

    Logger([string] $logDir) {
        if ([string]::IsNullOrWhiteSpace($logDir)) { throw "logDir is required" }

        $this.LogDir  = $logDir
        $this.LockObj = New-Object object
    }

    hidden [string] GetLogFilePath() {
        $date = (Get-Date).ToString("yyyy-MM-dd")
        return (Join-Path $this.LogDir ("{0}-{1}.log" -f $this.Prefix, $date))
    }

    [void] Write([string] $level, [string] $message) {
        if ([string]::IsNullOrWhiteSpace($level)) { return }
        if ($null -eq $message) { $message = "" }

        $path = $this.GetLogFilePath()
        $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $level.ToUpperInvariant(), $message

        try {
            [System.Threading.Monitor]::Enter($this.LockObj)
            Add-Content -LiteralPath $path -Value $line -Encoding UTF8
        } catch {
            return
        } finally {
            if ([System.Threading.Monitor]::IsEntered($this.LockObj)) {
                [System.Threading.Monitor]::Exit($this.LockObj)
            }
        }
    }

    [void] Debug([string] $m) { $this.Write("DEBUG", $m) }
    [void] Info ([string] $m) { $this.Write("INFO",  $m) }
    [void] Warn ([string] $m) { $this.Write("WARN",  $m) }
    [void] Error([string] $m) { $this.Write("ERROR", $m) }
}
