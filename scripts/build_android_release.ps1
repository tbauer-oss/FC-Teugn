param(
    [Parameter(Mandatory = $true)][string]$FlutterSdk,
    [ValidateSet('apk', 'appbundle')][string[]]$Targets = @('apk', 'appbundle')
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$appRoot = Join-Path $projectRoot 'fc_teugn_app'
$signingProperties = Join-Path $appRoot 'android/key.properties'
$signingSource = Join-Path $appRoot 'android/app/fc-teugn-talents-signing.dpapi.json'
$keystore = Join-Path $appRoot 'android/app/fc-teugn-talents-release.jks'
$createdSigningFile = $false
$previousJavaOptions = $env:JAVA_TOOL_OPTIONS
$previousSigningRequirement = $env:FC_TEUGN_REQUIRE_RELEASE_SIGNING
$socketDirectory = Join-Path $projectRoot 'tmp/java-sockets'
New-Item -ItemType Directory -Path $socketDirectory -Force | Out-Null

function ConvertTo-JavaProperty([string]$Value) {
    return -join ($Value.ToCharArray() | ForEach-Object { '\u{0:x4}' -f [int]$_ })
}

try {
    if (-not (Test-Path -LiteralPath $signingProperties)) {
        if (-not (Test-Path -LiteralPath $keystore) -or -not (Test-Path -LiteralPath $signingSource)) {
            throw 'Lokaler Signaturschlüssel fehlt. Den signierten GitHub-Workflow verwenden.'
        }
        $protectedSigning = Get-Content -LiteralPath $signingSource -Raw | ConvertFrom-Json
        $securePassword = ConvertTo-SecureString $protectedSigning.encryptedPassword
        $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        try {
            $encodedPassword = ConvertTo-JavaProperty ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer))
            $encodedAlias = ConvertTo-JavaProperty $protectedSigning.alias
            $properties = "storePassword=$encodedPassword`nkeyPassword=$encodedPassword`nkeyAlias=$encodedAlias`nstoreFile=fc-teugn-talents-release.jks`n"
            [IO.File]::WriteAllText($signingProperties, $properties, [Text.UTF8Encoding]::new($false))
            $createdSigningFile = $true
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
            $encodedPassword = $null
            $properties = $null
            $securePassword.Dispose()
        }
    }
    $env:JAVA_TOOL_OPTIONS = "$previousJavaOptions -Djdk.net.unixdomain.tmpdir=`"$socketDirectory`"".Trim()
    $env:FC_TEUGN_REQUIRE_RELEASE_SIGNING = 'true'
    $dart = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
    $packages = Join-Path $FlutterSdk 'packages/flutter_tools/.dart_tool/package_config.json'
    $snapshot = Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
    Push-Location $appRoot
    try {
        foreach ($target in $Targets) {
            & $dart "--packages=$packages" $snapshot build $target --release
            if ($LASTEXITCODE -ne 0) { throw "Android-$target-Build fehlgeschlagen (Exitcode $LASTEXITCODE)." }
        }
    } finally { Pop-Location }
} finally {
    if ($createdSigningFile) { Remove-Item -LiteralPath $signingProperties -Force }
    $env:JAVA_TOOL_OPTIONS = $previousJavaOptions
    $env:FC_TEUGN_REQUIRE_RELEASE_SIGNING = $previousSigningRequirement
}
