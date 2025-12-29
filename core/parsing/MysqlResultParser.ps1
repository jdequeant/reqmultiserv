Set-StrictMode -Version Latest

class MysqlResultParser {
    static [void] Parse(
        [string] $StdOut,
        [string] $ServerName,
        [System.Action[MysqlResultSchema]] $OnSchema,
        [System.Action[psobject]] $OnRow
    ) {
        $lines = ($StdOut -replace "`r","") -split "`n" |
            ForEach-Object { $_.TrimEnd() } |
            Where-Object { $_ -ne "" }

        if ($lines.Count -lt 2) { return }

        $rawHeaders = $lines[0] -split "`t"
        $used = @{}
        $schema = [MysqlResultSchema]::new()

        foreach ($h in $rawHeaders) {
            $safe = [MysqlResultParser]::Sanitize($h, $used)
            $schema.Columns.Add([MysqlResultColumn]::new($h, $safe))
        }
        try {
            $OnSchema.Invoke($schema)
        } catch {
            Write-Error $_.Exception
        }

        foreach ($line in ($lines | Select-Object -Skip 1)) {
            $values = $line -split "`t"
            $row = [ordered]@{ Server = $ServerName }

            for ($i = 0; $i -lt $schema.Columns.Count; $i++) {
                $row[$schema.Columns[$i].Name] =
                    if ($i -lt $values.Count) { $values[$i] } else { $null }
            }

            try {
                $OnRow.Invoke([pscustomobject]$row)
            } catch {
                Write-Error $_.Exception
            }
            
        }
    }

    static [string] Sanitize([string]$name, [hashtable]$used) {
        if ([string]::IsNullOrWhiteSpace($name)) { $name = "col" }

        $safe = ($name -replace '[^A-Za-z0-9_]', '_')
        if ($safe -match '^\d') { $safe = "c_$safe" }
        if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "col" }

        $base = $safe
        $i = 1
        while ($used.ContainsKey($safe)) {
            $safe = "{0}_{1}" -f $base, $i
            $i++
        }

        $used[$safe] = $true
        return $safe
    }
}
