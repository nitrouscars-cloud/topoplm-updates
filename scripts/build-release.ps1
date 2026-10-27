param([string]$Root = (Get-Location).Path, [string]$RuntimeCache = '')
$ErrorActionPreference = 'Stop'
$release = Get-Content -LiteralPath (Join-Path $Root 'release.json') -Raw | ConvertFrom-Json
if ($release.version -notmatch '^\d+\.\d+\.\d+$' -or $release.runtimeVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Version de publication invalide.' }
$work = Join-Path $Root 'dist'
$application = Join-Path $work 'TopoPLM'
New-Item -ItemType Directory -Path $application -Force | Out-Null
$archive = Join-Path $work 'application.zip'
$stream = [IO.File]::Create($archive)
try {
 foreach ($part in $release.parts) {
  if ($part -notmatch '^payload/[0-9.]+/application\.\d{3}$') { throw 'Chemin de paquet invalide.' }
  $bytes = [IO.File]::ReadAllBytes((Join-Path $Root $part))
  $stream.Write($bytes, 0, $bytes.Length)
 }
} finally { $stream.Dispose() }
if ((Get-Item -LiteralPath $archive).Length -ne $release.length -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $release.sha256) { throw 'Le paquet compilé a échoué à la vérification.' }
Expand-Archive -LiteralPath $archive -DestinationPath $application -Force
$expected = @('TopoPLM.exe','TopoPLM.dll','TopoPLM.deps.json','TopoPLM.runtimeconfig.json','PdfNative.exe','LISEZ-MOI.txt')
foreach ($item in Get-ChildItem -LiteralPath $application -Recurse -File) { if ($item.Name -notin $expected -or $item.DirectoryName -ne [IO.Path]::GetFullPath($application)) { throw 'Contenu inattendu dans le paquet compilé.' } }
foreach ($name in $expected) { if (-not (Test-Path -LiteralPath (Join-Path $application $name))) { throw "Fichier compilé absent : $name" } }
$runtimeConfig = Get-Content -LiteralPath (Join-Path $application 'TopoPLM.runtimeconfig.json') -Raw | ConvertFrom-Json
if (@($runtimeConfig.runtimeOptions.includedFrameworks | Where-Object { $_.version -ne $release.runtimeVersion }).Count -gt 0) { throw 'Le runtime ne correspond pas au programme compilé.' }
$applicationDeps = Get-Content -LiteralPath (Join-Path $application 'TopoPLM.deps.json') -Raw | ConvertFrom-Json
if ("TopoPLM/$($release.version)" -notin @($applicationDeps.libraries.PSObject.Properties.Name)) { throw 'La version ne correspond pas au programme compilé.' }
foreach ($package in @('microsoft.netcore.app.runtime.win-x64','microsoft.windowsdesktop.app.runtime.win-x64')) {
 $packageDir = if ($RuntimeCache) { Join-Path $RuntimeCache "$package/$($release.runtimeVersion)" } else { '' }
 if (-not $packageDir -or -not (Test-Path -LiteralPath $packageDir)) {
  $zip = Join-Path $work "$package.zip"
  $packageDir = Join-Path $work $package
  Invoke-WebRequest -Uri "https://api.nuget.org/v3-flatcontainer/$package/$($release.runtimeVersion)/$package.$($release.runtimeVersion).nupkg" -OutFile $zip
  Expand-Archive -LiteralPath $zip -DestinationPath $packageDir -Force
 }
 foreach ($sub in @('runtimes/win-x64/native', 'runtimes/win-x64/lib/net8.0')) {
  $from = Join-Path $packageDir $sub
  if (Test-Path -LiteralPath $from) {
   foreach ($item in Get-ChildItem -LiteralPath $from -Recurse -File) {
    if ($item.Extension -notin @('.dll','.exe','.json','.dat')) { continue }
    $to = Join-Path $application ([IO.Path]::GetRelativePath($from, $item.FullName))
    New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force | Out-Null
    Copy-Item -LiteralPath $item.FullName -Destination $to -Force
   }
  }
 }
 $notices = Join-Path $application "licenses/$package-$($release.runtimeVersion)"
 New-Item -ItemType Directory -Path $notices -Force | Out-Null
 Get-ChildItem -LiteralPath $packageDir -File | Where-Object { $_.Name -match 'LICENSE|NOTICE' } | Copy-Item -Destination $notices -Force
}
foreach ($name in @('TopoPLM.exe','TopoPLM.dll','PdfNative.exe','hostfxr.dll','hostpolicy.dll','coreclr.dll','PresentationFramework.dll','WindowsBase.dll')) {
 if (-not (Test-Path -LiteralPath (Join-Path $application $name))) { throw "Composant d’exécution absent : $name" }
}
if ((Get-ChildItem -LiteralPath $application -Recurse -File | Where-Object { $_.Extension -in @('.cs','.pdb','.topoplm') -or $_.Name -like '*Carl*' }).Count -gt 0) { throw 'Le paquet contient des données ou sources interdites.' }
$output = Join-Path $work 'TopoPLM-win-x64.zip'
Compress-Archive -Path (Join-Path $application '*') -DestinationPath $output -Force
Get-FileHash -LiteralPath $output -Algorithm SHA256
