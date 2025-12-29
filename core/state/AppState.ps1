Set-StrictMode -Version Latest

class AppState {
    [bool] $IsRunning
    [bool] $KillRequested

    [int] $MaxConcurrent
    [System.Collections.ObjectModel.ObservableCollection[Worker]] $ActiveWorkers
    [System.Collections.Generic.Queue[Worker]] $PendingWorkers
    [hashtable] $WorkerJobs

    [int] $SelectedMaxRowsPerServer = 0

    [System.Action[MysqlResultSchema]] $OnResultSchema
    [System.Action[psobject]] $OnResultRow

    [bool] $ExportCsvRequested = $false
    [bool] $CsvHeaderWritten = $false
    [System.IO.StreamWriter] $ExportWriter = $null

    AppState(
        [int]$maxConcurrent
    ) {
        $this.IsRunning = $false
        $this.KillRequested = $false

        $this.MaxConcurrent = $maxConcurrent
        $this.ActiveWorkers = [System.Collections.ObjectModel.ObservableCollection[Worker]]::new()
        $this.PendingWorkers = [System.Collections.Generic.Queue[Worker]]::new()
        $this.WorkerJobs = @{}

        $this.OnResultSchema = $null
        $this.OnResultRow = $null
    }
}
