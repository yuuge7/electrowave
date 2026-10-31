$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$versionLine = Get-Content -LiteralPath (Join-Path $repo 'pubspec.yaml') | Where-Object { $_ -match '^version:' } | Select-Object -First 1
$appVersion = ($versionLine -replace '^version:\s*', '') -replace '\+.*$', ''
if ($appVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid pubspec version' }
$bundle = Join-Path $repo 'build/windows/x64/runner/Release'
if (!(Test-Path -LiteralPath (Join-Path $bundle 'electrowave.exe'))) { throw 'Run flutter build windows --release first' }
# App-local Visual C++ runtime, as required by Flutter's Windows deployment
# guide, so installation works on machines without Visual Studio.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (Test-Path -LiteralPath $vswhere) {
    $visualStudio = & $vswhere -latest -products '*' -property installationPath
    $redist = Join-Path $visualStudio 'VC/Redist/MSVC'
    foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        $runtime = Get-ChildItem -LiteralPath $redist -Recurse -Filter $name | Where-Object { $_.FullName -match '\\x64\\Microsoft.VC\d+\.CRT\\' } | Sort-Object FullName -Descending | Select-Object -First 1
        if (!$runtime) { throw "Visual C++ runtime not found: $name" }
        Copy-Item -LiteralPath $runtime.FullName -Destination (Join-Path $bundle $name) -Force
    }
} else { throw 'Visual Studio runtime redistributables were not found' }
$toolFolder = Join-Path $repo 'build/tooling/wix4'
$compilerPath = Join-Path $toolFolder 'wix.exe'
if (!(Test-Path -LiteralPath $compilerPath)) {
    & dotnet tool install wix --version 4.0.6 --tool-path $toolFolder
    if ($LASTEXITCODE -ne 0) { throw 'Could not install the WiX compiler from NuGet' }
}
$output = Join-Path $repo 'build/installer'
New-Item -ItemType Directory -Path $output -Force | Out-Null

function Escape-Xml([string] $value) { return [System.Security.SecurityElement]::Escape($value) }
function Stable-Id([string] $value) {
    $hash = [System.Security.Cryptography.SHA256]::Create()
    try { return 'E' + ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($value)))).Replace('-', '').Substring(0, 40) }
    finally { $hash.Dispose() }
}
function Bundle-Xml([string] $folder) {
    $xml = [Text.StringBuilder]::new()
    foreach ($entry in Get-ChildItem -LiteralPath $folder | Sort-Object Name) {
        if ($entry.Name -eq 'portable' -or $entry.Name -eq 'ElectrowaveData') { continue }
        $relative = $entry.FullName.Substring($bundle.Length).TrimStart('\')
        $id = Stable-Id $relative
        if ($entry.PSIsContainer) {
            [void] $xml.Append('<Directory Id="D' + $id + '" Name="' + (Escape-Xml $entry.Name) + '">')
            [void] $xml.Append((Bundle-Xml $entry.FullName))
            [void] $xml.Append('</Directory>')
        } else {
            [void] $xml.Append('<Component Id="C' + $id + '" Guid="*" Bitness="always64"><File Id="F' + $id + '" Source="' + (Escape-Xml $entry.FullName) + '" KeyPath="yes" /></Component>')
        }
    }
    return $xml.ToString()
}
$files = Bundle-Xml $bundle
$icon = Escape-Xml (Join-Path $repo 'windows/runner/resources/app_icon.ico')
$source = @"
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package Name="Electrowave" Manufacturer="Electrowave contributors" Version="$appVersion" UpgradeCode="A77430BD-64C4-4A83-87B8-494702F39125" Scope="perUser" InstallerVersion="500">
    <MajorUpgrade DowngradeErrorMessage="A newer version of Electrowave is already installed." />
    <MediaTemplate EmbedCab="yes" CompressionLevel="high" />
    <Icon Id="AppIcon" SourceFile="$icon" />
    <Property Id="ARPPRODUCTICON" Value="AppIcon" />
    <StandardDirectory Id="LocalAppDataFolder">
      <Directory Id="ProgramsFolder" Name="Programs">
        <Directory Id="INSTALLFOLDER" Name="Electrowave">
          $files
          <Component Id="Associations" Guid="*">
            <RegistryValue Root="HKCU" Key="Software\Classes\Electrowave.Audio" Type="string" Value="Electrowave audio file" KeyPath="yes" />
            <RegistryValue Root="HKCU" Key="Software\Classes\Electrowave.Audio\DefaultIcon" Type="string" Value="[INSTALLFOLDER]electrowave.exe,0" />
            <RegistryValue Root="HKCU" Key="Software\Classes\Electrowave.Audio\shell\open\command" Type="string" Value="&quot;[INSTALLFOLDER]electrowave.exe&quot; &quot;%1&quot;" />
            <RegistryValue Root="HKCU" Key="Software\Classes\.mp3\OpenWithProgids" Name="Electrowave.Audio" Type="string" Value="" />
            <RegistryValue Root="HKCU" Key="Software\Classes\.flac\OpenWithProgids" Name="Electrowave.Audio" Type="string" Value="" />
            <RegistryValue Root="HKCU" Key="Software\Classes\.m3u8\OpenWithProgids" Name="Electrowave.Audio" Type="string" Value="" />
          </Component>
        </Directory>
      </Directory>
    </StandardDirectory>
    <StandardDirectory Id="ProgramMenuFolder">
      <Directory Id="AppMenuFolder" Name="Electrowave">
        <Component Id="StartMenu" Guid="*">
          <Shortcut Id="StartShortcut" Name="Electrowave" Target="[INSTALLFOLDER]electrowave.exe" WorkingDirectory="INSTALLFOLDER" Icon="AppIcon" />
          <Shortcut Id="UninstallShortcut" Name="Uninstall Electrowave" Target="[SystemFolder]msiexec.exe" Arguments="/x [ProductCode]" />
          <RemoveFolder Id="RemoveAppMenuFolder" On="uninstall" />
          <RegistryValue Root="HKCU" Key="Software\Electrowave" Name="Installed" Type="integer" Value="1" KeyPath="yes" />
        </Component>
      </Directory>
    </StandardDirectory>
    <Feature Id="MainFeature" Title="Electrowave" Level="1">
      <ComponentGroupRef Id="BundleComponents" />
    </Feature>
  </Package>
  <Fragment>
    <ComponentGroup Id="BundleComponents">
      <ComponentRef Id="Associations" />
      <ComponentRef Id="StartMenu" />
      $((Get-ChildItem -LiteralPath $bundle -Recurse -File | Where-Object { $_.Name -ne 'portable' -and $_.FullName -notlike '*\ElectrowaveData\*' } | ForEach-Object { '<ComponentRef Id="C' + (Stable-Id $_.FullName.Substring($bundle.Length).TrimStart('\')) + '" />' }) -join "`n")
    </ComponentGroup>
  </Fragment>
</Wix>
"@
$sourceFile = Join-Path $output 'electrowave.wxs'
[IO.File]::WriteAllText($sourceFile, $source, [Text.UTF8Encoding]::new($false))
& $compilerPath build $sourceFile -arch x64 -o (Join-Path $output 'electrowave-setup.msi')
if ($LASTEXITCODE -ne 0) { throw "Installer compilation failed ($LASTEXITCODE)" }
& (Join-Path $PSScriptRoot 'verify-installer.ps1')
