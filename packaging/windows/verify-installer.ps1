param([string] $InstallerPath)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (!$InstallerPath) { $InstallerPath = Join-Path $repo 'build/installer/electrowave-setup.msi' }
$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $installer.OpenDatabase((Resolve-Path -LiteralPath $InstallerPath).Path, 0)
function Rows([string] $sql) {
    $view = $database.OpenView($sql)
    $null = $view.Execute()
    try {
        while ($record = $view.Fetch()) {
            $count = $record.GetType().InvokeMember('FieldCount', [Reflection.BindingFlags]::GetProperty, $null, $record, $null)
            $values = for ($index = 1; $index -le $count; $index++) { $record.StringData($index) }
            [pscustomobject]@{ Values = @($values) }
        }
    } finally { $null = $view.Close() }
}
$files = @(Rows 'SELECT `FileName` FROM `File`')
if ($files.Count -lt 10) { throw 'The installer is missing its application bundle' }
$names = @($files | ForEach-Object { $_.Values[0] })
if (!($names | Where-Object { $_ -match 'electrowave.exe$' })) { throw 'The app executable is missing' }
if ($names | Where-Object { $_ -match 'portable$|electrowave.sqlite$|settings.json$' }) { throw 'Test or user data leaked into the installer' }
$shortcuts = @(Rows 'SELECT `Name` FROM `Shortcut`')
if ($shortcuts.Count -ne 2) { throw 'Expected Start menu and uninstaller shortcuts' }
$keys = @(Rows 'SELECT `Key` FROM `Registry`' | ForEach-Object { $_.Values[0] })
foreach ($extension in @('.mp3', '.flac', '.m3u8')) {
    if (!($keys | Where-Object { $_ -eq "Software\Classes\$extension\OpenWithProgids" })) { throw "Missing $extension association" }
}
$properties = @{}
Rows 'SELECT `Property`, `Value` FROM `Property`' | ForEach-Object { $properties[$_.Values[0]] = $_.Values[1] }
$versionLine = Get-Content -LiteralPath (Join-Path $repo 'pubspec.yaml') | Where-Object { $_ -match '^version:' } | Select-Object -First 1
$version = ($versionLine -replace '^version:\s*', '') -replace '\+.*$', ''
if ($properties['ProductVersion'] -ne $version) { throw 'Installer version differs from pubspec.yaml' }
if ($properties['ProductName'] -ne 'Electrowave') { throw 'Incorrect product identity' }
Write-Output "Verified MSI: $($files.Count) bundled files, 2 shortcuts, 3 associations, version $version."
