Set-StrictMode -Version Latest

class MariaDbEngine {
    [Logger] $Logger
    [MariaDbService] $DbService
    [string] $MySqlExePath

    [int] $KillTimeoutSec = 6
    [int] $PollAliveEveryMs = 500
    [int] $ExecTimeoutSec = 0 # 0 => disabled (optional)

    MariaDbEngine([Logger]$logger, [MariaDbService]$dbService, [string]$mySqlExePath) {
        $this.Logger = $logger
        $this.DbService = $dbService
        $this.MySqlExePath = $mySqlExePath
    }

    # ===============================
    # MAIN LOOP
    # ===============================
    [void] Tick([AppState]$state) {
        $now = Get-Date

        $this.PumpQueue($state, $now)

        foreach ($w in $state.ActiveWorkers) {
            # Terminal states, do nothing
            if ($w.Status -in @('done','error','killed')) {
                continue
            }

            # Propagate global kill => worker kill request
            if ($state.KillRequested -and $w.Status -in @('pending','running')) {
                $w.KillRequested = $true
            }

            # Pending => killed (cancel before start)
            if ($w.Status -eq 'pending' -and $w.KillRequested) {
                $this.FinalizeKilled($w, $now, 'Cancelled before start')
                continue
            }

            # Pending => running (first tick)
            if ($w.Status -eq 'pending') {
                $w.Status = 'running'
                $w.SetStartedAt($now)
            }

            # Ensure job exists when running
            if ($w.Status -eq 'running') {
                $this.StartWorkerJob($state, $w, $now)
            }

            # If kill requested : running => killing
            if ($w.Status -eq 'running' -and $w.KillRequested) {
                $w.Status = 'killing'
                $w.SetKillStartedAt($now)
            }

            $job = $null
            if ($state.WorkerJobs.ContainsKey($w.WorkerId)) {
                $job = $state.WorkerJobs[$w.WorkerId]
            }

            switch ($w.Status) {
                'running' {
                    # (Optionnel) timeout d'exec côté moteur / @TODO Rendre paramétrable
                    if ($this.ExecTimeoutSec -gt 0 -and
                        ($now - $w.StartedAt).TotalSeconds -gt $this.ExecTimeoutSec
                    ) {
                        $w.KillRequested = $true
                        $w.Status = 'killing'
                        $w.SetKillStartedAt($now)
                    }

                    # Job finished => consume and finalize
                    if ($job -and $job.State -ne 'Running') {
                        $this.ConsumeJobAndFinalize($state, $w, $job, $now)
                    }

                    break
                }

                'killing' {
                    # Émission du kill une seule fois
                    if (-not $w.KillIssued) {
                        $w.KillIssued = $true
                        $w.SetKillStartedAt($now)
                        $this.DbService.KillQuery($w)
                    }

                    # Vérification IsQueryAlive pour pouvoir marquer killed
                    $alive = $this.PollAlive($w, $now)

                    if (-not $alive) {
                        # Query plus visible: on marque killed (et on stoppe le job si encore running)
                        if ($job -and $job.State -eq 'Running') {
                            $this.StopWorkerJob($state.WorkerJobs, $w)
                        }
                        $this.FinalizeKilled($w, $now, '')
                        break
                    }

                    # 4) Timeout kill: stop job + error
                    if ($w.KillStartedAt -and (($now - $w.KillStartedAt).TotalSeconds -gt $this.KillTimeoutSec)) {
                        $this.StopWorkerJob($state.WorkerJobs, $w)
                        $this.FinalizeError($w, $now, 'Kill timeout')
                        break
                    }

                    break
                }

                default { }
            }

            # Job manquant dans un état actif => erreur
            if ($w.Status -in @('running','killing') -and -not $state.WorkerJobs.ContainsKey($w.WorkerId)) {
                $this.FinalizeError($w, $now, 'Internal: job missing for worker')
            }
        }

        $this.PumpQueue($state, $now)

        # Fin globale
        $anyActive = $false
        foreach ($w2 in $state.ActiveWorkers) {
            if ($w2.Status -in @('pending','running','killing')) { $anyActive = $true; break }
        }

        $hasPending = ($state.PendingWorkers -and $state.PendingWorkers.Count -gt 0)

        if (-not $anyActive -and -not $hasPending) {
            $this.Logger.Info("MariaDB CLI execution finished")
            $state.IsRunning = $false
            $state.KillRequested = $false
        }
    }

    [void] StartWorkerJob([object]$state, [object]$w, [datetime] $now) {
        if ($w.JobStarted -or $state.WorkerJobs.ContainsKey($w.WorkerId)) {
            return
        }

        $w.JobStarted = $true
        $w.Status = 'running'
        $w.StartedAt = $now

        $payload = [pscustomobject]@{
            MySqlExePath = $this.MySqlExePath
            DbHost = $w.Server.DbHost
            Port = $w.Server.Port
            User = $w.Server.User
            Password = $w.Server.Password
            Database = $w.Server.Database
            Query = $w.Query
            Tag = $w.Tag
        }

        $runnerPath = Join-Path $PSScriptRoot 'MariaDbRunner.ps1'

        $job = Start-Job -ArgumentList $payload, $runnerPath -ScriptBlock {
            param($p, $runnerPath)

            try {
                . $runnerPath 
                $runner = [MariaDbRunner]::new([string]$p.MySqlExePath)

                $result = $runner.InvokeMySql(
                    @{
                        DbHost = $p.DbHost
                        Port = $p.Port
                        User = $p.User
                        Password = $p.Password
                        Database = $p.Database
                    },
                    "/* $($p.Tag) */$($p.Query)",
                    @("--comments")
                )

                return $result
            } catch {
                return [pscustomobject]@{
                    Status = "error"
                    ExitCode = 1
                    StdOut = ""
                    StdErr = $_.ToString()
                }
            }
            
        }

        $state.WorkerJobs[$w.WorkerId] = $job
        $this.Logger.info("mysql.exe started [$($w.Server.Name)]")
    }

    [void] StopWorkerJob([hashtable]$workerJobs, [Worker]$worker) {
        if ($null -eq $workerJobs -or $null -eq $worker) { return }

        $job = $null
        if ($workerJobs.ContainsKey($worker.WorkerId)) { $job = $workerJobs[$worker.WorkerId] }

        if ($job -and $job.State -eq "Running") {
            Stop-Job $job -ErrorAction SilentlyContinue
        }

        if ($job) {
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }

        if ($workerJobs.ContainsKey($worker.WorkerId)) {
            [void]$workerJobs.Remove($worker.WorkerId)
        }
    }

    hidden [int] CountInFlight([AppState]$state) {
        $n = 0
        foreach ($w in $state.ActiveWorkers) {
            if ($w.Status -in @('pending','running','killing')) { $n++ }
        }
        return $n
    }

    hidden [void] PumpQueue([AppState]$state, [datetime]$now) {
        if ($state.KillRequested) {
            if ($state.PendingWorkers) { $state.PendingWorkers.Clear() }
            return
        }

        $inFlight = $this.CountInFlight($state)

        while ($inFlight -lt $state.MaxConcurrent -and $state.PendingWorkers.Count -gt 0) {
            $w = $state.PendingWorkers.Dequeue()

            # sécurité: le worker doit partir en pending
            $w.Status = 'pending'
            $w.KillRequested = $false
            $w.JobStarted = $false
            $w.LastAlivePollAt = [datetime]::MinValue

            $state.ActiveWorkers.Add($w)
            $inFlight++
        }
    }

    hidden [bool] PollAlive([object]$w, [datetime]$now) {
        if ((($now - $w.LastAlivePollAt).TotalMilliseconds) -lt $this.PollAliveEveryMs) { return $true }
        $w.LastAlivePollAt = $now

        try { return [bool]$this.DbService.IsQueryAlive($w) } catch { return $false }
    }

    [void] ConsumeJobAndFinalize([object]$state, [object]$w, [object]$job, [datetime]$now) {
        if (-not $job) {
            $this.FinalizeError($w, $now, 'Internal: job missing for worker')
            return
        }

        $result = $null
        try {
            $result = Receive-Job $job -ErrorAction Stop
        } catch {
            $result = [pscustomobject]@{
                Status = 'error'
                ExitCode = 1
                StdOut = ''
                StdErr = $_.ToString()
            }
        }

        $this.StopWorkerJob($state.WorkerJobs, $w)

        $w.StdOut = if ($result -and $result.PSObject.Properties.Match('StdOut').Count -gt 0 -and $result.StdOut) { [string]$result.StdOut } else { '' }
        $status = if ($result -and $result.PSObject.Properties.Match('Status').Count -gt 0 -and $result.Status) { [string]$result.Status } else { 'error' }
        $stderr = if ($result -and $result.PSObject.Properties.Match('StdErr').Count -gt 0 -and $result.StdErr) { [string]$result.StdErr } else { '' }

        $msg = if ($stderr) { $stderr } else { '' }

        # Cas priorité : kill explicite
        if ($w.Status -eq 'killing' -or $w.KillRequested) {
            if ($status -in @('done', 'timeout')) {
                $this.FinalizeKilled($w, $now, $msg)
            }
            else {
                $this.FinalizeError($w, $now, $msg)
            }
            return
        }

        # Cas normal
        switch ($status) {
            'done' { $this.FinalizeDone($w, $now, $state) }
            'timeout' { $this.FinalizeKilled($w, $now, $msg) }
            default { $this.FinalizeError($w, $now, $msg) }
        }
    }

    hidden [void] LogWorkerFinished([Worker]$w, [string]$finalStatus) {
        $name = $w.Server.Name
        $st = $finalStatus
        $this.Logger.Info(("mysql.exe finished [{0}] status={1}" -f $name, $st))
    }

    [void] FinalizeKilled([object]$w, [datetime]$now, [string]$reason) {
        $w.Status = 'killed'
        $w.Message = $reason
        $w.SetEndedAt($now)
        $this.LogWorkerFinished($w, 'killed')
    }

    [void] FinalizeDone([object]$w, [datetime]$now, [AppState]$state) {
        $rowCount = 0

        if ($w.StdOut) {
            $lines = @($w.StdOut -split "`r?\n" | Where-Object { $_.Trim() -ne "" })
            if ($lines.Count -gt 1) {
                $rowCount = $lines.Count - 1
            }
        }

        $w.RowCount = $rowCount
        $w.Status   = 'done'
        $w.Message = "$rowCount row(s) returned"
        $w.SetEndedAt($now)
        $this.LogWorkerFinished($w, 'done')

        if ($w.StdOut) {
            [MysqlResultParser]::Parse(
                $w.StdOut,
                $w.Server.Name,
                $state.OnResultSchema,
                $state.OnResultRow
            )
        }
    }

    [void] FinalizeError([object]$w, [datetime]$now, [string]$msg) {
        $w.Status = 'error'
        $w.Message = $msg
        $w.SetEndedAt($now)
        $this.LogWorkerFinished($w, 'error')
    }
}
