function Ensure-ResultsGridColumns {
    <#
    .SYNOPSIS
    Creates DataGrid columns once, using safe property names for bindings and showing raw headers.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid] $ResultsGrid,

        [Parameter(Mandatory)]
        [object] $Schema
    )

    if ($ResultsGrid.Columns.Count -gt 0) { return }

    $ResultsGrid.AutoGenerateColumns = $false
    $ResultsGrid.Columns.Clear()

    # TextBlock style applied to every DataGridTextColumn (ellipsis + tooltip behavior relies on trimming)
    $tbStyle = New-Object System.Windows.Style([System.Windows.Controls.TextBlock])
    $tbStyle.Setters.Add(
        (New-Object System.Windows.Setter(
            [System.Windows.Controls.TextBlock]::TextTrimmingProperty,
            [System.Windows.TextTrimming]::CharacterEllipsis
        ))
    ) | Out-Null

    # Server column first
    $colServer = New-Object System.Windows.Controls.DataGridTextColumn
    $colServer.Header  = "Server"
    $colServer.Binding = New-Object System.Windows.Data.Binding("Server")
    $colServer.ElementStyle = $tbStyle
    $ResultsGrid.Columns.Add($colServer) | Out-Null

    foreach ($c in $Schema.Columns) {
        $col = New-Object System.Windows.Controls.DataGridTextColumn
        $col.Header  = $c.Header
        $col.Binding = New-Object System.Windows.Data.Binding($c.Name)
        $col.ElementStyle = $tbStyle
        $ResultsGrid.Columns.Add($col) | Out-Null
    }
}

function Reset-ResultsGridState {
    <#
    .SYNOPSIS
    Resets the result collections and binds a fresh CollectionViewSource to the DataGrid.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid] $ResultsGrid,

        [System.Collections.ObjectModel.ObservableCollection[object]] $ResultsCollection,

        [Parameter(Mandatory)]
        [System.Windows.Data.CollectionViewSource] $ResultsCvs
    )

    $ResultsGrid.Columns.Clear()
    $ResultsCollection.Clear()
    $ResultsCvs.Source = $ResultsCollection
    $ResultsGrid.ItemsSource = $ResultsCvs.View
}

function Reset-ExecutionGridView {
    <#
    .SYNOPSIS
    Clears sorting on the execution grid to keep updates predictable.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid] $ExecutionGrid
    )

    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($ExecutionGrid.ItemsSource)
    if ($view) {
        $view.SortDescriptions.Clear()
        $view.Refresh()
    }
}
