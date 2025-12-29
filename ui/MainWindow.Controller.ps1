Set-StrictMode -Version Latest

class MainWindowController {
    [object] $App
    [System.Windows.Window] $Window

    # Controls
    [System.Windows.Controls.Button] $RunButton
    [System.Windows.Controls.Button] $KillButton
    [System.Windows.Controls.Button] $ExportButton
    [System.Windows.Controls.TextBox] $SqlTextBox
    [System.Windows.Controls.ComboBox] $LimitComboBox
    [System.Windows.Controls.TextBox] $FilterBox
    [System.Windows.Controls.DataGrid] $ServersGrid
    [System.Windows.Controls.DataGrid] $ExecutionGrid
    [System.Windows.Controls.DataGrid] $ResultsGrid
    [System.Windows.Controls.TextBlock] $StatusText
    [System.Windows.Controls.TextBlock] $TimerStatusText
    [System.Windows.Controls.MenuItem] $KillWorkerMenuItem
    [System.Windows.Controls.CheckBox] $SelectAllCheckBox

    # Collections
    [System.Collections.ObjectModel.ObservableCollection[object]] $ServersCollection
    [System.Collections.ObjectModel.ObservableCollection[object]] $ExecutionCollection
    [System.Collections.ObjectModel.ObservableCollection[object]] $ResultsCollection
    [System.Windows.Data.CollectionViewSource] $ResultsCvs
    [string] $ResultsFilterText = ""

    # Timer
    [System.Windows.Threading.DispatcherTimer] $Timer

    # Close
    [System.Windows.Threading.DispatcherTimer] $CloseTimer
    [bool] $CloseRequested = $false
    [bool] $ForceClose = $false

    # Running
    [Nullable[datetime]] $RunStartedAt = $null
    [string] $RunElapsedText = ""

    # Context menu
    [object] $ContextMenuWorker

    # Export CSV
    [bool] $ExportCsvRequested = $false

    MainWindowController([object]$app, [System.Windows.Window]$window) {
        if ($null -eq $app) { throw "App is required" }
        if ($null -eq $window) { throw "Window is required" }
        $this.App = $app
        $this.Window = $window
    }

    [void] Initialize() {
        $this.ResolveControls()
        $this.BindBehaviors()
        $this.BindData()
        $this.BindEvents()
        $this.StartTimer()

        $this.RefreshQueryLimitSuggestions()

        $this.RefreshToolbarFromState()
        $this.SetStatus("Ready")
    }

    hidden [void] ResolveControls() {
        $this.RunButton = $this.Window.FindName("RunButton")
        $this.KillButton = $this.Window.FindName("KillButton")
        $this.ExportButton = $this.Window.FindName("ExportButton")
        $this.SqlTextBox = $this.Window.FindName("SqlTextBox")
        $this.LimitComboBox = $this.Window.FindName("LimitComboBox")
        $this.FilterBox = $this.Window.FindName("FilterBox")
        $this.ServersGrid = $this.Window.FindName("ServersGrid")
        $this.ExecutionGrid = $this.Window.FindName("ExecutionGrid")
        $this.ResultsGrid = $this.Window.FindName("ResultsGrid")
        $this.StatusText = $this.Window.FindName("StatusText")
        $this.TimerStatusText = $this.Window.FindName("TimerStatusText")
        $this.KillWorkerMenuItem = $this.ExecutionGrid.ContextMenu.Items |
            Where-Object { $_ -is [System.Windows.Controls.MenuItem] -and $_.Header -eq 'Kill worker' }
        $this.SelectAllCheckBox = $this.Window.FindName("SelectAllCheckBox")

        if (-not $this.RunButton -or -not $this.KillButton -or -not $this.SqlTextBox -or -not $this.ServersGrid -or -not $this.ExecutionGrid -or -not $this.ResultsGrid -or -not $this.StatusText) {
            throw "MainWindow.xaml: one or more named controls not found (check x:Name)."
        }
    }

    hidden [void] BindBehaviors() {
        @($this.ServersGrid, $this.ExecutionGrid, $this.ResultsGrid) | Where-Object { $_ } | ForEach-Object {
            Enable-GridCopyHeaderRule -Grid $_
            Enable-GridSelectAllFocus -Grid $_
            Enable-GridAutoDeselectOnBlur -Grid $_
            Enable-EllipsisOnGridTextColumns -Grid $_
        }

        Enable-TrimmedTextTooltipsGlobal

        Enable-SqlTextBoxTabIndent -TextBox $this.SqlTextBox -IndentSize 4
        Enable-WindowCtrlEnterToRun -Window $this.Window -RunButton $this.RunButton
        Enable-TextBoxDebouncedAutoSave `
            -TextBox $this.SqlTextBox `
            -Path (Join-Path $this.App.Paths.Data "last_query.sql") `
            -DelaySeconds 3

        if ([string]::IsNullOrWhiteSpace($this.SqlTextBox.Text)) {
            $this.SqlTextBox.Text = "SELECT NOW();"
        }
    }

    hidden [void] BindData() {
        # Servers
        $this.ServersCollection = New-Object System.Collections.ObjectModel.ObservableCollection[object]

        foreach ($s in $this.App.Config.Servers) {
            $this.ServersCollection.Add($s) | Out-Null
        }

        $this.ServersGrid.ItemsSource = $this.ServersCollection

        Register-ObjectEvent `
            -InputObject $this.ServersCollection `
            -EventName CollectionChanged `
            -Action { $this.UpdateSelectAllState() } `
            | Out-Null

        # Execution
        $this.ExecutionCollection = New-Object System.Collections.ObjectModel.ObservableCollection[object]
        $this.ExecutionGrid.ItemsSource = $this.ExecutionCollection

        # Results
        $this.ResultsGrid.AutoGenerateColumns = $false
        $this.ResultsCollection = New-Object System.Collections.ObjectModel.ObservableCollection[object]
        $this.ResultsCvs = New-Object System.Windows.Data.CollectionViewSource
        $this.ResultsCvs.Source = $this.ResultsCollection
        $this.ResultsGrid.ItemsSource = $this.ResultsCvs.View

        $controller = $this
        $filterHandler = [System.Windows.Data.FilterEventHandler]{
            param($sender, $e)

            $item = $e.Item
            $t = $controller.ResultsFilterText

            if ([string]::IsNullOrWhiteSpace($t)) { $e.Accepted = $true; return }

            foreach ($p in $item.PSObject.Properties) {
                $v = $p.Value
                if ($null -ne $v -and $v.ToString().IndexOf($t, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $e.Accepted = $true
                    return
                }
            }
            $e.Accepted = $false
        }.GetNewClosure()

        $this.ResultsCvs.add_Filter($filterHandler)
    }

    hidden [void] BindEvents() {
        $self = $this

        $this.FilterBox.Add_TextChanged({
            $self.ResultsFilterText = $self.FilterBox.Text
            $self.ResultsCvs.View.Refresh()
            $self.UpdateFilterStatus()
        }.GetNewClosure())

        $this.RunButton.Add_Click({
            $self.ExportCsvRequested = $false
            $self.OnRun()
        }.GetNewClosure())

        $this.ExportButton.Add_Click({
            $self.ExportCsvRequested = $true
            $self.OnRun()
        }.GetNewClosure())

        $this.KillButton.Add_Click({ $self.OnKill() }.GetNewClosure())

        $this.KillWorkerMenuItem.Add_Click({
            $w = $self.ContextMenuWorker
            if ($null -eq $w) { return }
            if ($w.Status -in @('killed','error','done')) { return }

            $w.KillRequested = $true

            $self.SyncExecutionGridFromState()
        }.GetNewClosure())

        $GetDataGridRowFromEvent = ${function:Get-DataGridRowFromEvent}

        $this.ExecutionGrid.Add_ContextMenuOpening({
            param($sender, $e)

            $row = & $GetDataGridRowFromEvent -Grid $sender -Event $e
            if ($null -eq $row) {
                $self.ContextMenuWorker = $null
                $self.KillWorkerMenuItem.IsEnabled = $false
                return
            }

            $w = [object]$row.Item
            $self.ContextMenuWorker = $w

            $self.KillWorkerMenuItem.IsEnabled = ($w.Status -in @('pending','running'))
        }.GetNewClosure())

        $this.ServersGrid.AddHandler(
            [System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent,
            [System.Windows.RoutedEventHandler]{
                $self.RefreshQueryLimitSuggestions()
                $self.UpdateSelectAllState()
            }.GetNewClosure(),
            $true
        )

        $this.ServersGrid.AddHandler(
            [System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent,
            [System.Windows.RoutedEventHandler]{
                $self.RefreshQueryLimitSuggestions()
                $self.UpdateSelectAllState()
            }.GetNewClosure(),
            $true
        )

        $this.ServersGrid.AddHandler(
            [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
            [System.Windows.RoutedEventHandler]{
                param($sender, $e)

                $src = $e.OriginalSource
                if (-not ($src -is [System.Windows.Controls.CheckBox])) { return }

                # Vérifie que c’est le CheckBox du HEADER
                $p = $src
                $isHeader = $false
                while ($p) {
                    if ($p.GetType().Name -eq 'DataGridColumnHeader') { $isHeader = $true; break }
                    $p = [System.Windows.Media.VisualTreeHelper]::GetParent($p)
                }
                if (-not $isHeader) { return }

                $total = $self.ServersCollection.Count
                if ($total -le 0) { return }

                $checked = 0
                foreach ($s in $self.ServersCollection) { if ($s.IsSelected) { $checked++ } }

                $next = ($checked -ne $total)

                foreach ($s in $self.ServersCollection) {
                    $s.IsSelected = $next
                }

                $self.ServersGrid.Items.Refresh()
                $self.UpdateSelectAllState()
                $self.RefreshQueryLimitSuggestions()

                $e.Handled = $true
            }.GetNewClosure(),
            $true
        )

        $this.LimitComboBox.Add_SelectionChanged({
            $item = $self.LimitComboBox.SelectedItem
            if ($item -and $item.PSObject.Properties['RowsPerServer']) {
                $self.App.State.SelectedMaxRowsPerServer = $item.RowsPerServer
            }
        }.GetNewClosure())

        $this.Window.Add_Closing({
            param($sender, $e)
            $self.RequestKillAndClose($sender, $e)
        }.GetNewClosure())
    }

    hidden [void] RequestKillAndClose(
        [object]$sender,
        [System.ComponentModel.CancelEventArgs]$e
    ) {
        if ($this.ForceClose) { return }

        $state = $this.App.State

        if (-not $state.IsRunning -and -not $state.KillRequested) {
            return
        }

        if (-not $state.KillRequested) {
            $state.KillRequested = $true
        }

        $e.Cancel = $true
        $sender.IsEnabled = $false

        $this.SetStatus("Killing...")
        $this.RefreshToolbarFromState()
        $this.SyncExecutionGridFromState()

        if ($this.CloseTimer) {
            return  # déjà en cours
        }

        $timeoutSec = [Math]::Max(3, $this.App.Engine.KillTimeoutSec + 2)
        $deadline = (Get-Date).AddSeconds($timeoutSec)

        $self = $this

        $this.CloseTimer = New-Object System.Windows.Threading.DispatcherTimer
        $this.CloseTimer.Interval = [TimeSpan]::FromMilliseconds(150)

        $this.CloseTimer.Add_Tick({
            try {
                $self.App.Engine.Tick($state)
            } catch {}

            $self.SyncExecutionGridFromState()
            $self.RefreshToolbarFromState()

            $done = (-not $state.IsRunning -and -not $state.KillRequested)
            $timedOut = ((Get-Date) -ge $deadline)

            if ($done -or $timedOut) {
                $self.CloseTimer.Stop()
                $self.CloseTimer = $null

                $self.ForceClose = $true
                $sender.IsEnabled = $true
                $sender.Close()
            }
        }.GetNewClosure())

        $this.CloseTimer.Start()
    }

    hidden [void] StartTimer() {
        $self = $this

        $this.Timer = New-Object System.Windows.Threading.DispatcherTimer
        $this.Timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $this.Timer.Add_Tick({ $self.OnTick() }.GetNewClosure())
        $this.Timer.Start()
    }

    hidden [void] OnRun() {
        if ($this.App.State.IsRunning -or $this.App.State.KillRequested) { return }

        try {
            $selected = @()
            foreach ($row in $this.ServersGrid.ItemsSource) {
                if ($row.PSObject.Properties.Match('IsSelected').Count -gt 0) {
                    if ($row.IsSelected) { $selected += $row }
                } else {
                    # fallback: treat as enabled if no IsSelected flag
                    $selected += $row
                }
            }
            if (-not $selected) { throw "No server selected" }

            $cursor = $this.SqlTextBox.CaretIndex
            $stmt = Get-Statement-AtCursor -Text $this.SqlTextBox.Text -CursorIndex $cursor
            $query = Normalize-Sql $stmt
            if ([string]::IsNullOrWhiteSpace($query)) { throw "SQL query is empty" }

            $this.App.State.ExportCsvRequested = $this.ExportCsvRequested

            if ($this.App.State.ExportCsvRequested) {
                $path = Join-Path ([Environment]::GetFolderPath('Desktop')) (
                    "ReqMultiServ_{0}.csv" -f (Get-Date -UFormat "%Y%m%d_%H%M%S")
                )

                $this.App.State.ExportWriter = [System.IO.StreamWriter]::new($path, $false)
            }

            $limit = $this.App.State.SelectedMaxRowsPerServer
            if ($limit -gt 0) {
                $query = Ensure-QueryLimit -Sql $query -MaxRows $limit
            }

            $this.RefreshToolbarFromState()
            $this.UpdateRunningStatus()

            Reset-ResultsGridState -ResultsGrid $this.ResultsGrid -ResultsCollection $this.ResultsCollection -ResultsCvs $this.ResultsCvs
            Reset-ExecutionGridView -ExecutionGrid $this.ExecutionGrid
            $this.ExecutionCollection.Clear()

            $self = $this;
            $EnsureResultsGridColumns = ${function:Ensure-ResultsGridColumns}
            $this.App.State.OnResultSchema = {
                param($schema)
                & $EnsureResultsGridColumns -ResultsGrid $self.ResultsGrid -Schema $schema

                if ($self.App.State.ExportCsvRequested -and -not $self.App.State.CsvHeaderWritten) {
                    $headers = @('Server') + ($schema.Columns.Header)
                    $self.App.State.ExportWriter.WriteLine(($headers -join ';'))
                    $self.App.State.CsvHeaderWritten = $true
                }
            }.GetNewClosure()

            $this.App.State.OnResultRow = {
                param($row)

                $self.ResultsGrid.Dispatcher.Invoke({
                    if (-not $self.App.State.ExportCsvRequested) {
                        $self.ResultsCollection.Add($row) | Out-Null
                    }
                })

                if ($self.App.State.ExportCsvRequested) {
                    $self.App.State.ExportWriter.WriteLine(
                        ($row.PSObject.Properties.Value -join ';')
                    )
                }
            }.GetNewClosure()

            $this.App.State.CsvHeaderWritten = $false
            $this.RunStartedAt = Get-Date
            $this.RunElapsedText = ""

            $this.App.Service.PrepareExecution(
                $this.App.State,
                ($selected | ForEach-Object { $_ }),
                $query
            )

            $this.SyncExecutionGridFromState()
            $this.RefreshToolbarFromState()
        }
        catch {
            $this.SetStatus($_.Exception.Message, 'error')
            $this.App.State.IsRunning = $false
            $this.RefreshToolbarFromState()
        }
    }

    hidden [void] OnKill() {
        if ($this.App.State.KillRequested -or -not $this.App.State.IsRunning) { return }

        $this.App.State.KillRequested = $true
        $this.RefreshToolbarFromState()
        $this.SetStatus("Killing...")
        $this.SyncExecutionGridFromState()
    }

    hidden [void] OnTick() {
        if (-not $this.App.State.IsRunning -and -not $this.App.State.KillRequested) { return }

        try {
            $this.App.Engine.Tick($this.App.State)
        } catch {}

        $this.SyncExecutionGridFromState()
        $this.RefreshToolbarFromState()
        $this.UpdateRunningStatus()

        if ($this.RunStartedAt) {
            $elapsed = (Get-Date) - $this.RunStartedAt
            $this.RunElapsedText = (
                "{0:hh\:mm\:ss}" -f [TimeSpan]::FromSeconds([math]::Floor($elapsed.TotalSeconds))
            )
        }

        $this.TimerStatusText.Text = $this.RunElapsedText

        if (-not $this.App.State.IsRunning -and -not $this.App.State.KillRequested) {
            $this.App.State.CsvHeaderWritten = $false
            if ($this.App.State.ExportWriter) {
                $this.App.State.ExportWriter.Flush()
                $this.App.State.ExportWriter.Close()
                $this.App.State.ExportWriter = $null
            }
            $this.RunStartedAt = $null
            $this.UpdateFilterStatus()
        }
    }

    hidden [void] SyncExecutionGridFromState() {
        $this.ExecutionCollection.Clear()
        foreach ($w in $this.App.State.ActiveWorkers) {
            $this.ExecutionCollection.Add($w) | Out-Null
        }
    }

    hidden [void] RefreshToolbarFromState() {
        $anyKilling = [bool]($this.App.State.ActiveWorkers | Where-Object { $_.Status -eq 'killing' })
        if ($anyKilling) {
            $this.RunButton.IsEnabled = $false
            $this.ExportButton.IsEnabled = $false
            $this.KillButton.IsEnabled = $false
            $this.SetStatus("Killing...")
            return
        }

        if ($this.App.State.IsRunning) {
            $this.RunButton.IsEnabled = $false
            $this.ExportButton.IsEnabled = $false
            $this.KillButton.IsEnabled = $true
            return
        }

        $this.ExportButton.IsEnabled = $true
        $this.RunButton.IsEnabled = $true
        $this.KillButton.IsEnabled = $false
    }

    hidden [void] SetStatus([string]$text) {
        $this.SetStatus($text, 'info')
    }

    hidden [void] SetStatus([string]$text, [string]$level='info') {
        switch ($level) {
            'error' { $this.StatusText.Foreground = 'Firebrick' }
            'warning' { $this.StatusText.Foreground = 'Blue' }
            default { $this.StatusText.Foreground = 'Black' }
        }
        $this.StatusText.Text = $text
    }

    hidden [void] UpdateRunningStatus() {
        $state = $this.App.State
        if (-not $state.IsRunning) { return }

        $max = $state.MaxConcurrent

        $running = 0
        foreach ($w in $state.ActiveWorkers) {
            if ($w.Status -in @('pending','running','killing')) {
                $running++
            }
        }

        $pending = if ($state.PendingWorkers) { $state.PendingWorkers.Count } else { 0 }
        $total = $state.ActiveWorkers.Count + $pending

        $this.SetStatus(("Running... ({0}/{1} worker(s), {2} queued, {3} total)" -f $running, $max, $pending, $total))
    }

    hidden [void] UpdateFilterStatus() {
        $total = $this.ResultsCvs.Source.Count
        $visible = $this.ResultsCvs.View.Count

        if ([string]::IsNullOrWhiteSpace($this.ResultsFilterText)) {
            $this.SetStatus(("{0} row(s)" -f $total))
        } else {
            $this.SetStatus(("{0} of {1} row(s) (filtered)" -f $visible, $total), 'warning')
        }
    }

    hidden [void] RefreshQueryLimitSuggestions() {

        $selectedServers = @(
            $this.ServersGrid.ItemsSource |
            Where-Object { $_.IsSelected }
        )

        $serverCount = $selectedServers.Count

        if ($serverCount -le 0) {
            $this.LimitComboBox.ItemsSource = @()
            $this.LimitComboBox.SelectedItem = $null
            $this.App.State.SelectedMaxRowsPerServer = 0
            return
        }

        $suggestions = Get-SuggestedQueryLimits `
            -ServerCount $serverCount `
            -MaxTotalRows 100000 |
            ForEach-Object {
                [pscustomobject]@{
                    RowsPerServer = $_.RowsPerServer
                    TotalRows     = $_.TotalRows
                    Display = if ($_.RowsPerServer -eq 0) {
                        "No LIMIT"
                    } else {
                        "LIMIT {0:N0} ({1:N0} total)" -f $_.RowsPerServer, $_.TotalRows
                    }
                }
            }

        $this.LimitComboBox.DisplayMemberPath = 'Display'
        $this.LimitComboBox.ItemsSource = $suggestions

        $current = $this.App.State.SelectedMaxRowsPerServer

        if ($current -gt 0) {
            # tenter de conserver le choix utilisateur
            $match = $suggestions | Where-Object { $_.RowsPerServer -eq $current } | Select-Object -First 1
            if ($match) {
                $this.LimitComboBox.SelectedItem = $match
                return
            }
        }

        $max = $suggestions | Sort-Object RowsPerServer -Descending | Select-Object -First 1
        $this.LimitComboBox.SelectedItem = $max
        $this.App.State.SelectedMaxRowsPerServer = [int]$max.RowsPerServer
    }

    hidden [void] UpdateSelectAllState() {
        $src = $this.ServersCollection
        if (-not $src) { return }

        $total = $src.Count
        if ($total -eq 0) {
            $this.SelectAllCheckBox.IsChecked = $false
            return
        }

        $checked = 0
        foreach ($s in $src) {
            if ($s.IsSelected) { $checked++ }
        }

        if ($checked -eq $total) {
            $this.SelectAllCheckBox.IsChecked = $true
        }
        elseif ($checked -eq 0) {
            $this.SelectAllCheckBox.IsChecked = $false
        }
        else {
            $this.SelectAllCheckBox.IsChecked = $null
        }
    }
}
