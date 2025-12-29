class MysqlResultColumn {
    [string] $Header
    [string] $Name

    MysqlResultColumn([string]$header, [string]$name) {
        $this.Header = $header
        $this.Name = $name
    }
}

class MysqlResultSchema {
    [System.Collections.Generic.List[MysqlResultColumn]] $Columns

    MysqlResultSchema() {
        $this.Columns = [System.Collections.Generic.List[MysqlResultColumn]]::new()
    }
}