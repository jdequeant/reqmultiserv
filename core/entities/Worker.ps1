class Worker {
    [string] $WorkerId
    [Server] $Server
    [string] $Status
    [datetime] $StartedAt
    [datetime] $EndedAt
    [double] $DurationMs
    [double] $DurationSec
    [datetime] $LastAlivePollAt

    [string] $StdOut
    [string] $Message

    [bool] $JobStarted

    [bool] $KillRequested
    [bool] $KillIssued
    [datetime] $KillStartedAt

    [string] $Query
    [string] $Tag

    [int] $RowCount = 0

    Worker() {
        $this.WorkerId = [guid]::NewGuid().ToString()
        $this.Status = "pending"
        $this.Tag = "req-$([guid]::NewGuid().ToString('N'))"
    }

    [void] calcDuration() {
        if ($this.StartedAt -ne [datetime]::MinValue -and $this.EndedAt -ne [datetime]::MinValue) { 
            $this.DurationMs = ($this.EndedAt - $this.StartedAt).TotalMilliseconds
            $this.DurationSec = $this.DurationMs / 1000
        } else {
            $this.DurationMs = 0.0
            $this.DurationSec = 0.0
        }
    }

    [void] SetEndedAt([datetime]$v) {
        $this.EndedAt = $v
        $this.calcDuration()
    }

    [void] SetStartedAt([datetime]$v) {
        # Don't erase if already set
        if (-not ($this.StartedAt -is [datetime] -and $this.StartedAt -gt [datetime]::MinValue)) {
            $this.StartedAt = $v
        }
    }

    [void] SetKillStartedAt([datetime]$v) {
        # Don't erase if already set
        if (-not ($this.KillStartedAt -is [datetime] -and $this.KillStartedAt -gt [datetime]::MinValue)) {
            $this.KillStartedAt = $v
        }
    }
}