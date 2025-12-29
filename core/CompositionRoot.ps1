Set-StrictMode -Version Latest

function New-App {
    param(
        [Parameter(Mandatory)] $Paths,
        [Parameter(Mandatory)] $Config
    )

    $logger = [Logger]::new($Paths.Logs)

    $state = [AppState]::new($Config.MaxParallelWorkers)

    $runner = [MariaDbRunner]::new($Config.MySqlExePath)
    $executor = [MariaDbExecutor]::new($logger)
    $inspector = [MariaDbInspector]::new($runner)
    $killer = [MariaDbKiller]::new($runner)

    $service = [MariaDbService]::new($executor, $inspector, $killer)
    $engine = [MariaDbEngine]::new($logger, $service, $Config.MySqlExePath)

    return [pscustomobject]@{
        Logger = $logger
        State = $state
        Engine = $engine
        Service = $service
        Paths = $Paths
        Config = $Config
    }
}