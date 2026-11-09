param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArgs)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$localFlutter = Join-Path $projectRoot '.tooling/flutter/bin/flutter.bat'
if (Test-Path -LiteralPath $localFlutter) {
    $flutterCommand = $localFlutter
    $env:PUB_CACHE = Join-Path $projectRoot '.tooling/pub-cache'
} else {
    $flutterCommand = (Get-Command flutter -ErrorAction Stop).Source
}
$env:GRADLE_USER_HOME = Join-Path $projectRoot '.tooling/gradle'
$socketDirectory = Join-Path $projectRoot '.tooling/tmp'
New-Item -ItemType Directory -Path $socketDirectory -Force | Out-Null
# JDK 23 uses Windows Unix-domain socket paths. Keep the temp path short.
if ($env:JAVA_TOOL_OPTIONS -notmatch '-Djdk.net.unixdomain.tmpdir=') {
    $env:JAVA_TOOL_OPTIONS = ($env:JAVA_TOOL_OPTIONS + ' -Djdk.net.unixdomain.tmpdir="' + $socketDirectory + '"').Trim()
}
$localAndroid = Join-Path $projectRoot '.tooling/android-sdk'
if (Test-Path -LiteralPath $localAndroid) { $env:ANDROID_HOME = $localAndroid }
if (!$FlutterArgs) { $FlutterArgs = @('analyze') }
Push-Location $projectRoot
try { & $flutterCommand @FlutterArgs; $flutterExit = $LASTEXITCODE }
finally { Pop-Location }
exit $flutterExit
