Set-StrictMode -Version Latest

class MariaDbKiller {
    [MariaDbRunner] $Runner

    MariaDbKiller([MariaDbRunner]$runner) {
        $this.Runner = $runner
    }

    [void] KillQuery([Worker]$worker) {
        if ($null -eq $worker -or $null -eq $worker.Server) { return }

        $needle = ("/* {0} */" -f $worker.Tag) -replace "'","''"

        $sql = "SELECT ID FROM information_schema.PROCESSLIST WHERE INFO IS NOT NULL AND LOCATE('$needle', INFO) > 0 AND ID <> CONNECTION_ID() AND COMMAND = 'Query'"

        $res = $this.Runner.InvokeMySql($worker.Server, $sql, @("--skip-column-names"))

        if ($res.Status -ne 'done' -or [string]::IsNullOrWhiteSpace($res.StdOut)) {
            return
        }

        $lines = [System.Text.RegularExpressions.Regex]::Split($res.StdOut.Trim(), "\r\n|\n|\r") |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        foreach ($line in $lines) {
            $id = 0
            if ([int]::TryParse($line.Trim(), [ref]$id)) {
                [void]$this.Runner.InvokeMySql($worker.Server, ("KILL {0}" -f $id))
            }
        }
    }
}
