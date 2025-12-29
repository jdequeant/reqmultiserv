function Normalize-Sql {
    <#
    .SYNOPSIS
    Normalizes SQL text by stripping inline comments and collapsing whitespace.
    #>
    param([string]$Sql)

    if ($null -eq $Sql) { return "" }

    # Remove inline comments (-- ... / # ...)
    $Sql = $Sql -split "`r?\n" | ForEach-Object {
        $_ -replace '(?<!-)--\s.*$|#.*$', '' | ForEach-Object { $_.TrimEnd() }
    }

    # Flatten newlines
    $Sql = $Sql -replace "`r", " "
    $Sql = $Sql -replace "`n", " "

    # Collapse whitespace
    $Sql = $Sql -replace '\s+', ' '

    return $Sql.Trim()
}

function Get-SqlStatements {
    <#
    .SYNOPSIS
    Splits SQL text into semicolon-terminated statements while respecting quotes.
    #>
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return @() }

    $results = @()
    $current = ""
    $inSingle = $false
    $inDouble = $false
    $startIndex = 0

    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]

        if ($c -eq "'" -and -not $inDouble) { $inSingle = -not $inSingle }
        elseif ($c -eq '"' -and -not $inSingle) { $inDouble = -not $inDouble }

        if ($c -eq ';' -and -not $inSingle -and -not $inDouble) {
            $results += [pscustomobject]@{
                Text = $current.Trim()
                Start = $startIndex
                End = $i
            }
            $current = ""
            $startIndex = $i + 1
        }
        else {
            $current += $c
        }
    }

    if ($current.Trim()) {
        $results += [pscustomobject]@{
            Text = $current.Trim()
            Start = $startIndex
            End = $Text.Length
        }
    }

    return $results
}

function Get-Statement-AtCursor {
    <#
    .SYNOPSIS
    Returns the SQL statement that contains the given caret index.
    #>
    param(
        [string]$Text,
        [int]$CursorIndex
    )

    $stmts = Get-SqlStatements -Text $Text

    foreach ($s in $stmts) {
        if ($CursorIndex -ge $s.Start -and $CursorIndex -le ($s.End + 1)) {
            return $s.Text
        }
    }

    return $null
}
