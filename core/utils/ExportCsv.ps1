function Export-FinalCsv {
    <#
    .SYNOPSIS
    Exports the current result set to a CSV file on the desktop.
    #>
    param([System.Collections.ObjectModel.ObservableCollection[object]]$Rows)

    if (-not $Rows -or $Rows.Count -eq 0) { return }

    $path = Join-Path ([Environment]::GetFolderPath('Desktop')) "ReqMultiServ_$(Get-Date -Format yyyyMMdd_HHmmss).csv"

    $first = $Rows[0]
    $headers = @()
    foreach ($p in $first.PSObject.Properties) { $headers += $p.Name }

    Add-Content -Path $path -Value ($headers -join ';')

    foreach ($row in $Rows) {
        $vals = @()
        foreach ($h in $headers) {
            $v = $row.$h
            if ($null -eq $v) { $vals += '' }
            else { $vals += ($v.ToString().Replace(';',',')) }
        }
        Add-Content -Path $path -Value ($vals -join ';')
    }
}
