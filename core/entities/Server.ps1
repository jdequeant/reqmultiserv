class Server {
    [string] $Id
    [string] $Name
    [string] $DbHost
    [int] $Port
    [string] $User
    [string] $Password
    [string] $Database
    [bool] $IsEnabledByDefault
    [bool] $IsSelected

    Server(
        [string] $name,
        [string] $dbHost,
        [int] $port,
        [string] $user,
        [string] $password,
        [string] $database,
        [bool] $isEnabledByDefault
    ) {
        $this.Id = [guid]::NewGuid().ToString()
        $this.Name = $name
        $this.DbHost = $dbHost
        $this.Port = $port
        $this.User = $user
        $this.Password = $password
        $this.Database = $database
        $this.IsEnabledByDefault = $isEnabledByDefault
        $this.IsSelected = $isEnabledByDefault
    }
}