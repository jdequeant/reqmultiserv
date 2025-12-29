function Enable-SqlTextBoxTabIndent {
    <#
    .SYNOPSIS
    Enables Tab/Shift+Tab indentation on a multi-line TextBox without inserting focus navigation.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox] $TextBox,

        [int] $IndentSize = 4
    )

    if (-not $TextBox.Tag) { $TextBox.Tag = @{} }
    if ($TextBox.Tag.ContainsKey('SqlTabIndentBound')) { return }
    $TextBox.Tag.SqlTabIndentBound = $true

    $TextBox.Add_PreviewKeyDown({
        param($sender, $e)

        if ($e.Key -ne 'Tab') { return }
        $e.Handled = $true

        $tb = [System.Windows.Controls.TextBox]$sender
        $tab = (' ' * $IndentSize)

        $start = $tb.SelectionStart
        $length = $tb.SelectionLength
        $text = $tb.Text

        # Find impacted line range (based on LF) and exclude a trailing CR
        $lineStart = $text.LastIndexOf("`n", [Math]::Max(0, $start - 1))
        if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart++ }

        $lineEnd = if ($length -gt 0) {
            $text.IndexOf("`n", $start + $length)
        } else {
            $text.IndexOf("`n", $start)
        }
        if ($lineEnd -lt 0) { $lineEnd = $text.Length }

        if ($lineEnd -gt $lineStart -and $text[$lineEnd - 1] -eq "`r") {
            $lineEnd--
        }

        $block = $text.Substring($lineStart, $lineEnd - $lineStart)
        $lines = [System.Text.RegularExpressions.Regex]::Split($block, "\r\n|\n|\r")

        if ($e.KeyboardDevice.Modifiers -band [System.Windows.Input.ModifierKeys]::Shift) {
            # Shift+Tab => unindent
            $lines = $lines | ForEach-Object {
                if ($_ -match "^(?:$([regex]::Escape($tab)))") { $_.Substring($tab.Length) }
                elseif ($_ -match "^\s") { $_.Substring(1) }
                else { $_ }
            }
        } else {
            # Tab => indent
            $lines = $lines | ForEach-Object { $tab + $_ }
        }

        $newBlock = ($lines -join "`r`n")

        $tb.Text =
            $text.Substring(0, $lineStart) +
            $newBlock +
            $text.Substring($lineEnd)

        $tb.CaretIndex = $lineStart + $newBlock.Length
    }.GetNewClosure())
}

function Enable-WindowCtrlEnterToRun {
    <#
    .SYNOPSIS
    Binds Ctrl+Enter on the window to trigger a given Run button click.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window] $Window,

        [Parameter(Mandatory)]
        [System.Windows.Controls.Button] $RunButton
    )

    if (-not $Window.Tag) { $Window.Tag = @{} }
    if ($Window.Tag.ContainsKey('CtrlEnterRunBound')) { return }
    $Window.Tag.CtrlEnterRunBound = $true

    $btn = $RunButton

    $handler = [System.Windows.Input.KeyEventHandler]{
        param($_sender, $e)

        if ($e.Key -eq 'Enter' -and ($e.KeyboardDevice.Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
            $e.Handled = $true
            $btn.RaiseEvent(
                [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
            )
        }
    }.GetNewClosure()

    $Window.AddHandler([System.Windows.UIElement]::PreviewKeyDownEvent, $handler)
}

function Enable-TextBoxDebouncedAutoSave {
    <#
    .SYNOPSIS
    Persists the SQL editor content only when it has changed since last save.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox] $TextBox,

        [Parameter(Mandatory)]
        [string] $Path,

        [int] $DelaySeconds = 5
    )

    $lastHash = ""
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds($DelaySeconds)

    $timer.Add_Tick({
        $timer.Stop()

        try {
            $text = $TextBox.Text
            $hash = [BitConverter]::ToString(
                [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                    [System.Text.Encoding]::UTF8.GetBytes($text)
                )
            )

            if ($hash -ne $lastHash) {
                New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
                [System.IO.File]::WriteAllText(
                    $Path,
                    $text,
                    [System.Text.Encoding]::UTF8
                )
                $lastHash = $hash
            }
        } catch {}
    }.GetNewClosure())

    # restore on load (IMPORTANT: before TextChanged fires)
    if (Test-Path $Path) {
        try {
            $TextBox.Text = Get-Content $Path -Raw
            $lastHash = [BitConverter]::ToString(
                [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                    [System.Text.Encoding]::UTF8.GetBytes($TextBox.Text)
                )
            )
        } catch {}
    }

    $TextBox.Add_TextChanged({
        $timer.Stop()
        $timer.Start()
    }.GetNewClosure())
}
