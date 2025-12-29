Set-StrictMode -Version Latest

class MariaDbExecutor {
    [Logger] $Logger

    MariaDbExecutor([Logger]$logger) {
        $this.Logger = $logger
    }

    [void] ValidateSqlReadOnly([string]$query) {
        if ([string]::IsNullOrWhiteSpace($query)) {
            throw "SQL query is empty"
        }

        if ($query -match '(?i)\b(insert|update|delete|drop|alter|truncate|create|replace|rename|grant|revoke|call|execute|set|load|outfile|infile|shutdown|install|uninstall|purge|reset|flush)\b')
        {
            throw "Forbidden SQL keyword detected (read-only mode)"
        }
    }

    [void] PrepareExecution(
        [AppState] $state,
        [Server[]] $servers,
        [string] $query
    ) {
        if ($state.IsRunning) {
            throw "Execution already running"
        }

        $this.ValidateSqlReadOnly($query)

        $state.IsRunning = $true
        $state.KillRequested = $false

        $state.ActiveWorkers.Clear()
        $state.PendingWorkers.Clear()
        $state.WorkerJobs.Clear()

        foreach ($server in $servers) {
            $worker = [Worker]::new()
            $worker.Server = $server
            $worker.Query = $query

            $state.PendingWorkers.Enqueue($worker)
        }

        $this.Logger.Info(
            ("MariaDB execution prepared ({0} servers, max parallel = {1})" -f
                $servers.Count,
                $state.MaxConcurrent
            )
        )
    }
}
