Set-StrictMode -Version Latest

class MariaDbService {
    [MariaDbKiller] $Killer
    [MariaDbExecutor] $Executor
    [MariaDbInspector] $Inspector

    MariaDbService(
        [MariaDbExecutor] $executor,
        [MariaDbInspector] $inspector,
        [MariaDbKiller] $killer
    ) {
        $this.Executor = $executor
        $this.Inspector = $inspector
        $this.Killer = $killer
    }

    [bool] IsQueryAlive([Worker]$Worker) {
        return $this.Inspector.IsQueryAlive($Worker)
    }

    [void] KillQuery([Worker]$Worker) {
        $this.Killer.KillQuery($Worker)
    }

    [void] PrepareExecution(
        [AppState]$AppState,
        [Server[]]$Servers,
        [string]$Query
    ) {
        $this.Executor.PrepareExecution($AppState, $Servers, $Query)
    }
}
