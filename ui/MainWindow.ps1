param(
    [Parameter(Mandatory)] $App
)

Set-StrictMode -Version Latest
Add-Type -AssemblyName PresentationFramework

# Behaviors / helpers
. (Join-Path $PSScriptRoot "behaviors/GridBehaviors.ps1")
. (Join-Path $PSScriptRoot "behaviors/SqlTextBoxBehaviors.ps1")
. (Join-Path $PSScriptRoot "behaviors/TextBlockBehaviors.ps1")
. (Join-Path $PSScriptRoot "sql/SqlStatements.ps1")
. (Join-Path $PSScriptRoot "sql/SqlLimits.ps1")
. (Join-Path $PSScriptRoot "results/ResultsGridBuilder.ps1")

# Controller
. (Join-Path $PSScriptRoot "MainWindow.Controller.ps1")

# XAML
$xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
[xml]$xaml = Get-Content -LiteralPath $xamlPath -Raw
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))

$iconPath = Join-Path $PSScriptRoot "app.ico"
$uri = [Uri]::new($iconPath, [UriKind]::Absolute)
$window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create($uri)

# Start
$controller = [MainWindowController]::new($App, $window)
$controller.Initialize()
$window.ShowDialog() | Out-Null