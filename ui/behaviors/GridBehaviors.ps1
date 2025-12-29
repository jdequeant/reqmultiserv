function Enable-GridCopyHeaderRule {
    <#
    .SYNOPSIS
    Tweaks Ctrl+C so headers are included for multi-column copies and removed for single-column copies.
    #>
    param(
        [Parameter(Mandatory)] [System.Windows.Controls.DataGrid] $Grid
    )

    $gridRef = $Grid

    $handler = [System.Windows.Input.ExecutedRoutedEventHandler]{
        param($s, $e)
        try {
            if (-not [System.Windows.Clipboard]::ContainsText()) { return }
            $t = [System.Windows.Clipboard]::GetText()
            if (-not $t) { return }
        }
        catch {
            return
        }

        $cols = @(
            $gridRef.SelectedCells |
            Select-Object -ExpandProperty Column -Unique |
            Sort-Object DisplayIndex
        )

        $singleCol = ($cols.Count -eq 1)

        $expectedHeader = ($cols | ForEach-Object {
            if ($null -eq $_.Header) { "" } else { $_.Header.ToString() }
        }) -join "`t"

        $action = [Action]{
            try {
                if (-not [System.Windows.Clipboard]::ContainsText()) { return }
                $t = [System.Windows.Clipboard]::GetText()

                $lines = [System.Text.RegularExpressions.Regex]::Split($t, "\r\n|\n|\r")
                $first = if ($lines.Count -gt 0) { $lines[0] } else { "" }

                $hasHeader = ($first -eq $expectedHeader) -or ($first -eq ("`t" + $expectedHeader))

                if ($singleCol) {
                    if ($hasHeader -and $lines.Count -ge 2) {
                        $t = ($lines[1..($lines.Count-1)] -join "`r`n")
                    } elseif ($hasHeader) {
                        $t = ""
                    }
                } else {
                    for ($i = 0; $i -lt $lines.Count; $i++) {
                        $line = $lines[$i]

                        if ($line.StartsWith('System.')) {
                            $tabIndex = $line.IndexOf("`t")
                            if ($tabIndex -ge 0) {
                                # garder la tab + le reste
                                $lines[$i] = $line.Substring($tabIndex)
                            }
                        }
                    }

                    $t = ($lines -join "`r`n")
                }

                $data = New-Object System.Windows.DataObject
                $data.SetData([System.Windows.DataFormats]::UnicodeText, $t) | Out-Null
                $data.SetData([System.Windows.DataFormats]::Text, $t) | Out-Null
                [System.Windows.Clipboard]::SetDataObject($data, $true)
            } catch {}
        }.GetNewClosure()

        $gridRef.Dispatcher.BeginInvoke($action, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
    }.GetNewClosure()

    [System.Windows.Input.CommandManager]::AddPreviewExecutedHandler($gridRef, $handler)
}

function Enable-GridSelectAllFocus {
    <#
    .SYNOPSIS
    Forces SelectAll (Ctrl+A) to focus the grid and select all rows reliably.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid] $Grid
    )

    # évite doublons si appelée plusieurs fois
    if (-not $Grid.Tag) { $Grid.Tag = @{} }
    if ($Grid.Tag.ContainsKey('SelectAllFocusBound')) { return }
    $Grid.Tag.SelectAllFocusBound = $true

    $onCanExecute = [System.Windows.Input.CanExecuteRoutedEventHandler]{
        param($s, $e)
        $e.CanExecute = $true
        $e.Handled = $true
    }

    $onExecuted = [System.Windows.Input.ExecutedRoutedEventHandler]{
        param($s, $e)

        $dg = [System.Windows.Controls.DataGrid]$s

        # focus clavier réel
        $dg.Focus() | Out-Null
        [System.Windows.Input.Keyboard]::Focus($dg) | Out-Null

        # exécute l'action
        $dg.SelectAll()

        $e.Handled = $true
    }

    $Grid.CommandBindings.Add(
        (New-Object System.Windows.Input.CommandBinding([System.Windows.Controls.DataGrid]::SelectAllCommand, $onExecuted, $onCanExecute))
    ) | Out-Null
}

function Enable-GridAutoDeselectOnBlur {
    <#
    .SYNOPSIS
    Clears selection when focus leaves the grid to avoid sticky highlights.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid] $Grid
    )

    $Grid.AddHandler(
        [System.Windows.UIElement]::LostKeyboardFocusEvent,
        [System.Windows.Input.KeyboardFocusChangedEventHandler]{
            param($sender, $e)

            $newFocus = $e.NewFocus
            $inside = $false

            if ($newFocus -is [System.Windows.DependencyObject]) {
                $cur = $newFocus
                while ($cur) {
                    if ($cur -eq $sender) { $inside = $true; break }
                    $cur = [System.Windows.Media.VisualTreeHelper]::GetParent($cur)
                }
            }

            if (-not $inside) {
                $sender.UnselectAll()
                $sender.UnselectAllCells()
                $sender.ClearValue([System.Windows.Controls.DataGrid]::CurrentCellProperty)
            }
        },
        $true
    )
}

function Get-DataGridRowFromEvent {
    <#
    .SYNOPSIS
    Resolves the DataGridRow that originated a routed UI event.
    #>
    param(
        [System.Windows.Controls.DataGrid] $Grid,
        [System.Windows.RoutedEventArgs] $Event
    )

    $dep = $Event.OriginalSource
    while ($dep -and -not ($dep -is [System.Windows.Controls.DataGridRow])) {
        $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
    }

    return $dep
}