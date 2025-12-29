Set-StrictMode -Version Latest

class MariaDbInspector {
    [object] $MariaDbRunner

    MariaDbInspector([object]$mariaDbRunner) {
        $this.MariaDbRunner = $mariaDbRunner
    }

    [bool] IsQueryAlive([object]$worker) {
        try {
            $res = $this.MariaDbRunner.InvokeMySql(
                $worker.Server,
                "SELECT 1 FROM information_schema.PROCESSLIST WHERE INFO LIKE '%$($worker.Tag)%' AND ID <> CONNECTION_ID() LIMIT 1",
                @("--skip-column-names")
            )
            return -not [string]::IsNullOrWhiteSpace($res.StdOut)
        }
        catch {
            return $false
        }
    }
}
