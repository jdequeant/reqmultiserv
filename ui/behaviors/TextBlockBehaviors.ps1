# ui/behaviors/TrimmedTooltips.ps1
Set-StrictMode -Version Latest

function Enable-TrimmedTextTooltipsGlobal {
    <#
    .SYNOPSIS
    Shows a tooltip only when a TextBlock is actually trimmed (ellipsis).
    Works with DataGrid virtualization and manual column resizing (PS5/.NET Framework).
    #>

    if (Test-Path Variable:\script:TrimmedTooltipsEnabled) { return }
    $script:TrimmedTooltipsEnabled = $true

    $update = {
        param([System.Windows.Controls.TextBlock] $tb)

        if ($null -eq $tb) { return }

        # Only for "ellipsis" scenarios
        if ($tb.TextWrapping -ne [System.Windows.TextWrapping]::NoWrap -or
            $tb.TextTrimming -eq [System.Windows.TextTrimming]::None) {
            $tb.ClearValue([System.Windows.FrameworkElement]::ToolTipProperty)
            return
        }

        $text = $tb.Text
        if ([string]::IsNullOrEmpty($text)) {
            $tb.ClearValue([System.Windows.FrameworkElement]::ToolTipProperty)
            return
        }

        # Ensure layout is current (critical after manual column resize)
        $tb.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
        $tb.UpdateLayout()

        if ($tb.ActualWidth -le 0) {
            $tb.ClearValue([System.Windows.FrameworkElement]::ToolTipProperty)
            return
        }

        # Measure natural width and compare to available width
        $tb.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        $isTrimmed = ($tb.DesiredSize.Width -gt ($tb.ActualWidth + 0.5))

        if ($isTrimmed) {
            $tb.ToolTip = $text
        } else {
            $tb.ClearValue([System.Windows.FrameworkElement]::ToolTipProperty)
        }
    }.GetNewClosure()

    $onMouseEnter = [System.Windows.Input.MouseEventHandler]{
        param($sender, $e)
        & $update ([System.Windows.Controls.TextBlock]$sender)
    }.GetNewClosure()

    $onSizeChanged = [System.Windows.SizeChangedEventHandler]{
        param($sender, $e)
        & $update ([System.Windows.Controls.TextBlock]$sender)
    }.GetNewClosure()

    [System.Windows.EventManager]::RegisterClassHandler(
        [System.Windows.Controls.TextBlock],
        [System.Windows.UIElement]::MouseEnterEvent,
        $onMouseEnter,
        $true
    )

    [System.Windows.EventManager]::RegisterClassHandler(
        [System.Windows.Controls.TextBlock],
        [System.Windows.FrameworkElement]::SizeChangedEvent,
        $onSizeChanged,
        $true
    )
}

function New-EllipsisTextBlockStyle {
    <#
    .SYNOPSIS
    Creates a TextBlock style for DataGridTextColumn cells (NoWrap + Ellipsis).
    #>
    $s = New-Object System.Windows.Style([System.Windows.Controls.TextBlock])

    $s.Setters.Add((New-Object System.Windows.Setter(
        [System.Windows.Controls.TextBlock]::TextWrappingProperty,
        [System.Windows.TextWrapping]::NoWrap
    ))) | Out-Null

    $s.Setters.Add((New-Object System.Windows.Setter(
        [System.Windows.Controls.TextBlock]::TextTrimmingProperty,
        [System.Windows.TextTrimming]::CharacterEllipsis
    ))) | Out-Null

    return $s
}

function Enable-EllipsisOnGridTextColumns {
    <#
    .SYNOPSIS
    Applies an ElementStyle to all current and future DataGridTextColumn in a DataGrid.
    #>
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid] $Grid
    )

    # Avoid double binding
    if (-not $Grid.Tag) { $Grid.Tag = @{} }
    if ($Grid.Tag.ContainsKey('EllipsisTextColumnsBound')) { return }
    $Grid.Tag.EllipsisTextColumnsBound = $true

    # Existing columns (XAML-defined or programmatic)
    foreach ($col in @($Grid.Columns)) {
        if ($col -is [System.Windows.Controls.DataGridTextColumn]) {
            $col.ElementStyle = New-EllipsisTextBlockStyle
        }
    }

    # Future columns (AutoGenerateColumns=True or dynamic add)
    $Grid.Add_AutoGeneratingColumn({
        param($s, $e)
        if ($e.Column -is [System.Windows.Controls.DataGridTextColumn]) {
            $e.Column.ElementStyle = New-EllipsisTextBlockStyle
        }
    }.GetNewClosure())
}
