function Initialize-Directory {
    <#
    .SYNOPSIS
    Ensures that a directory exists on disk.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    } catch {
    }
}