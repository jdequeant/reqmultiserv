function Ensure-QueryLimit {
    <#
    .SYNOPSIS
    Ensures a safe top-level LIMIT clause is present on a SELECT query to prevent excessive result sets.
    #>
    param(
        [string]$Sql,
        [int]$MaxRows
    )

    if ([string]::IsNullOrWhiteSpace($Sql)) {
        return $Sql
    }

    # No limit requested
    if ($MaxRows -le 0) {
        return $Sql.TrimEnd().TrimEnd(';')
    }

    $trimmed = $Sql.TrimEnd()

    if ($trimmed.EndsWith(";")) {
        $trimmed = $trimmed.Substring(0, $trimmed.Length - 1)
    }

    # Regex LIMIT top-level
    $hasLimit = $trimmed -match '(?is)\blimit\s+(\d+|\?|:\w+)(\s*,\s*\d+|\s+offset\s+\d+)?\s*$'

    if ($hasLimit) {
        return $trimmed
    }

    return "$trimmed LIMIT $MaxRows"
}

function Get-SuggestedQueryLimits {
    <#
    .SYNOPSIS
    Computes safe LIMIT values based on selected server count.
    #>
    param(
        [int] $ServerCount,
        [int] $MaxTotalRows = 100000
    )

    if ($ServerCount -le 0) { return @() }

    $limits = @(
        [pscustomobject]@{
            RowsPerServer = 0
            TotalRows     = 0
        }
    )

    $multipliers = @(1, 5, 10, 50, 100, 1000, 10000, 50000)

    foreach ($m in $multipliers) {
        $total = $ServerCount * $m
        if ($total -le $MaxTotalRows) {
            $limits += [pscustomobject]@{
                RowsPerServer = $m
                TotalRows = $total
            }
        }
    }

    return $limits
}
